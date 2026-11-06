/**
 * Records platform event subscriber failures.
 *
 * Spec section 5.3 requires that "event publishing and subscriber failures must be
 * recorded in Delivery_Attempt__c or equivalent operational telemetry". The subscribers
 * previously used `catch (Exception ignored) {}`, which meant a broken subscriber was
 * completely invisible: no alert, no log, no signal in Automation Health.
 *
 * Failures are collected per invocation and written in a single DML, so a bulk event
 * batch cannot exhaust DML limits recording its own failures. Recording is best effort
 * by design; observability must never be the thing that breaks the transaction.
 */
public with sharing class AEIR_SubscriberTelemetry {

    private final String subscriber;
    private final List<Delivery_Attempt__c> failures = new List<Delivery_Attempt__c>();

    public AEIR_SubscriberTelemetry(String subscriberName) {
        this.subscriber = String.isBlank(subscriberName) ? 'Unknown subscriber' : subscriberName;
    }

    /** Records one failure. Call flush() once at the end of the handler. */
    public void record(String correlationId, Exception ex) {
        String reason = AEIR_SecuritySanitizerService.mask(
            ex == null ? 'Unspecified subscriber failure.' : ex.getTypeName() + ': ' + ex.getMessage());
        System.debug(LoggingLevel.WARN, AEIR_SecuritySanitizerService.mask(
            'Aegis Flow: ' + subscriber + ' failed for ' + correlationId + ': ' + reason));
        failures.add(new Delivery_Attempt__c(
            Correlation_Id__c = String.isBlank(correlationId) ? subscriber : correlationId,
            Channel__c = 'Platform Event',
            Status__c = 'Failed',
            Attempt_Count__c = 1,
            Idempotency_Key__c = subscriber + ':' + (String.isBlank(correlationId) ? String.valueOf(failures.size()) : correlationId),
            Response_Body__c = AEIR_SecuritySanitizerService.safeTruncate(
                AEIR_SecuritySanitizerService.mask(subscriber + ' :: ' + reason
                + (ex == null ? '' : '\n' + ex.getStackTraceString())), 32000)
        ));
    }

    public Boolean hasFailures() {
        return !failures.isEmpty();
    }

    /** Single DML for the whole batch. Never throws. */
    public void flush() {
        if (failures.isEmpty()) return;
        try {
            Database.insert(failures, false);
        } catch (Exception telemetryFailure) {
            System.debug(LoggingLevel.WARN,
                'Aegis Flow: could not record subscriber telemetry; inspect subscriber permissions and limits.');
        }
        failures.clear();
    }
}
