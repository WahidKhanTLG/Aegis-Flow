/**
 * Groups repeating failures into Incident__c (spec sections 8.1 and EPIC-05).
 *
 * Without grouping, 500 rows failing the same validation rule produce 500 unrelated
 * error logs, 500 diagnosis requests, and a Command Center that cannot report recurring
 * incidents, affected users, or top failing sources. Grouping is what makes the volume
 * story tractable: diagnose once per incident, not once per failed row.
 *
 * The incident key is derived from source type, source name, normalized category,
 * failed element, and a time bucket, so an unrelated failure tomorrow starts a new
 * incident rather than inflating yesterday's.
 */
public without sharing class AEIR_IncidentAggregationService {

    /** Occurrences within the same bucket roll into one incident. */
    @TestVisible
    private static final Integer BUCKET_MINUTES = 60;

    private static final Map<String, Integer> SEVERITY_RANK = new Map<String, Integer>{
        'LOW' => 1, 'MEDIUM' => 2, 'HIGH' => 3, 'CRITICAL' => 4
    };
    private static final Map<Integer, String> RANK_SEVERITY = new Map<Integer, String>{
        1 => 'Low', 2 => 'Medium', 3 => 'High', 4 => 'Critical'
    };

    /**
     * Assigns each log to an incident, creating or updating incidents as needed.
     * Bulk-safe: two queries and at most two DML statements regardless of input size.
     *
     * Callers must persist the logs afterwards; this sets Incident__c and
     * Incident_Key__c on the in-memory records without issuing DML on them.
     */
    public static void assign(List<Error_Log__c> logs) {
        if (logs == null || logs.isEmpty()) return;

        Datetime nowValue = Datetime.now();
        Map<String, List<Error_Log__c>> byKey = new Map<String, List<Error_Log__c>>();
        for (Error_Log__c log : logs) {
            if (log == null) continue;
            String key = buildKey(log, nowValue);
            log.Incident_Key__c = key;
            if (!byKey.containsKey(key)) byKey.put(key, new List<Error_Log__c>());
            byKey.get(key).add(log);
        }
        if (byKey.isEmpty()) return;

        Set<String> keys = byKey.keySet();
        Map<String, Incident__c> existing = new Map<String, Incident__c>();
        Map<String, Object> incidentBinds = new Map<String, Object>{ 'incidentKeys' => keys };
        for (Incident__c incident : (List<Incident__c>) Database.queryWithBinds(
            'SELECT Id, Incident_Key__c, Occurrence_Count__c, Affected_Record_Count__c, Affected_User_Count__c, '
            + 'First_Seen_At__c, Last_Seen_At__c, Highest_Severity__c, Status__c '
            + 'FROM Incident__c WHERE Incident_Key__c IN :incidentKeys',
            incidentBinds,
            AccessLevel.SYSTEM_MODE
        )) {
            existing.put(incident.Incident_Key__c, incident);
        }

        // Distinct record and user counts need history, not just this batch.
        Map<String, Set<String>> knownRecords = new Map<String, Set<String>>();
        Map<String, Set<String>> knownUsers = new Map<String, Set<String>>();
        if (!existing.isEmpty()) {
            for (Error_Log__c prior : (List<Error_Log__c>) Database.queryWithBinds(
                'SELECT Incident_Key__c, Record_Id__c, User__c '
                + 'FROM Error_Log__c WHERE Incident_Key__c IN :incidentKeys LIMIT 10000',
                incidentBinds,
                AccessLevel.SYSTEM_MODE
            )) {
                addTo(knownRecords, prior.Incident_Key__c, prior.Record_Id__c);
                addTo(knownUsers, prior.Incident_Key__c, String.valueOf(prior.User__c));
            }
        }

        List<Incident__c> toUpsert = new List<Incident__c>();
        for (String key : byKey.keySet()) {
            List<Error_Log__c> grouped = byKey.get(key);
            Incident__c incident = existing.get(key);
            if (incident == null) {
                incident = new Incident__c(
                    Incident_Key__c = key,
                    First_Seen_At__c = nowValue,
                    Occurrence_Count__c = 0,
                    Status__c = 'Open',
                    Source_Type__c = grouped[0].Source_Type__c,
                    Source_Name__c = grouped[0].Source_Name__c,
                    Normalized_Category__c = grouped[0].Error_Category__c,
                    Summary__c = AEIR_SecuritySanitizerService.safeTruncate(grouped[0].Normalized_Message__c, 4000)
                );
            }

            for (Error_Log__c log : grouped) {
                addTo(knownRecords, key, log.Record_Id__c);
                addTo(knownUsers, key, String.valueOf(log.User__c));
                if (rank(log.Severity__c) > rank(incident.Highest_Severity__c)) {
                    incident.Highest_Severity__c = RANK_SEVERITY.get(rank(log.Severity__c));
                }
            }
            incident.Occurrence_Count__c = zero(incident.Occurrence_Count__c) + grouped.size();
            incident.Affected_Record_Count__c = countOf(knownRecords, key);
            incident.Affected_User_Count__c = countOf(knownUsers, key);
            incident.Last_Seen_At__c = nowValue;
            if (incident.First_Seen_At__c == null) incident.First_Seen_At__c = nowValue;
            toUpsert.add(incident);
        }

        try {
            Database.upsert(toUpsert, Incident__c.Fields.Incident_Key__c, true, AccessLevel.SYSTEM_MODE);
        } catch (Exception groupingFailure) {
            // Grouping is bookkeeping. Spec 1.2 requires the error record to persist even
            // when downstream services cannot run, so a user without Incident__c create
            // rights still gets their failure captured, just without an incident link.
            System.debug(LoggingLevel.WARN,
                'Aegis Flow: incident grouping skipped for this transaction: ' + groupingFailure.getMessage());
            return;
        }

        Map<String, Id> idByKey = new Map<String, Id>();
        for (Incident__c incident : toUpsert) idByKey.put(incident.Incident_Key__c, incident.Id);
        for (Error_Log__c log : logs) {
            if (log != null && idByKey.containsKey(log.Incident_Key__c)) {
                log.Incident__c = idByKey.get(log.Incident_Key__c);
            }
        }
    }

    /**
     * Stable across occurrences of the same failure, distinct across unrelated ones.
     * Record id is deliberately excluded so 500 rows failing the same rule group together.
     */
    @TestVisible
    private static String buildKey(Error_Log__c log, Datetime nowValue) {
        Long bucket = nowValue.getTime() / (BUCKET_MINUTES * 60 * 1000L);
        List<String> parts = new List<String>{
            blankTo(log.Source_Type__c, 'UnknownSource'),
            blankTo(log.Source_Name__c, 'UnknownName'),
            blankTo(log.Error_Category__c, 'Uncategorized'),
            blankTo(log.Object_API_Name__c, 'NoObject'),
            String.valueOf(bucket)
        };
        String key = String.join(parts, '|');
        return key.length() > 255 ? key.substring(0, 255) : key;
    }

    private static void addTo(Map<String, Set<String>> target, String key, String value) {
        if (String.isBlank(key) || String.isBlank(value) || value == 'null') return;
        if (!target.containsKey(key)) target.put(key, new Set<String>());
        target.get(key).add(value);
    }
    private static Integer countOf(Map<String, Set<String>> target, String key) {
        return target.containsKey(key) ? target.get(key).size() : 0;
    }
    private static Integer zero(Decimal value) { return value == null ? 0 : Integer.valueOf(value); }
    private static String blankTo(String value, String fallback) { return String.isBlank(value) ? fallback : value; }
    private static Integer rank(String severity) {
        if (String.isBlank(severity)) return 0;
        String key = severity.toUpperCase();
        return SEVERITY_RANK.containsKey(key) ? SEVERITY_RANK.get(key) : 0;
    }
}
