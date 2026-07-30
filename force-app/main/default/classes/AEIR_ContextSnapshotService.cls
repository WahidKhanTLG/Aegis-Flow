public with sharing class AEIR_ContextSnapshotService {
    @AuraEnabled(cacheable=true)
    public static String getSnapshot(String objectApiName, String recordId, Boolean forEscalation) {
        if (String.isBlank(objectApiName) || String.isBlank(recordId)) return '{}';
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        if (!gd.containsKey(objectApiName)) return '{}';
        Schema.DescribeSObjectResult d = gd.get(objectApiName).getDescribe();
        if (!d.isAccessible()) return '{}';
        Map<String, Schema.SObjectField> fmap = d.fields.getMap();
        List<String> selected = new List<String>();
        for (Context_Field_Setting__mdt cfg : [SELECT Field_API_Name__c, Include_In_Agent__c, Include_In_Escalation__c, Active__c FROM Context_Field_Setting__mdt WHERE Object__c = :objectApiName AND Active__c = true LIMIT 50]) {
            Boolean include = forEscalation == true ? cfg.Include_In_Escalation__c : cfg.Include_In_Agent__c;
            if (include && fmap.containsKey(cfg.Field_API_Name__c) && fmap.get(cfg.Field_API_Name__c).getDescribe().isAccessible()) selected.add(cfg.Field_API_Name__c);
        }
        if (selected.isEmpty()) selected.add('Id');
        if (!selected.contains('Id')) selected.add('Id');
        String soql = 'SELECT ' + String.join(selected, ',') + ' FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1';
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

            Map<String, Schema.SObjectField> fmap = d.fields.getMap();
            List<String> selected = new List<String>();
            for (Context_Field_Setting__mdt cfg : [
                SELECT Field_API_Name__c, Include_In_Agent__c, Include_In_Escalation__c, Active__c
                FROM Context_Field_Setting__mdt WHERE Object__c = :objectApiName AND Active__c = true LIMIT 50
            ]) {
                Boolean include = forEscalation == true ? cfg.Include_In_Escalation__c : cfg.Include_In_Agent__c;
                if (include && fmap.containsKey(cfg.Field_API_Name__c)
                    && fmap.get(cfg.Field_API_Name__c).getDescribe().isAccessible()) {
                    selected.add(cfg.Field_API_Name__c);
                }
            }
            if (!selected.contains('Id')) selected.add('Id');

            // One query per object, not per record.
            String soql = 'SELECT ' + String.join(selected, ',') + ' FROM ' + objectApiName
                        + ' WHERE Id IN :recordIds';
            try {
                for (SObject row : Database.query(soql)) {
                    Map<String, Object> values = new Map<String, Object>();
                    for (String f : selected) values.put(objectApiName + '.' + f, row.get(f));
                    out.put(String.valueOf(row.get('Id')),
                            AEIR_SecuritySanitizerService.mask(JSON.serialize(values)));
                }
            } catch (Exception ex) {
                // A snapshot must never break the caller; record the reason instead.
                for (String rid : recordIds) {
                    out.put(rid, JSON.serialize(new Map<String, Object>{ 'snapshotError' => ex.getMessage() }));
                }
            }
        }
        return out;
    }
}