/**
 * Reconciles failed asynchronous Apex jobs into Aegis error logs.
 *
 * Bulk safety matters here more than anywhere else in the product: this runs on a
 * schedule against up to 100 failed jobs at once. The previous implementation called
 * AEIR_ErrorCaptureService.capture() inside the loop, and capture() itself performs
 * several queries, an incident upsert, an insert, a notification insert and an event
 * publish. At roughly fifteen failed jobs that exceeded the SOQL limit, so the scheduled
 * job would die exactly when the org was least healthy.
 *
 * It now builds every input first and hands the whole set to the bulk entry point, so the
 * cost is fixed regardless of how many jobs failed.
 */
public with sharing class AEIR_AsyncJobMonitorScheduler implements Schedulable {

    /** Correlation prefix. Correlation_Id__c is a unique external id, so this dedupes. */
    private static final String PREFIX = 'ASYNC-';

    public void execute(SchedulableContext context) {
        monitorFailedJobs();
    }

    /** @return how many newly failed jobs were captured */
    public static Integer monitorFailedJobs() {
        return reconcile([
            SELECT Id, Status, JobType, ApexClassId, ExtendedStatus, NumberOfErrors, CreatedDate, CompletedDate
            FROM AsyncApexJob
            WHERE Status = 'Failed' AND CreatedDate = LAST_N_DAYS:1
            ORDER BY CreatedDate DESC
            LIMIT 100
        ]);
    }

    /**
     * Reconciliation split from the query so the bulk behaviour is testable. AsyncApexJob
     * cannot be inserted, so tests build jobs via JSON deserialization and call this
     * directly. That matters: this method was rewritten to fix a governor-limit defect,
     * and an untested fix to a limits bug is not a fix.
     */
    @TestVisible
    private static Integer reconcile(List<AsyncApexJob> jobs) {
        if (jobs == null || jobs.isEmpty()) return 0;

        Map<String, AsyncApexJob> byCorrelation = new Map<String, AsyncApexJob>();
        Set<String> jobIds = new Set<String>();
        for (AsyncApexJob job : jobs) {
            byCorrelation.put(PREFIX + job.Id, job);
            jobIds.add(String.valueOf(job.Id));
        }

        // Two dedupe signals: the correlation id used by this class, and the legacy
        // Async_Job_Id__c stamp, so logs captured by an earlier version are not repeated.
        Set<String> alreadyCaptured = new Set<String>();
        for (Error_Log__c row : [
            SELECT Correlation_Id__c, Async_Job_Id__c
            FROM Error_Log__c
            WHERE Correlation_Id__c IN :byCorrelation.keySet() OR Async_Job_Id__c IN :jobIds
        ]) {
            if (String.isNotBlank(row.Correlation_Id__c)) alreadyCaptured.add(row.Correlation_Id__c);
            if (String.isNotBlank(row.Async_Job_Id__c)) alreadyCaptured.add(PREFIX + row.Async_Job_Id__c);
        }

        List<AEIR_ErrorCaptureService.ErrorInput> inputs = new List<AEIR_ErrorCaptureService.ErrorInput>();
        List<String> orderedCorrelations = new List<String>();
        for (String correlationId : byCorrelation.keySet()) {
            if (alreadyCaptured.contains(correlationId)) continue;
            AsyncApexJob job = byCorrelation.get(correlationId);
            AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
            input.correlationId = correlationId;
            input.sourceType = job.JobType == 'BatchApex' ? 'Batch' : 'Queueable';
            input.sourceName = String.isBlank(job.JobType) ? 'Asynchronous Apex' : job.JobType;
            input.originalMessage = String.isBlank(job.ExtendedStatus)
                ? 'Asynchronous Apex job failed.'
                : job.ExtendedStatus;
            input.actionName = 'Async job ' + job.Id;
            input.severity = 'High';
            input.contextJson = JSON.serialize(new Map<String, Object>{
                'asyncApexJobId' => String.valueOf(job.Id),
                'jobType' => job.JobType,
                'numberOfErrors' => job.NumberOfErrors,
                'createdDate' => String.valueOf(job.CreatedDate),
                'completedDate' => String.valueOf(job.CompletedDate),
                'capturedBy' => 'AsyncApexJob reconciliation'
            });
            inputs.add(input);
            orderedCorrelations.add(correlationId);
        }
        if (inputs.isEmpty()) return 0;

        // One bulk call: captureFromEvents handles classification, incident grouping,
        // notification policy and diagnosis dispatch for the whole set together.
        List<AEIR_ErrorCaptureService.CaptureResult> results =
            AEIR_ErrorCaptureService.captureFromEvents(inputs);

        // Stamp the job id in a single DML so the legacy dedupe signal stays populated.
        List<Error_Log__c> stamps = new List<Error_Log__c>();
        for (Integer i = 0; i < results.size() && i < orderedCorrelations.size(); i++) {
            AEIR_ErrorCaptureService.CaptureResult result = results[i];
            if (result == null || result.success != true || result.errorLogId == null) continue;
            AsyncApexJob job = byCorrelation.get(orderedCorrelations[i]);
            if (job == null) continue;
            stamps.add(new Error_Log__c(Id = result.errorLogId, Async_Job_Id__c = String.valueOf(job.Id)));
        }
        if (!stamps.isEmpty()) Database.update(stamps, false);
        return stamps.size();
    }
}