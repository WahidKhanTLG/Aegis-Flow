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

    /** Injectable evidence source because FlowInterview cannot be inserted by tests. */
    public virtual class EvidenceSource {
        public virtual List<FlowInterview> page(Datetime cursorAt, Id cursorId, Integer pageSize) {
            String query = 'SELECT Id, Guid, InterviewLabel, CurrentElement, Error, CreatedById, CreatedDate FROM FlowInterview '
                + 'WHERE InterviewStatus = \'Error\' AND CreatedDate = LAST_N_DAYS:1';
            if (cursorAt != null) query += ' AND (CreatedDate > :cursorAt OR (CreatedDate = :cursorAt AND Id > :cursorId))';
            return Database.queryWithBinds(query + ' ORDER BY CreatedDate ASC, Id ASC LIMIT :pageSize',
                new Map<String, Object>{'cursorAt' => cursorAt, 'cursorId' => cursorId, 'pageSize' => pageSize}, AccessLevel.USER_MODE);
        }
    }
    @TestVisible private static EvidenceSource evidenceSource = new EvidenceSource();

    /** Processes one page per call; later calls continue beyond already captured rows. */
    public static Integer reconcile() {
        AEIR_MonitorCursorService.State cursor = AEIR_MonitorCursorService.read(true);
        List<FlowInterview> errored;
        try { errored = evidenceSource.page(cursor.at, cursor.lastId, BATCH_LIMIT); }
        catch (Exception unavailable) {
            AEIR_SubscriberTelemetry telemetry = new AEIR_SubscriberTelemetry('FlowInterviewMonitor');
            telemetry.record(null, new MonitorException('Failed Flow interviews could not be read. Review monitor access.'));
            telemetry.flush();
            return 0;
        }
        Integer captured = reconcile(errored);
        FlowInterview last = errored.isEmpty() ? null : errored[errored.size() - 1];
        // Reset only after the entire sweep, so late status changes are rescanned.
        AEIR_MonitorCursorService.save(cursor, true,
            errored.size() < BATCH_LIMIT ? null : last.CreatedDate,
            errored.size() < BATCH_LIMIT ? null : last.Id);
        return captured;
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

        Integer captured = 0;
        for (AEIR_ErrorCaptureService.CaptureResult result :
            AEIR_ErrorCapturedEventHandler.captureInputs(inputs, 'FlowInterviewMonitor')) {
            if (result != null && result.retryable == true) {
                throw new MonitorException('Temporary Flow capture failure; the monitoring cursor was not advanced.');
            }
            if (result != null && result.success == true) captured++;
        }
        return captured;
    }
    private class MonitorException extends Exception {}

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