/**
 * Zero-instrumentation Flow failure capture.
 *
 * Salesforce persists every errored Flow interview in FlowInterview with the failing
 * element and the full error message. That means the product can capture Flow failures
 * without the customer wiring a fault path into anything, which removes the single
 * largest adoption barrier in the capture story.
 *
 * What FlowInterview gives us for free:
 *   InterviewLabel   - which Flow
 *   CurrentElement   - which element failed
 *   Error            - the full error message
 *   CreatedById      - the affected user
 *   Guid             - a stable id, used here for idempotency
 *
 * What it does NOT give us, and why fault paths still matter for some Flows:
 *   - the affected record id, so no record snapshot in the escalation package
 *   - real-time delivery; this is a poll, so the user is notified on the scheduler
 *     cadence rather than at the moment of failure
 *
 * Recommended use: run this everywhere for coverage, and add fault paths only to the
 * Flows where the user needs an immediate, record-level diagnosis.
 */
public with sharing class AEIR_FlowInterviewMonitor implements Schedulable {

    /** Correlation prefix. Correlation_Id__c is a unique external id, so this dedupes. */
    private static final String PREFIX = 'FLOWINT-';

    @TestVisible
    private static final Integer BATCH_LIMIT = 200;

    public void execute(SchedulableContext context) {
        reconcile();
    }

    /**
     * Turns errored Flow interviews into Aegis error logs.
     * @return how many new failures were captured
     */
    public static Integer reconcile() {
        List<FlowInterview> errored;
        try {
            errored = [
                SELECT Id, Guid, InterviewLabel, CurrentElement, Error, CreatedById, CreatedDate
                FROM FlowInterview
                WHERE InterviewStatus = 'Error' AND CreatedDate = LAST_N_DAYS:1
                ORDER BY CreatedDate DESC
                LIMIT :BATCH_LIMIT
            ];
        } catch (Exception noAccess) {
            // FlowInterview requires "Manage Flow" style access. Degrade rather than fail
            // the scheduled job, and leave a trace for the admin.
            System.debug(LoggingLevel.WARN,
                'Aegis Flow: cannot read FlowInterview, skipping Flow reconciliation: ' + noAccess.getMessage());
            return 0;
        }
        return reconcile(errored);
    }

    /**
     * Reconciliation split from the query so the behaviour is testable. FlowInterview
     * cannot be inserted, so tests build interviews via JSON deserialization and call
     * this directly.
     */
    @TestVisible
    private static Integer reconcile(List<FlowInterview> errored) {
        if (errored == null || errored.isEmpty()) return 0;

        Set<String> correlationIds = new Set<String>();
        for (FlowInterview interview : errored) correlationIds.add(PREFIX + interview.Guid);

        Set<String> alreadyCaptured = new Set<String>();
        for (Error_Log__c existing : [
            SELECT Correlation_Id__c FROM Error_Log__c WHERE Correlation_Id__c IN :correlationIds
        ]) {
            alreadyCaptured.add(existing.Correlation_Id__c);
        }

        // Build every input first, then capture once. capture() performs several queries,
        // an incident upsert, an insert and an event publish, so calling it per interview
        // exceeded the SOQL limit well before BATCH_LIMIT. This is the same defect that
        // was fixed in AEIR_AsyncJobMonitorScheduler; both poll loops had it.
        List<AEIR_ErrorCaptureService.ErrorInput> inputs = new List<AEIR_ErrorCaptureService.ErrorInput>();
        for (FlowInterview interview : errored) {
            String correlationId = PREFIX + interview.Guid;
            if (alreadyCaptured.contains(correlationId)) continue;
            alreadyCaptured.add(correlationId); // guard against duplicates within one batch

            AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
            input.correlationId = correlationId;
            input.sourceType = 'Flow';
            input.sourceName = sourceName(interview);
            input.originalMessage = interview.Error;
            input.actionName = 'Flow element: ' + blankTo(interview.CurrentElement, 'Unknown');
            input.userId = String.valueOf(interview.CreatedById);
            input.contextJson = JSON.serialize(new Map<String, Object>{
                'flowInterviewId' => interview.Id,
                'flowInterviewGuid' => interview.Guid,
                'interviewLabel' => interview.InterviewLabel,
                'failedElement' => interview.CurrentElement,
                'failedAt' => String.valueOf(interview.CreatedDate),
                'capturedBy' => 'FlowInterview reconciliation (no fault path required)'
            });
            inputs.add(input);
        }
        if (inputs.isEmpty()) return 0;

        try {
            Integer captured = 0;
            for (AEIR_ErrorCaptureService.CaptureResult result : AEIR_ErrorCaptureService.captureFromEvents(inputs)) {
                if (result != null && result.success == true) captured++;
            }
            return captured;
        } catch (Exception captureFailure) {
            System.debug(LoggingLevel.WARN,
                'Aegis Flow: Flow interview reconciliation failed: ' + captureFailure.getMessage());
            return 0;
        }
    }

    /**
     * InterviewLabel is "<Flow Label> <timestamp>", so the timestamp is stripped to keep
     * incident grouping stable across occurrences of the same Flow.
     */
    @TestVisible
    private static String sourceName(FlowInterview interview) {
        String label = blankTo(interview.InterviewLabel, 'Unknown Flow');
        Pattern trailingTimestamp = Pattern.compile('\\s+\\d{1,2}/\\d{1,2}/\\d{4}.*$');
        String flowName = trailingTimestamp.matcher(label).replaceAll('').trim();
        if (String.isBlank(flowName)) flowName = 'Unknown Flow';
        return String.isBlank(interview.CurrentElement)
            ? flowName
            : flowName + ' / ' + interview.CurrentElement;
    }

    private static String blankTo(String value, String fallback) {
        return String.isBlank(value) ? fallback : value;
    }
}