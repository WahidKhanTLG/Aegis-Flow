public with sharing class AEIR_AdminConsoleController {
    public class Metrics {
        @AuraEnabled public Integer newErrorsToday;
        @AuraEnabled public Integer criticalOpen;
        @AuraEnabled public Integer escalationsPending;
        @AuraEnabled public Integer resolvedErrors;
        @AuraEnabled public Integer affectedUsers;
        @AuraEnabled public Integer recurringIncidents;
        @AuraEnabled public Integer unresolvedCriticalIncidents;
        @AuraEnabled public Decimal meanMinutesToDiagnosis;
        @AuraEnabled public Decimal meanMinutesToResolution;
        @AuraEnabled public Integer assistedResolutions;
        @AuraEnabled public Integer automaticallyResolved;
        @AuraEnabled public Decimal retrySuccessRate;
        @AuraEnabled public List<SourceCount> topFailingSources;
    }
    /** An incident seen this many times or more counts as recurring (spec 13.2). */
    private static final Integer RECURRENCE_THRESHOLD = 3;

    public class SourceCount {
        @AuraEnabled public String sourceName;
        @AuraEnabled public String sourceType;
        @AuraEnabled public Integer occurrences;
    }

    @AuraEnabled(cacheable=true)
    public static List<Error_Log__c> getRecentErrors(String status, String severity, Integer limitSize) {
        Integer l = limitSize == null || limitSize <= 0 || limitSize > 200 ? 50 : limitSize;
        String q = 'SELECT Id, Name, Correlation_Id__c, Error_Category__c, Severity__c, Source_Type__c, Source_Name__c, Object_API_Name__c, Record_Id__c, Status__c, Agentforce_Status__c, CreatedDate FROM Error_Log__c';
        List<String> whereParts = new List<String>();
        if (!String.isBlank(status)) whereParts.add('Status__c = :status');
        if (!String.isBlank(severity)) whereParts.add('Severity__c = :severity');
        if (!whereParts.isEmpty()) q += ' WHERE ' + String.join(whereParts, ' AND ');
        q += ' ORDER BY CreatedDate DESC LIMIT :l';
        return Database.query(q);
    }
    @AuraEnabled(cacheable=true)
    public static List<Developer_Escalation__c> getRecentEscalations(Integer limitSize) {
        Integer l = limitSize == null || limitSize <= 0 || limitSize > 200 ? 50 : limitSize;
        return [SELECT Id, Name, Correlation_Id__c, Channel__c, Recipient__c, Severity__c, Subject__c, Status__c, CreatedDate FROM Developer_Escalation__c ORDER BY CreatedDate DESC LIMIT :l];
    }
    @AuraEnabled(cacheable=true)
    public static Metrics getMetrics() {
        Metrics m = new Metrics();
        m.newErrorsToday = [SELECT count() FROM Error_Log__c WHERE CreatedDate = TODAY];
        m.criticalOpen = [SELECT count() FROM Error_Log__c WHERE Severity__c = 'Critical' AND Status__c != 'Closed'];
        m.escalationsPending = [SELECT count() FROM Developer_Escalation__c WHERE Status__c IN ('New','Failed')];
        m.resolvedErrors = [SELECT count() FROM Error_Log__c WHERE Status__c = 'Resolved'];

        // Distinct users materially affected today.
        Set<Id> affected = new Set<Id>();
        for (AggregateResult ar : [SELECT User__c uid FROM Error_Log__c
                                   WHERE CreatedDate = TODAY AND User__c != null GROUP BY User__c LIMIT 2000]) {
            affected.add((Id) ar.get('uid'));
        }
        m.affectedUsers = affected.size();

        // Incident-derived metrics (available now that AEIR_IncidentAggregationService populates Incident__c).
        m.recurringIncidents = [SELECT count() FROM Incident__c
                                WHERE Occurrence_Count__c >= :RECURRENCE_THRESHOLD AND Status__c != 'Resolved'];
        m.unresolvedCriticalIncidents = [SELECT count() FROM Incident__c
                                         WHERE Highest_Severity__c = 'Critical' AND Status__c NOT IN ('Resolved','Suppressed')];

        m.meanMinutesToDiagnosis = meanMinutesBetween('Diagnosed');
        m.meanMinutesToResolution = meanMinutesBetween('Resolved');

        // Assisted = a user confirmed a remediation. Automatic = system-safe, no confirmation.
        m.assistedResolutions = [SELECT count() FROM Remediation_Action__c
                                 WHERE Status__c = 'Executed' AND Requires_Confirmation__c = true];
        m.automaticallyResolved = [SELECT count() FROM Remediation_Action__c
                                   WHERE Status__c = 'Executed' AND Requires_Confirmation__c = false];

        Integer retriesRun = [SELECT count() FROM Retry_Attempt__c WHERE Status__c IN ('Succeeded','Failed')];
        Integer retriesOk = [SELECT count() FROM Retry_Attempt__c WHERE Status__c = 'Succeeded'];
        m.retrySuccessRate = retriesRun == 0 ? 0 : ((Decimal) retriesOk / retriesRun * 100).setScale(1);

        m.topFailingSources = topFailingSources();
        return m;
    }

    /**
     * Mean minutes from capture to the given lifecycle status. Uses LastModifiedDate as
     * the transition proxy, which is accurate while the status is only set once.
     */
    private static Decimal meanMinutesBetween(String targetStatus) {
        List<Error_Log__c> rows = [
            SELECT CreatedDate, LastModifiedDate
            FROM Error_Log__c
            WHERE Status__c = :targetStatus AND CreatedDate = LAST_N_DAYS:30
            LIMIT 2000
        ];
        if (rows.isEmpty()) return 0;
        Decimal total = 0;
        for (Error_Log__c row : rows) {
            total += (row.LastModifiedDate.getTime() - row.CreatedDate.getTime()) / 60000.0;
        }
        return (total / rows.size()).setScale(1);
    }

    /** Ranked failing sources, so triage knows where to look first (spec 13.2). */
    private static List<SourceCount> topFailingSources() {
        List<SourceCount> output = new List<SourceCount>();
        for (AggregateResult ar : [
            SELECT Source_Name__c name, Source_Type__c stype, COUNT(Id) total
            FROM Error_Log__c
            WHERE CreatedDate = LAST_N_DAYS:7 AND Source_Name__c != null
            GROUP BY Source_Name__c, Source_Type__c
            ORDER BY COUNT(Id) DESC
            LIMIT 5
        ]) {
            SourceCount sc = new SourceCount();
            sc.sourceName = (String) ar.get('name');
            sc.sourceType = (String) ar.get('stype');
            sc.occurrences = (Integer) ar.get('total');
            output.add(sc);
        }
        return output;
    }
}