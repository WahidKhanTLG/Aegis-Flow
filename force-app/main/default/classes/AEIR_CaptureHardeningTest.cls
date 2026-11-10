@IsTest
private class AEIR_CaptureHardeningTest {
    @TestSetup
    static void users() {
        User caller = new User(Alias = 'afbound', Email = 'boundary@example.invalid',
            Username = 'af-boundary-' + Datetime.now().getTime() + '@example.invalid',
            LastName = 'AegisCaptureBoundary', ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
        insert caller;
        // Check-only deployment leaves the org's existing AEIR_End_User grants
        // effective during tests. Use isolated least-privilege setup data for the
        // runtime boundary; local_audit separately checks the shipped role XML.
        PermissionSet role = new PermissionSet(Name = 'AEIR_CaptureBoundaryFixture', Label = 'Aegis capture boundary fixture');
        insert role;
        insert new ObjectPermissions(ParentId = role.Id, SObjectType = 'Diagnostic_Session__c',
            PermissionsRead = true, PermissionsCreate = true);
        insert new FieldPermissions(ParentId = role.Id, SObjectType = 'Diagnostic_Session__c',
            Field = 'Diagnostic_Session__c.User__c', PermissionsRead = true, PermissionsEdit = false);
        insert new SetupEntityAccess(ParentId = role.Id,
            SetupEntityId = [SELECT Id FROM ApexClass WHERE Name = 'AEIR_HelpMeController' LIMIT 1].Id);
        insert new PermissionSetAssignment(AssigneeId = caller.Id, PermissionSetId = role.Id);
    }
    private static void quiet() {
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.USER_NOTIFICATIONS, false);
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AUTO_DIAGNOSIS, false);
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AI_DIAGNOSIS, false);
    }
    @IsTest static void restrictedUserHasNoInternalSessionStreamAccessAndHelpStillWorks() {
        User caller = [SELECT Id FROM User WHERE LastName = 'AegisCaptureBoundary' LIMIT 1];
        insert new Error_Log__c(Correlation_Id__c = 'HELP-ME-UNREADABLE-ERROR', User__c = caller.Id,
            OwnerId = caller.Id, Source_Type__c = 'Flow', Status__c = 'New');
        System.runAs(caller) {
            System.assertEquals(false, Schema.sObjectType.Error_Log__c.isAccessible());
            System.assertEquals(false, Diagnostic_Session_Requested__e.SObjectType.getDescribe().isAccessible());
            System.assertEquals(false, Diagnostic_Session_Requested__e.SObjectType.getDescribe().isCreateable());
            AEIR_HelpMeController.HelpMeResponse result = AEIR_HelpMeController.createSession('{}', 'Help with saving', 'Save Error');
            Diagnostic_Session__c session = [SELECT User__c FROM Diagnostic_Session__c WHERE Id = :result.sessionId];
            System.assertEquals(caller.Id, session.User__c);
            System.assertEquals(null, result.recentErrorLogId, 'A manual session must not associate unreadable technical evidence.');
        }
    }
    @IsTest static void eventCannotSpoofAnotherActiveUser() {
        User victim = [SELECT Id FROM User WHERE LastName = 'AegisCaptureBoundary' LIMIT 1];
        List<Diagnostic_Session_Requested__e> events = AEIR_EventTestData.sessions(
            new List<Diagnostic_Session_Requested__e>{
                new Diagnostic_Session_Requested__e(Correlation_Id__c = 'SPOOFED-SESSION', User_Id__c = victim.Id),
                new Diagnostic_Session_Requested__e(Correlation_Id__c = 'AUTHENTIC-SESSION', User_Id__c = UserInfo.getUserId())
            }, UserInfo.getUserId());
        Test.startTest();
        AEIR_DiagnosticSessionRequestHandler.handle(events);
        Test.stopTest();
        System.assertEquals(0, [SELECT count() FROM Diagnostic_Session__c WHERE Correlation_Id__c = 'SPOOFED-SESSION']);
        System.assertEquals(1, [SELECT count() FROM Diagnostic_Session__c WHERE Correlation_Id__c = 'AUTHENTIC-SESSION']);
        System.assertEquals(1, [SELECT count() FROM Delivery_Attempt__c WHERE Correlation_Id__c = 'SPOOFED-SESSION']);
    }
    @IsTest static void missingPublisherIsRejectedAndOmittedUserUsesPublisher() {
        AEIR_DiagnosticSessionRequestHandler.handle(new List<Diagnostic_Session_Requested__e>{
            new Diagnostic_Session_Requested__e(Correlation_Id__c = 'NO-PUBLISHER') });
        AEIR_DiagnosticSessionRequestHandler.handle(AEIR_EventTestData.sessions(
            new List<Diagnostic_Session_Requested__e>{new Diagnostic_Session_Requested__e(Correlation_Id__c = 'FROM-PUBLISHER')}, UserInfo.getUserId()));
        System.assertEquals(0, [SELECT count() FROM Diagnostic_Session__c WHERE Correlation_Id__c = 'NO-PUBLISHER']);
        System.assertEquals(UserInfo.getUserId(), [SELECT User__c FROM Diagnostic_Session__c WHERE Correlation_Id__c = 'FROM-PUBLISHER'].User__c);
    }
    @IsTest static void rejectedCaptureDoesNotDisappearOrAbandonValidEvent() {
        quiet();
        Test.startTest();
        AEIR_ErrorCapturedEventHandler.handle(new List<Error_Captured__e>{
            new Error_Captured__e(Correlation_Id__c = 'CAPTURE-REJECTED', Source_Type__c = 'Unregistered Source'),
            new Error_Captured__e(Correlation_Id__c = 'CAPTURE-ACCEPTED', Source_Type__c = 'Flow', Error_Message__c = 'Save failed') });
        Test.stopTest();
        System.assertEquals(1, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c = 'CAPTURE-ACCEPTED']);
        System.assertEquals(0, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c = 'CAPTURE-REJECTED']);
        System.assertEquals(1, [SELECT count() FROM Delivery_Attempt__c WHERE Correlation_Id__c = 'CAPTURE-REJECTED' AND Status__c = 'Failed']);
    }
    @IsTest static void temporaryFailuresRetryAndExhaustionIsReported() {
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.correlationId = 'TEMPORARY-CAPTURE';
        AEIR_ErrorCaptureService.CaptureResult failed = new AEIR_ErrorCaptureService.CaptureResult();
        failed.success = false; failed.retryable = true; failed.message = 'Temporary persistence failure';
        Boolean retried = false;
        try { AEIR_ErrorCapturedEventHandler.recordResults(
            new List<AEIR_ErrorCaptureService.ErrorInput>{input}, new List<AEIR_ErrorCaptureService.CaptureResult>{failed}, 'CaptureRetry', 0); }
        catch (EventBus.RetryableException expected) { retried = true; }
        System.assert(retried, 'Transient event delivery must be retried rather than acknowledged as success.');
        AEIR_ErrorCapturedEventHandler.recordResults(new List<AEIR_ErrorCaptureService.ErrorInput>{input},
            new List<AEIR_ErrorCaptureService.CaptureResult>{failed}, 'CaptureRetry', 9);
        System.assertEquals(1, [SELECT count() FROM Delivery_Attempt__c WHERE Correlation_Id__c = 'TEMPORARY-CAPTURE']);
    }
    @IsTest static void guardDoesNotReturnAnAcceptedReferenceForRejectedPublication() {
        quiet();
        String tooLong = ''.leftPad(300, 'x');
        Test.startTest();
        String correlation = AEIR_Guard.capture(null, tooLong);
        Test.stopTest();
        System.assertEquals(null, correlation, 'A rejected event must not yield a reference implying acceptance.');
    }
    @IsTest static void finalPublicationFailureIsRecordedOutsideTheOriginatingTransaction() {
        quiet();
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.correlationId = 'FINAL-PUBLISH-FAILURE'; input.sourceType = 'Flow';
        Test.startTest();
        System.assertEquals(true, AEIR_ErrorCaptureService.publish(input).success, 'The first result only acknowledges queuing.');
        Test.getEventBus().fail();
        Test.stopTest();
        System.assertEquals(0, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c = :input.correlationId]);
        System.assertEquals(1, [SELECT count() FROM Delivery_Attempt__c WHERE Correlation_Id__c = :input.correlationId AND Status__c = 'Failed']);
    }
    private static BatchApexErrorEvent batchEvent(String uuid, String scope) {
        return (BatchApexErrorEvent)JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'AsyncApexJobId' => '707000000000001', 'EventUuid' => uuid, 'Phase' => 'EXECUTE',
            'JobScope' => scope, 'ExceptionType' => 'DmlException', 'Message' => 'FIELD_CUSTOM_VALIDATION_EXCEPTION',
            'CreatedDate' => Datetime.now(), 'CreatedById' => UserInfo.getUserId()
        }), BatchApexErrorEvent.class);
    }
    @IsTest static void batchScopesAreDistinctAndReplayedEventsAreDeduplicated() {
        quiet();
        BatchApexErrorEvent first = batchEvent('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '001000000000001');
        BatchApexErrorEvent second = batchEvent('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '001000000000002');
        Test.startTest();
        AEIR_BatchApexErrorEventHandler.handle(new List<BatchApexErrorEvent>{first, second, first});
        AEIR_BatchApexErrorEventHandler.handle(new List<BatchApexErrorEvent>{second});
        Test.stopTest();
        List<Error_Log__c> logs = [SELECT Correlation_Id__c, Context_JSON__c FROM Error_Log__c WHERE Source_Type__c = 'Batch'];
        System.assertEquals(2, logs.size(), 'Each real failed scope survives, while replay does not add another log.');
        System.assertNotEquals(logs[0].Correlation_Id__c, logs[1].Correlation_Id__c);
        for (Error_Log__c log : logs) System.assert(log.Correlation_Id__c.length() <= 80);
    }
}
