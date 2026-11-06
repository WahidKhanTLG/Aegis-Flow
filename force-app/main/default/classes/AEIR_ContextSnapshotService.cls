public with sharing class AEIR_ContextSnapshotService {
    private static final Integer CALLER_QUERY_RESERVE = 10;
    @TestVisible private static Map<String, List<Context_Field_Setting__mdt>> configurationOverrides;

    private static Boolean hasQueryCapacity() {
        return Limits.getLimitQueries() - Limits.getQueries() > CALLER_QUERY_RESERVE;
    }
    private static String queryCapacityError() {
        // Fixed diagnostic text contains no record data and needs no additional reads.
        return JSON.serialize(new Map<String, Object>{
            'snapshotError' => 'Snapshot omitted because remaining query capacity is reserved for the caller.'
        });
    }

    private static List<Context_Field_Setting__mdt> fieldSettings(String objectApiName) {
        if (configurationOverrides != null) {
            return configurationOverrides.containsKey(objectApiName)
                ? configurationOverrides.get(objectApiName) : new List<Context_Field_Setting__mdt>();
        }
        return [SELECT Field_API_Name__c, Include_In_Agent__c, Include_In_Escalation__c, Active__c
            FROM Context_Field_Setting__mdt WHERE Object__c = :objectApiName AND Active__c = true LIMIT 50];
    }
    @AuraEnabled(cacheable=true)
    public static String getSnapshot(String objectApiName, String recordId, Boolean forEscalation) {
        if (String.isBlank(objectApiName) || String.isBlank(recordId)) return '{}';
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        if (!gd.containsKey(objectApiName)) return '{}';
        Schema.DescribeSObjectResult d = gd.get(objectApiName).getDescribe();
        if (!d.isAccessible()) return '{}';
        if (!hasQueryCapacity()) return queryCapacityError();
        Map<String, Schema.SObjectField> fmap = d.fields.getMap();
        List<String> selected = new List<String>();
        for (Context_Field_Setting__mdt cfg : fieldSettings(objectApiName)) {
            if (cfg.Active__c != true) continue;
            Boolean include = forEscalation == true ? cfg.Include_In_Escalation__c : cfg.Include_In_Agent__c;
            if (include && fmap.containsKey(cfg.Field_API_Name__c) && fmap.get(cfg.Field_API_Name__c).getDescribe().isAccessible()) selected.add(cfg.Field_API_Name__c);
        }
        if (selected.isEmpty()) selected.add('Id');
        if (!selected.contains('Id')) selected.add('Id');
        String soql = 'SELECT ' + String.join(selected, ',') + ' FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1';
        if (!hasQueryCapacity()) return queryCapacityError();
        try {
            SObject row = Database.query(soql);
            Map<String, Object> out = new Map<String, Object>();
            for (String f : selected) out.put(objectApiName + '.' + f, row.get(f));
            return AEIR_SecuritySanitizerService.mask(JSON.serialize(out));
        } catch (Exception ex) {
            return JSON.serialize(new Map<String, Object>{'snapshotError' => ex.getMessage()});
        }
    }

    /**
     * Bulk snapshots, grouped by object so cost scales with the number of distinct
     * objects rather than the number of records. The single-record getSnapshot() issues
     * one query per call, which made any bulk caller (escalation, notification) exceed
     * the SOQL limit long before its own batch size.
     *
     * @return snapshot JSON keyed by record id
     */
    public static Map<String, String> getSnapshots(Map<String, Set<String>> recordIdsByObject, Boolean forEscalation) {
        Map<String, String> out = new Map<String, String>();
        if (recordIdsByObject == null || recordIdsByObject.isEmpty()) return out;
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

        for (String objectApiName : recordIdsByObject.keySet()) {
            Set<String> recordIds = recordIdsByObject.get(objectApiName);
            if (String.isBlank(objectApiName) || recordIds == null || recordIds.isEmpty()) continue;
            if (!gd.containsKey(objectApiName)) continue;
            Schema.DescribeSObjectResult d = gd.get(objectApiName).getDescribe();
            if (!d.isAccessible()) continue;
            Set<Id> validRecordIds = new Set<Id>();
            String invalidRecord = JSON.serialize(new Map<String, Object>{
                'snapshotError' => 'The snapshot record id is invalid or belongs to another object.'
            });
            for (String requestedId : recordIds) {
                try {
                    Id typedId = (Id) requestedId;
                    if (typedId == null || typedId.getSObjectType() != gd.get(objectApiName)) {
                        out.put(requestedId == null ? 'null' : requestedId, invalidRecord);
                    } else validRecordIds.add(typedId);
                } catch (Exception invalidId) {
                    out.put(requestedId, invalidRecord);
                }
            }
            if (validRecordIds.isEmpty()) continue;
            // Large mixed-object batches must leave capacity for diagnosis, status
            // updates, and the caller's remaining work instead of hitting query 101.
            if (!hasQueryCapacity()) {
                String omitted = queryCapacityError();
                for (Id recordId : validRecordIds) out.put(String.valueOf(recordId), omitted);
                continue;
            }

            Map<String, Schema.SObjectField> fmap = d.fields.getMap();
            List<String> selected = new List<String>();
            for (Context_Field_Setting__mdt cfg : fieldSettings(objectApiName)) {
                if (cfg.Active__c != true) continue;
                Boolean include = forEscalation == true ? cfg.Include_In_Escalation__c : cfg.Include_In_Agent__c;
                if (include && fmap.containsKey(cfg.Field_API_Name__c)
                    && fmap.get(cfg.Field_API_Name__c).getDescribe().isAccessible()) {
                    selected.add(cfg.Field_API_Name__c);
                }
            }
            if (!selected.contains('Id')) selected.add('Id');

            // One query per object, not per record.
            String soql = 'SELECT ' + String.join(selected, ',') + ' FROM ' + objectApiName
                        + ' WHERE Id IN :validRecordIds';
            if (!hasQueryCapacity()) {
                String omitted = queryCapacityError();
                for (Id recordId : validRecordIds) out.put(String.valueOf(recordId), omitted);
                continue;
            }
            try {
                for (SObject row : Database.query(soql)) {
                    Map<String, Object> values = new Map<String, Object>();
                    for (String f : selected) values.put(objectApiName + '.' + f, row.get(f));
                    out.put(String.valueOf(row.get('Id')),
                            AEIR_SecuritySanitizerService.mask(JSON.serialize(values)));
                }
            } catch (Exception ex) {
                // A snapshot must never break the caller; record the reason instead.
                for (Id rid : validRecordIds) {
                    out.put(String.valueOf(rid), JSON.serialize(new Map<String, Object>{ 'snapshotError' => ex.getMessage() }));
                }
            }
        }
        return out;
    }
}
