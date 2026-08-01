/**
 * Starts one retention batch for each active, supported policy. The scheduled job only
 * queues work; Database.QueryLocator lets the batch clear a backlog larger than one page.
 */
public without sharing class AEIR_RetentionScheduler implements Schedulable {
    public static final String ERROR_LOG = 'Error_Log__c';
    public static final String DIAGNOSTIC_SESSION = 'Diagnostic_Session__c';

    public void execute(SchedulableContext context) {
        purge();
    }

    public static void purge() {
        for (Retention_Policy__mdt policy : Retention_Policy__mdt.getAll().values()) {
            if (policy.Active__c != true
                || policy.Retention_Days__c == null
                || policy.Retention_Days__c <= 0
                || !isSupported(policy.Object_Name__c)) {
                continue;
            }
            Datetime cutoff = Datetime.now().addDays(-Integer.valueOf(policy.Retention_Days__c));
            Database.executeBatch(
                new AEIR_RetentionPurgeBatch(policy.Object_Name__c, cutoff, policy.Delete_Attachments__c),
                200
            );
        }
    }

    public static void purgeErrorLogs(Set<Id> errorLogIds, Boolean deleteAttachments) {
        if (errorLogIds == null || errorLogIds.isEmpty()) return;

        deleteRows([
            SELECT Id FROM Error_Context__c WHERE Error_Log__c IN :errorLogIds
        ], 'error contexts');
        deleteRows([
            SELECT Id FROM AI_Diagnosis__c WHERE Error_Log__c IN :errorLogIds
        ], 'AI diagnoses');

        if (deleteAttachments == true) {
            // Aegis Flow records a File Id but does not own the ContentDocument. Deleting only
            // the manifest avoids removing a file that may also be linked outside Aegis Flow.
            deleteRows([
                SELECT Id FROM Error_Attachment__c WHERE Error_Log__c IN :errorLogIds
            ], 'error attachment manifests');
        }

        redactEscalations([
            SELECT Id, Summary__c, Diagnostic_Package_JSON__c
            FROM Developer_Escalation__c
            WHERE Error_Log__c IN :errorLogIds
        ]);
        redactFeedback([
            SELECT Id, Comments__c FROM Error_Feedback__c WHERE Error_Log__c IN :errorLogIds
        ]);
        redactRetryAttempts([
            SELECT Id, Payload_JSON__c, Result_Message__c
            FROM Retry_Attempt__c
            WHERE Error_Log__c IN :errorLogIds
        ]);
        redactRemediationActions([
            SELECT Id, Before_Value__c, After_Value__c, Result_Message__c
            FROM Remediation_Action__c
            WHERE Error_Log__c IN :errorLogIds
        ]);

        deleteRows([
            SELECT Id FROM Error_Log__c WHERE Id IN :errorLogIds
        ], 'error logs');
    }

    public static void purgeDiagnosticSessions(Set<Id> sessionIds) {
        if (sessionIds == null || sessionIds.isEmpty()) return;

        deleteRows([
            SELECT Id FROM AI_Diagnosis__c WHERE Diagnostic_Session__c IN :sessionIds
        ], 'AI diagnoses');
        redactEscalations([
            SELECT Id, Summary__c, Diagnostic_Package_JSON__c
            FROM Developer_Escalation__c
            WHERE Diagnostic_Session__c IN :sessionIds
        ]);
        redactFeedback([
            SELECT Id, Comments__c FROM Error_Feedback__c WHERE Diagnostic_Session__c IN :sessionIds
        ]);
        redactRemediationActions([
            SELECT Id, Before_Value__c, After_Value__c, Result_Message__c
            FROM Remediation_Action__c
            WHERE Diagnostic_Session__c IN :sessionIds
        ]);

        deleteRows([
            SELECT Id FROM Diagnostic_Session__c WHERE Id IN :sessionIds
        ], 'diagnostic sessions');
    }

    private static Boolean isSupported(String objectName) {
        return objectName == ERROR_LOG || objectName == DIAGNOSTIC_SESSION;
    }

    private static void redactEscalations(List<Developer_Escalation__c> rows) {
        for (Developer_Escalation__c row : rows) {
            row.Diagnostic_Package_JSON__c = null;
            row.Summary__c = 'Retained audit; technical evidence deleted by retention policy.';
        }
        updateRows(rows, 'developer escalation evidence');
    }

    private static void redactFeedback(List<Error_Feedback__c> rows) {
        for (Error_Feedback__c row : rows) row.Comments__c = null;
        updateRows(rows, 'feedback comments');
    }

    private static void redactRetryAttempts(List<Retry_Attempt__c> rows) {
        for (Retry_Attempt__c row : rows) {
            row.Payload_JSON__c = null;
            row.Result_Message__c = 'Technical evidence deleted by retention policy.';
        }
        updateRows(rows, 'retry evidence');
    }

    private static void redactRemediationActions(List<Remediation_Action__c> rows) {
        for (Remediation_Action__c row : rows) {
            row.Before_Value__c = null;
            row.After_Value__c = null;
            row.Result_Message__c = 'Technical evidence deleted by retention policy.';
        }
        updateRows(rows, 'remediation evidence');
    }

    private static void deleteRows(List<SObject> rows, String description) {
        if (rows.isEmpty()) return;
        List<Database.DeleteResult> results = Database.delete(rows, false, AccessLevel.SYSTEM_MODE);
        assertDeletesSuccessful(results, description);
    }

    private static void updateRows(List<SObject> rows, String description) {
        if (rows.isEmpty()) return;
        List<Database.SaveResult> results = Database.update(rows, false, AccessLevel.SYSTEM_MODE);
        assertSuccessful(results, description);
    }

    private static void assertSuccessful(List<Database.SaveResult> results, String description) {
        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
                Database.Error error = result.getErrors()[0];
                throw new RetentionException('Could not purge ' + description + ': ' + error.getMessage());
            }
        }
    }

    private static void assertDeletesSuccessful(List<Database.DeleteResult> results, String description) {
        for (Database.DeleteResult result : results) {
            if (!result.isSuccess()) {
                Database.Error error = result.getErrors()[0];
                throw new RetentionException('Could not purge ' + description + ': ' + error.getMessage());
            }
        }
    }

    private class RetentionException extends Exception {}
}
