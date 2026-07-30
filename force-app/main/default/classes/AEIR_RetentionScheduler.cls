public with sharing class AEIR_RetentionScheduler implements Schedulable {
    public void execute(SchedulableContext sc) { purge(); }
    public static void purge() {
        Integer daysToKeep = 365;
        List<Retention_Policy__mdt> policies = [SELECT Retention_Days__c FROM Retention_Policy__mdt WHERE Object_Name__c = 'Error_Log__c' AND Active__c = true LIMIT 1];
        if (!policies.isEmpty() && policies[0].Retention_Days__c != null) daysToKeep = Integer.valueOf(policies[0].Retention_Days__c);
        Datetime cutoff = Datetime.now().addDays(-daysToKeep);
        List<Error_Log__c> oldLogs = [SELECT Id FROM Error_Log__c WHERE CreatedDate < :cutoff LIMIT 200];
        if (!oldLogs.isEmpty()) Database.delete(oldLogs, false);
    }
}