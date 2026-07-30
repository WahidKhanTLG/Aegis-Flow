public with sharing class AEIR_LogCollectorService {
    public class LogCollectionResult {
        @AuraEnabled public Boolean available;
        @AuraEnabled public String message;
        @AuraEnabled public String debugLogId;
        @AuraEnabled public String debugLogLink;
    }
    @AuraEnabled
    public static LogCollectionResult collectForError(Id errorLogId) {
        Error_Log__c log = [SELECT Id, Debug_Log_Id__c FROM Error_Log__c WHERE Id = :errorLogId LIMIT 1];
        LogCollectionResult res = new LogCollectionResult();
        res.available = !String.isBlank(log.Debug_Log_Id__c);
        res.debugLogId = log.Debug_Log_Id__c;
        if (res.available) {
            res.debugLogLink = URL.getOrgDomainUrl().toExternalForm() + '/' + log.Debug_Log_Id__c;
            log.Debug_Log_Link__c = res.debugLogLink;
            update log;
            res.message = 'A debug log id was already linked to this error. Full Tooling API retrieval should be implemented using a customer-approved Named Credential.';
        } else {
            res.message = 'No debug log id is available. Continue with stack trace, context, record snapshot, and user description.';
        }
        return res;
    }
}