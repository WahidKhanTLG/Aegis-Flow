/**
 * Zero-instrumentation Flow capture. FlowInterview rows cannot be created in a test,
 * so these cover the reconciler's contract, idempotency and label parsing.
 */
@IsTest
private class AEIR_FlowInterviewMonitorTest {

    @IsTest
    static void reconcileIsSafeWhenNothingHasFailed() {
        Test.startTest();
        Integer captured = AEIR_FlowInterviewMonitor.reconcile();
        Test.stopTest();
        System.assert(captured >= 0, 'Reconciliation must never throw, even with nothing to do.');
    }

    @IsTest
    static void schedulableEntryPointRuns() {
        Test.startTest();
        String jobId = System.schedule('Aegis Flow Interview Monitor Test', '0 30 * * * ?',
                                       new AEIR_FlowInterviewMonitor());
        Test.stopTest();
        System.assertNotEquals(null, jobId);
        System.assertEquals(1, [SELECT count() FROM CronTrigger
                                WHERE CronJobDetail.Name = 'Aegis Flow Interview Monitor Test']);
    }

    @IsTest
    static void alreadyCapturedInterviewsAreNotDuplicated() {
        // A prior run captured this interview; a second pass must not create another log.
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.correlationId = 'FLOWINT-probe-guid-0001';
        input.sourceType = 'Flow';
        input.sourceName = 'Aegis Metrics Probe / Create_Invalid_Contact';
        input.originalMessage = 'REQUIRED_FIELD_MISSING: Required fields are missing: [LastName]';
        AEIR_ErrorCaptureService.capture(input);

        Test.startTest();
        AEIR_FlowInterviewMonitor.reconcile();
        Test.stopTest();

        System.assertEquals(1,
            [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c = 'FLOWINT-probe-guid-0001'],
            'The correlation id is a unique external id, so re-running must not duplicate.');
    }

    @IsTest
    static void interviewLabelTimestampIsStrippedForStableGrouping() {
        // Incident grouping keys on source name, so the per-run timestamp must not leak in.
        FlowInterview interview = new FlowInterview(
            InterviewLabel = 'Aegis Metrics Probe 7/27/2026, 4:00 PM',
            CurrentElement = 'Create_Invalid_Contact'
        );
        String resolved = AEIR_FlowInterviewMonitor.sourceName(interview);
        System.assertEquals('Aegis Metrics Probe / Create_Invalid_Contact', resolved, resolved);

        FlowInterview noElement = new FlowInterview(InterviewLabel = 'Order Sync 1/2/2026, 9:15 AM');
        System.assertEquals('Order Sync', AEIR_FlowInterviewMonitor.sourceName(noElement));

        FlowInterview blank = new FlowInterview();
        System.assertEquals('Unknown Flow', AEIR_FlowInterviewMonitor.sourceName(blank));
    }

    /**
     * Real-time path. FlowExecutionErrorEvent carries ContextRecordId, which FlowInterview
     * does not, so a real-time capture produces a richer log than the poll.
     */
    @IsTest
    static void realTimeFlowEventCapturesRecordContext() {
        Account a = new Account(Name = 'Aegis RT Test');
        insert a;
        String payload = JSON.serialize(new Map<String, Object>{
            'FlowApiName' => 'Aegis_Test_Order_On_Closed_Won',
            'ElementApiName' => 'Create_Order_Without_Account',
            'ElementType' => 'RecordCreate',
            'ErrorMessage' => 'REQUIRED_FIELD_MISSING: Select an account.',
            'ExtendedErrorCode' => 'REQUIRED_FIELD_MISSING',
            'ContextRecordId' => a.Id,
            'ContextObject' => 'Account',
            'UserId' => UserInfo.getUserId(),
            'InterviewGuid' => 'rt-guid-0001'
        });

        Test.startTest();
        String correlationId = AEIR_AegisHeadlessMonitorController.captureFlowError(payload);
        Test.stopTest();

        System.assertEquals('FLOWINT-rt-guid-0001', correlationId,
            'The correlation id must match the poll scheme so the two paths dedupe.');
        Error_Log__c log = [
            SELECT Source_Name__c, Record_Id__c, Object_API_Name__c, Error_Category__c, Action_Name__c
            FROM Error_Log__c WHERE Correlation_Id__c = :correlationId
        ];
        System.assertEquals('Aegis_Test_Order_On_Closed_Won / Create_Order_Without_Account', log.Source_Name__c);
        System.assertEquals(String.valueOf(a.Id), log.Record_Id__c, 'The record id is the advantage over the poll.');
        System.assertEquals('Account', log.Object_API_Name__c);
        System.assertEquals('Missing Data', log.Error_Category__c);
    }

    @IsTest
    static void realTimeAndPollDoNotDoubleCapture() {
        String payload = JSON.serialize(new Map<String, Object>{
            'FlowApiName' => 'Dedupe_Probe',
            'ElementApiName' => 'Update_Records',
            'ErrorMessage' => 'FIELD_CUSTOM_VALIDATION_EXCEPTION: probe',
            'UserId' => UserInfo.getUserId(),
            'InterviewGuid' => 'dedupe-guid-0001'
        });

        Test.startTest();
        String first = AEIR_AegisHeadlessMonitorController.captureFlowError(payload);
        String second = AEIR_AegisHeadlessMonitorController.captureFlowError(payload);
        AEIR_FlowInterviewMonitor.reconcile();
        Test.stopTest();

        System.assertEquals(first, second);
        System.assertEquals(1, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c = :first],
            'Correlation_Id__c is a unique external id, so real-time and poll cannot duplicate.');
    }

    @IsTest
    static void malformedRealTimePayloadIsIgnored() {
        Test.startTest();
        System.assertEquals(null, AEIR_AegisHeadlessMonitorController.captureFlowError(null));
        System.assertEquals(null, AEIR_AegisHeadlessMonitorController.captureFlowError('not json'));
        Test.stopTest();
    }

    /**
     * Regression: a capture whose notification was throttled must still be viewable.
     * Throttling controls interruption, not access. Previously this raised
     * "You are not authorized", which read as a permission problem and was not one.
     */
    @IsTest
    static void suppressedNotificationStillAllowsViewingDetails() {
        AEIR_ErrorCaptureService.ErrorInput first = new AEIR_ErrorCaptureService.ErrorInput();
        first.sourceType = 'Flow';
        first.sourceName = 'Throttle_Probe / A';
        first.originalMessage = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: first';
        first.severity = 'Medium';
        AEIR_ErrorCaptureService.capture(first);

        // Second capture lands inside the cooldown, so no notification is created.
        AEIR_ErrorCaptureService.ErrorInput second = new AEIR_ErrorCaptureService.ErrorInput();
        second.sourceType = 'Flow';
        second.sourceName = 'Throttle_Probe / B';
        second.originalMessage = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: second';
        second.severity = 'Medium';
        AEIR_ErrorCaptureService.CaptureResult throttled = AEIR_ErrorCaptureService.capture(second);

        Test.startTest();
        AEIR_UserNotificationService.DetailDTO detail =
            AEIR_AegisHeadlessMonitorController.getAlertDetails(throttled.correlationId);
        Test.stopTest();

        System.assertNotEquals(null, detail.errorLog,
            'A throttled alert must still expose its diagnostic when the user asks for it.');
        System.assertNotEquals(null, detail.alert, 'A synthetic alert view must be returned.');
        System.assertEquals(true, detail.canEscalate);
    }

    @IsTest
    static void anotherUsersDiagnosticIsStillRefused() {
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.sourceType = 'Flow';
        input.sourceName = 'Foreign_Probe';
        input.originalMessage = 'System.NullPointerException: not yours';
        AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(input);

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User other = new User(FirstName = 'Aegis', LastName = 'Other', Alias = 'aot',
            Email = 'aegis.other@example.com',
            Username = 'aegis.other.' + Datetime.now().getTime() + '@example.invalid',
            ProfileId = p.Id, TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
        insert other;

        Boolean refused = false;
        Test.startTest();
        System.runAs(other) {
            try {
                AEIR_AegisHeadlessMonitorController.getAlertDetails(captured.correlationId);
            } catch (Exception e) {
                refused = true;
            }
        }
        Test.stopTest();
        System.assertEquals(true, refused, 'The fallback must not leak another user\'s diagnostic.');
    }
}