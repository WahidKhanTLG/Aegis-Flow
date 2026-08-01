/** Executes one metadata-defined retention policy without an arbitrary record cap. */
public without sharing class AEIR_RetentionPurgeBatch implements Database.Batchable<SObject> {
    private final String objectName;
    private final Datetime cutoff;
    private final Boolean deleteAttachments;

    public AEIR_RetentionPurgeBatch(String objectName, Datetime cutoff, Boolean deleteAttachments) {
        this.objectName = objectName;
        this.cutoff = cutoff;
        this.deleteAttachments = deleteAttachments == true;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        if (objectName == AEIR_RetentionScheduler.ERROR_LOG) {
            return Database.getQueryLocator([
                SELECT Id FROM Error_Log__c WHERE CreatedDate < :cutoff
            ]);
        }
        if (objectName == AEIR_RetentionScheduler.DIAGNOSTIC_SESSION) {
            return Database.getQueryLocator([
                SELECT Id FROM Diagnostic_Session__c WHERE CreatedDate < :cutoff
            ]);
        }
        return Database.getQueryLocator([SELECT Id FROM User WHERE Id = null]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        Set<Id> ids = new Map<Id, SObject>(scope).keySet();
        if (objectName == AEIR_RetentionScheduler.ERROR_LOG) {
            AEIR_RetentionScheduler.purgeErrorLogs(ids, deleteAttachments);
        } else if (objectName == AEIR_RetentionScheduler.DIAGNOSTIC_SESSION) {
            AEIR_RetentionScheduler.purgeDiagnosticSessions(ids);
        }
    }

    public void finish(Database.BatchableContext context) {}
}
