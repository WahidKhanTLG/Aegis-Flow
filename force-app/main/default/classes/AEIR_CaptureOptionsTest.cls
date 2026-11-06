@IsTest
private class AEIR_CaptureOptionsTest {
    private static void enableFollowUps() {
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.USER_NOTIFICATIONS, true);
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AUTO_DIAGNOSIS, true);
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AI_DIAGNOSIS, true);
    }
    private static AEIR_ErrorCaptureService.ErrorInput input(String correlation) {
        AEIR_ErrorCaptureService.ErrorInput value = new AEIR_ErrorCaptureService.ErrorInput();
        value.correlationId = correlation;
        value.sourceType = 'Manual';
        value.sourceName = 'Capture options regression';
        value.originalMessage = 'REQUIRED_FIELD_MISSING: Name';
        value.contextJson = '{"password":"CAPTURE-OPTIONS-SECRET"}';
        value.severity = 'Critical';
        return value;
    }
    private static AEIR_ErrorCaptureService.CaptureOptions isolated() {
        AEIR_ErrorCaptureService.CaptureOptions options = new AEIR_ErrorCaptureService.CaptureOptions();
        options.notifyUser = false;
        options.requestDiagnosis = false;
        return options;
    }
    @IsTest
    static void isolatedSingleCapturePersistsEvidenceWithoutAnyFollowUp() {
        enableFollowUps();
        Test.startTest();
        AEIR_ErrorCaptureService.CaptureResult result = AEIR_ErrorCaptureService.capture(input('ISOLATED-SINGLE'), isolated());
        Test.getEventBus().deliver();
        Test.stopTest();
        System.assertEquals(true, result.success);
        Error_Log__c stored = [SELECT Context_JSON__c, Status__c FROM Error_Log__c WHERE Id = :result.errorLogId];
        System.assertEquals('New', stored.Status__c);
        System.assert(!stored.Context_JSON__c.contains('CAPTURE-OPTIONS-SECRET'));
        System.assertEquals(1, [SELECT count() FROM Error_Context__c WHERE Error_Log__c = :result.errorLogId]);
        System.assertEquals(0, [SELECT count() FROM User_Notification__c]);
        System.assertEquals(0, [SELECT count() FROM AI_Diagnosis__c]);
        System.assertEquals(0, [SELECT count() FROM Delivery_Attempt__c], 'No notice or diagnosis publication may escape a probe.');
    }
    @IsTest
    static void isolatedBatchRetainsOrderingAndDedupeWithoutFollowUpWork() {
        enableFollowUps();
        List<AEIR_ErrorCaptureService.ErrorInput> values = new List<AEIR_ErrorCaptureService.ErrorInput>{
            input('ISOLATED-BATCH-B'), input('ISOLATED-BATCH-A'), input('ISOLATED-BATCH-B')
        };
        Test.startTest();
        List<AEIR_ErrorCaptureService.CaptureResult> results = AEIR_ErrorCaptureService.captureFromEvents(values, isolated());
        Test.getEventBus().deliver();
        Test.stopTest();
        System.assertEquals(3, results.size());
        System.assertEquals('ISOLATED-BATCH-B', results[0].correlationId);
        System.assertEquals('ISOLATED-BATCH-A', results[1].correlationId);
        System.assertEquals(results[0].errorLogId, results[2].errorLogId);
        System.assertEquals(2, [SELECT count() FROM Error_Log__c]);
        System.assertEquals(0, [SELECT count() FROM User_Notification__c]);
        System.assertEquals(0, [SELECT count() FROM AI_Diagnosis__c]);
        System.assertEquals(0, [SELECT count() FROM Delivery_Attempt__c]);
    }
    @IsTest
    static void automaticDeterministicDiagnosisDoesNotRequireRemoteAi() {
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.USER_NOTIFICATIONS, false);
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AUTO_DIAGNOSIS, true);
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AI_DIAGNOSIS, false);
        Test.startTest();
        AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(input('AUTOMATIC-DETERMINISTIC'));
        Boolean authorized = AEIR_CoreTest.eventSubscriberAuthorized(captured.errorLogId);
        Test.getEventBus().deliver();
        Test.stopTest();
        if (authorized) {
            System.assertEquals(1, [SELECT count() FROM AI_Diagnosis__c WHERE Error_Log__c = :captured.errorLogId]);
        } else {
            System.assertEquals(0, [SELECT count() FROM AI_Diagnosis__c WHERE Error_Log__c = :captured.errorLogId]);
            System.assertEquals(1, [SELECT count() FROM Delivery_Attempt__c WHERE Correlation_Id__c = :captured.correlationId
                AND Status__c = 'Failed' AND Idempotency_Key__c LIKE 'AgentDiagnosisRequested:%'],
                'The deterministic request must reach its actual runtime authorization boundary.');
        }
        System.assertEquals(0, Limits.getCallouts(), 'The remote AI flag remains off.');
        System.assertEquals(0, [SELECT count() FROM User_Notification__c]);
    }
}
