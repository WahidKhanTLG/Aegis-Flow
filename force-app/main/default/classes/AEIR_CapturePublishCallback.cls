/** Final publication failures are recorded independently of a publisher's rollback. */
public without sharing class AEIR_CapturePublishCallback implements EventBus.EventPublishFailureCallback {
    private Map<String, String> correlationsByUuid;
    public AEIR_CapturePublishCallback(Map<String, String> correlations) {
        // Only identifiers cross the asynchronous boundary; never retain diagnostic bodies.
        correlationsByUuid = new Map<String, String>(correlations);
    }
    public void onFailure(EventBus.FailureResult result) {
        AEIR_SubscriberTelemetry telemetry = new AEIR_SubscriberTelemetry('CapturePublication');
        for (String uuid : result.getEventUuids()) {
            telemetry.record(correlationsByUuid.get(uuid), new PublicationException(
                'The event was accepted for queuing but failed final publication. Reconcile the source failure before retrying capture.'));
        }
        telemetry.flush();
    }
    private class PublicationException extends Exception {}
}
