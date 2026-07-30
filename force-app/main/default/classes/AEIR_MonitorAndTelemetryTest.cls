/**
 * Covers the two classes rewritten during code review: the bulk-safe async job
 * reconciler and the subscriber telemetry recorder. Both were changed to fix defects,
 * so they need real assertions rather than smoke coverage.
 */
@IsTest
private class AEIR_MonitorAndTelemetryTest {

    private static final String MASKED = '[MASKED]';

    /** AsyncApexJob is not insertable; JSON is the supported way to build one in a test. */
    private static List<AsyncApexJob> fakeJobs(Integer count) {
        List<AsyncApexJob> jobs = new List<AsyncApexJob>();
        for (Integer i = 0; i < count; i++) {
            String suffix = String.valueOf(100000 + i);
            jobs.add((AsyncApexJob) JSON.deserialize(
                '{"attributes":{"type":"AsyncApexJob"},' +
                '"Id":"707000000000' + suffix + '",' +
                '"Status":"Failed","JobType":"BatchApex",' +
                '"ExtendedStatus":"First error: System.NullPointerException probe ' + i + '",' +
                '"NumberOfErrors":1}', AsyncApexJob.class));
        }
        return jobs;
    }

    @IsTest
    static void reconcileIsBulkSafeForManyFailedJobs() {
        // The defect this replaced called capture() per job, which exceeded the SOQL
        // limit at roughly fifteen jobs. Fifty must stay comfortably inside limits.
        List<AsyncApexJob> jobs = fakeJobs(50);

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        Integer captured = AEIR_AsyncJobMonitorScheduler.reconcile(jobs);
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        System.assertEquals(50, captured, 'Every failed job should be captured.');
        System.assert(queriesUsed <= 10, 'Query cost must not scale with job count, used ' + queriesUsed);
        System.assert(dmlUsed <= 10, 'DML cost must not scale with job count, used ' + dmlUsed);
        System.assertEquals(50, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c LIKE 'ASYNC-%']);
    }

    @IsTest
    static void reconcileIsIdempotent() {
        List<AsyncApexJob> jobs = fakeJobs(5);

        Test.startTest();
        Integer first = AEIR_AsyncJobMonitorScheduler.reconcile(jobs);
        Integer second = AEIR_AsyncJobMonitorScheduler.reconcile(jobs);
        Test.stopTest();

        System.assertEquals(5, first);
        System.assertEquals(0, second, 'A second pass over the same jobs must capture nothing.');
        System.assertEquals(5, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c LIKE 'ASYNC-%']);
    }

    @IsTest
    static void reconcileStampsTheJobIdAndClassifies() {
        Test.startTest();
        AEIR_AsyncJobMonitorScheduler.reconcile(fakeJobs(1));
        Test.stopTest();

        Error_Log__c log = [SELECT Async_Job_Id__c, Source_Type__c, Severity__c, Error_Category__c, Action_Name__c, Context_JSON__c
                            FROM Error_Log__c WHERE Correlation_Id__c LIKE 'ASYNC-%' LIMIT 1];
        System.assertNotEquals(null, log.Async_Job_Id__c, 'The legacy dedupe stamp must still be written.');
        System.assertEquals('Batch', log.Source_Type__c);
        System.assertEquals('High', log.Severity__c);
        System.assertEquals('Null Pointer', log.Error_Category__c, 'The message must still be classified.');
        System.assert(log.Context_JSON__c.contains('asyncApexJobId'), log.Context_JSON__c);
    }

    @IsTest
    static void reconcileHandlesEmptyAndNull() {
        Test.startTest();
        System.assertEquals(0, AEIR_AsyncJobMonitorScheduler.reconcile(null));
        System.assertEquals(0, AEIR_AsyncJobMonitorScheduler.reconcile(new List<AsyncApexJob>()));
        System.assertEquals(0, AEIR_AsyncJobMonitorScheduler.monitorFailedJobs());
        Test.stopTest();
    }

    // ---------- subscriber telemetry ----------

    @IsTest
    static void telemetryRecordsSubscriberFailuresInOneDml() {
        AEIR_SubscriberTelemetry telemetry = new AEIR_SubscriberTelemetry('ReviewProbe');
        System.assertEquals(false, telemetry.hasFailures());

        Test.startTest();
        for (Integer i = 0; i < 20; i++) {
            try {
                throw new AEIR_RetryOrchestrationService.RetryException('probe failure ' + i);
            } catch (Exception e) {
                telemetry.record('TEL-' + i, e);
            }
        }
        System.assertEquals(true, telemetry.hasFailures());
        Integer dmlBefore = Limits.getDmlStatements();
        telemetry.flush();
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        System.assertEquals(1, dmlUsed, 'Twenty failures must cost exactly one DML.');
        System.assertEquals(20, [SELECT count() FROM Delivery_Attempt__c WHERE Correlation_Id__c LIKE 'TEL-%']);
        Delivery_Attempt__c row = [SELECT Channel__c, Status__c, Response_Body__c
                                   FROM Delivery_Attempt__c WHERE Correlation_Id__c = 'TEL-0' LIMIT 1];
        System.assertEquals('Platform Event', row.Channel__c);
        System.assertEquals('Failed', row.Status__c);
        System.assert(row.Response_Body__c.contains('ReviewProbe'), row.Response_Body__c);
    }

    @IsTest
    static void telemetryFlushIsSafeWhenEmptyOrRepeated() {
        AEIR_SubscriberTelemetry telemetry = new AEIR_SubscriberTelemetry(null);
        Test.startTest();
        telemetry.flush();
        telemetry.record(null, null);
        telemetry.flush();
        telemetry.flush();
        Test.stopTest();
        System.assertEquals(false, telemetry.hasFailures(), 'flush() must clear the buffer.');
    }

    // ---------- masking regression ----------

    /**
     * Regression for a crash that took down capture entirely. The long-digit rule has no
     * capture group, but it was being replaced with '$1', so any message containing an
     * order number, record id or card number threw "Index out of Bounds: No group 1".
     */
    @IsTest
    static void maskHandlesLongDigitRunsWithoutThrowing() {
        Test.startTest();
        String cardLike = AEIR_SecuritySanitizerService.mask('Payment failed for card 4111111111111111 on order 9876543210123');
        String recordLike = AEIR_SecuritySanitizerService.mask('Async job 707000000000100000 failed');
        String mixed = AEIR_SecuritySanitizerService.mask('password=hunter2 and card 4111111111111111');
        Test.stopTest();

        System.assert(!cardLike.contains('4111111111111111'), 'Card-length digits must be masked: ' + cardLike);
        System.assert(!recordLike.contains('707000000000100000'), 'Long ids must be masked: ' + recordLike);
        System.assert(!mixed.contains('hunter2'), 'Labelled secrets must still be masked: ' + mixed);
        System.assert(!mixed.contains('4111111111111111'), 'Both rule types must apply: ' + mixed);
        // The packaged Sensitive_Field.PASSWORD rule also masks the label, which is
        // deliberately more conservative than the built-in labelled pattern alone.
        System.assert(mixed.contains(MASKED), 'Something must have been masked: ' + mixed);
    }

    @IsTest
    static void captureSurvivesAMessageContainingLongDigits() {
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.sourceType = 'Apex Class';
        input.sourceName = 'DigitProbe';
        input.originalMessage = 'Order 9876543210123456 could not be created: REQUIRED_FIELD_MISSING';

        Test.startTest();
        AEIR_ErrorCaptureService.CaptureResult result = AEIR_ErrorCaptureService.capture(input);
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Capture must not fail because the message contained a long number.');
        System.assertEquals(1, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c = :result.correlationId]);
    }
}