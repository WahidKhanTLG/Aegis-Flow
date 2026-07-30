/**
 * One-line Apex instrumentation for customer code.
 *
 * The full ErrorInput contract is fine for the package's own adapters but far too much
 * ceremony for a developer adding a catch block. Instrumentation that is tedious does not
 * get adopted, and un-adopted instrumentation is the single largest coverage gap in the
 * product, so this exists to make the right thing the easy thing.
 *
 * Typical use, preserving the original exception for the caller:
 *
 *     try {
 *         update orders;
 *     } catch (Exception e) {
 *         AEIR_Guard.capture(e, 'OrderService.recalculateTax', orderId);
 *         throw e;
 *     }
 *
 * Fire and forget, when the caller handles the failure itself:
 *
 *     AEIR_Guard.capture(e, 'OrderService.recalculateTax');
 *
 * capture() never throws. Instrumentation must not be able to break the business
 * transaction it is observing.
 *
 * IMPORTANT: capture() publishes a platform event rather than writing directly, so the
 * evidence survives even when the transaction rolls back. That matters because the most
 * common instrumentation shape is "capture then rethrow", and a rethrow rolls back the
 * transaction. A direct insert would be rolled back with it and the failure lost.
 * Use captureNow() only when you need the Error_Log__c id inside the same transaction
 * and you know that transaction will commit.
 */
global with sharing class AEIR_Guard {

    /** Minimal form: exception plus where it happened. */
    global static String capture(Exception ex, String sourceName) {
        return capture(ex, sourceName, null, null, null);
    }

    /** With the affected record, so the escalation can carry a record snapshot. */
    global static String capture(Exception ex, String sourceName, Id recordId) {
        return capture(ex, sourceName, recordId, recordId == null ? null : String.valueOf(recordId.getSObjectType()), null);
    }

    /** With the user action, which is what makes the summary readable to a human. */
    global static String capture(Exception ex, String sourceName, Id recordId, String userAction) {
        return capture(ex, sourceName, recordId, recordId == null ? null : String.valueOf(recordId.getSObjectType()), userAction);
    }

    /**
     * Rollback safe. Publishes Error_Captured__e, which is PublishImmediately, so the
     * evidence survives whether the transaction commits or rolls back.
     *
     * @return the correlation id, so the caller can show the user a reference number,
     *         or null when capture was not possible.
     */
    global static String capture(Exception ex, String sourceName, Id recordId, String objectApiName, String userAction) {
        try {
            return AEIR_ErrorCaptureService.publish(buildInput(ex, sourceName, recordId, objectApiName, userAction)).correlationId;
        } catch (Exception instrumentationFailure) {
            // Never let observability break the transaction it is observing.
            System.debug(LoggingLevel.WARN,
                'Aegis Flow: capture failed for ' + sourceName + ': ' + instrumentationFailure.getMessage());
            return null;
        }
    }

    /**
     * Writes Error_Log__c directly in the current transaction and returns its id. Only
     * use this when the caller needs that id immediately and the transaction is known to
     * commit. If the caller rethrows, prefer capture().
     */
    global static Id captureNow(Exception ex, String sourceName, Id recordId, String userAction) {
        try {
            String objectApiName = recordId == null ? null : String.valueOf(recordId.getSObjectType());
            return AEIR_ErrorCaptureService.capture(buildInput(ex, sourceName, recordId, objectApiName, userAction)).errorLogId;
        } catch (Exception instrumentationFailure) {
            System.debug(LoggingLevel.WARN,
                'Aegis Flow: captureNow failed for ' + sourceName + ': ' + instrumentationFailure.getMessage());
            return null;
        }
    }

    private static AEIR_ErrorCaptureService.ErrorInput buildInput(
        Exception ex, String sourceName, Id recordId, String objectApiName, String userAction) {
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.sourceType = 'Apex Class';
        input.sourceName = String.isBlank(sourceName) ? 'Unnamed Apex' : sourceName;
        input.objectApiName = objectApiName;
        input.recordId = recordId == null ? null : String.valueOf(recordId);
        input.actionName = userAction;
        input.originalMessage = ex == null ? 'Unspecified Apex failure.' : ex.getTypeName() + ': ' + ex.getMessage();
        input.stackTrace = ex == null ? null : ex.getStackTraceString();
        return input;
    }

    /** Retained alias. capture() is now rollback safe by default, so this is equivalent. */
    global static String captureResilient(Exception ex, String sourceName, Id recordId) {
        return capture(ex, sourceName, recordId);
    }
}