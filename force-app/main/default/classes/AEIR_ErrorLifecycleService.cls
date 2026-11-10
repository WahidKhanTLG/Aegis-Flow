/** Server-owned transition times; unrelated edits cannot rewrite diagnostic durations. */
public with sharing class AEIR_ErrorLifecycleService {
    @TestVisible private static Datetime clockOverride;
    public static void stamp(List<Error_Log__c> rows, Map<Id, Error_Log__c> previous) {
        Datetime nowValue = clockOverride == null ? Datetime.now() : clockOverride;
        for (Error_Log__c row : rows) {
            Error_Log__c old = previous == null ? null : previous.get(row.Id);
            row.First_Diagnosed_At__c = old == null ? null : old.First_Diagnosed_At__c;
            row.Resolved_At__c = old == null ? null : old.Resolved_At__c;
            if (row.Status__c == 'Diagnosed' && (old == null || old.Status__c != 'Diagnosed')
                && row.First_Diagnosed_At__c == null) row.First_Diagnosed_At__c = nowValue;
            if (row.Status__c == 'Resolved') {
                if (old == null || old.Status__c != 'Resolved') row.Resolved_At__c = nowValue;
            } else row.Resolved_At__c = null;
        }
    }
}
