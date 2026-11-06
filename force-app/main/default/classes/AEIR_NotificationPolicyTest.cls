/**
 * AF-03 / AF-05: proves notification policy and feature flags are actually enforced.
 * Before this work every captured error produced an alert with no throttling at all.
 */
@IsTest
private class AEIR_NotificationPolicyTest {

    @TestSetup
    static void authorizeEventSubscriber() {
        AEIR_CoreTest.createEventProcessorFixtures('Notification');
    }

    private static List<Error_Log__c> buildLogs(Integer count, String severity) {
        List<Error_Log__c> logs = new List<Error_Log__c>();
        for (Integer i = 0; i < count; i++) {
            logs.add(new Error_Log__c(
                Correlation_Id__c = 'POLICY-' + severity + '-' + i + '-' + Datetime.now().getTime(),
                Source_Type__c = 'Apex Class',
                Original_Error_Message__c = 'Policy probe ' + i,
                Severity__c = severity,
                Status__c = 'New',
                User__c = UserInfo.getUserId()
            ));
        }
        insert logs;
        return logs;
    }

    @IsTest
    static void stormIsThrottledByPolicy() {
        // 25 Medium errors for one user. Default policy allows 3/hour with a 15 minute
        // cooldown, so the cooldown should stop everything after the first.
        List<Error_Log__c> logs = buildLogs(25, 'Medium');

        Test.startTest();
        AEIR_UserNotificationService.notifyForErrorLogs(logs);
        Test.stopTest();

        Integer created = [SELECT count() FROM User_Notification__c WHERE Target_User__c = :UserInfo.getUserId()];
        System.assert(created <= 3, 'Policy must cap a storm well below the 25 captured errors, got ' + created);
        System.assert(created >= 1, 'At least the first error should notify, got ' + created);
    }

    @IsTest
    static void severityBelowMinimumIsSuppressed() {
        List<Error_Log__c> logs = buildLogs(3, 'Low');

        Test.startTest();
        Map<Id, AEIR_NotificationPolicyService.Decision> decisions =
            AEIR_NotificationPolicyService.evaluate(logs);
        Test.stopTest();

        for (Error_Log__c log : logs) {
            System.assertEquals(false, decisions.get(log.Id).allowed, 'Low severity is below the Medium minimum.');
            System.assert(decisions.get(log.Id).reason.contains('below the policy minimum'), decisions.get(log.Id).reason);
        }
    }

    @IsTest
    static void criticalBypassesThrottling() {
        List<Error_Log__c> logs = buildLogs(5, 'Critical');

        Test.startTest();
        Map<Id, AEIR_NotificationPolicyService.Decision> decisions =
            AEIR_NotificationPolicyService.evaluate(logs);
        Test.stopTest();

        for (Error_Log__c log : logs) {
            System.assertEquals(true, decisions.get(log.Id).allowed, 'Critical must never be suppressed by throttling.');
        }
    }

    @IsTest
    static void processorCountsPrivateCooldownAndHourlyHistory() {
        Error_Log__c log = buildLogs(1, 'Medium')[0];
        User processor = AEIR_CoreTest.eventActor('Notification', true);
        List<User_Notification__c> history = new List<User_Notification__c>();
        for (Integer i = 0; i < 3; i++) {
            history.add(new User_Notification__c(
                Correlation_Id__c = 'PRIVATE-HISTORY-' + i,
                Target_User__c = log.User__c, OwnerId = log.User__c,
                Notification_Type__c = 'Detected', Severity__c = 'Medium',
                Headline__c = 'Existing alert', Short_Message__c = 'Policy history.',
                Action_Available__c = 'VIEW', Status__c = 'New',
                Expires_At__c = Datetime.now().addHours(24),
                Dedupe_Key__c = 'PRIVATE-HISTORY-' + i + ':' + log.User__c));
        }
        insert history;

        System.runAs(processor) {
            System.assert(Schema.sObjectType.User_Notification__c.isAccessible(),
                'Use a reader who lacks record visibility, not object permission.');
            System.assertEquals(0, [SELECT count() FROM User_Notification__c
                WHERE Target_User__c = :log.User__c], 'The processor has no blanket access to private alerts.');
            System.assertEquals(null, AEIR_UserNotificationService.resolveAlert('PRIVATE-HISTORY-0'),
                'Internal policy maintenance must not expose another user\'s alert.');
            AEIR_NotificationPolicyService.Decision decision =
                AEIR_NotificationPolicyService.evaluate(new List<Error_Log__c>{ log }).get(log.Id);
            System.assertEquals(false, decision.allowed, 'Private recent alerts count toward cooldown.');
            System.assert(decision.reason.contains('cooldown'), decision.reason);
        }

        // Outside the 15 minute cooldown but inside the one hour maximum, the same
        // private records must still consume the affected user's three-alert budget.
        for (User_Notification__c notice : history) {
            Test.setCreatedDate(notice.Id, Datetime.now().addMinutes(-30));
        }
        Test.startTest();
        System.runAs(processor) {
            AEIR_NotificationPolicyService.Decision decision =
                AEIR_NotificationPolicyService.evaluate(new List<Error_Log__c>{ log }).get(log.Id);
            System.assertEquals(false, decision.allowed, 'Private history must consume the hourly budget.');
            System.assert(decision.reason.contains('Hourly alert limit'), decision.reason);
        }
        Test.stopTest();
    }

    @IsTest
    static void processorDeduplicatesPrivateAndRepeatedBatchNotices() {
        Error_Log__c log = buildLogs(1, 'Critical')[0];
        User processor = AEIR_CoreTest.eventActor('Notification', true);
        Test.startTest();
        System.runAs(processor) {
            // Critical bypasses policy throttling, so this proves actual dedupe both
            // within the first batch and against the affected-user-owned result.
            AEIR_UserNotificationService.notifyForErrorLogs(new List<Error_Log__c>{ log, log });
            AEIR_UserNotificationService.notifyForErrorLogs(new List<Error_Log__c>{ log });
            System.assertEquals(0, [SELECT count() FROM User_Notification__c
                WHERE Correlation_Id__c = :log.Correlation_Id__c]);
            System.assertEquals(null, AEIR_UserNotificationService.resolveAlert(log.Correlation_Id__c));
        }
        Test.stopTest();
        List<User_Notification__c> notices = [SELECT OwnerId, Target_User__c FROM User_Notification__c
            WHERE Correlation_Id__c = :log.Correlation_Id__c];
        System.assertEquals(1, notices.size(), 'One durable notice survives both kinds of duplicate input.');
        System.assertEquals(log.User__c, notices[0].OwnerId);
        System.assertEquals(log.User__c, notices[0].Target_User__c);
        System.assertEquals(0, [SELECT count() FROM Delivery_Attempt__c
            WHERE Correlation_Id__c = :log.Correlation_Id__c AND Status__c = 'Failed'],
            'Dedupe must avoid duplicate DML failures, rather than relying on the unique field.');
    }

    @IsTest
    static void featureFlagDisablesNotifications() {
        List<Error_Log__c> logs = buildLogs(2, 'Critical');
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.USER_NOTIFICATIONS, false);

        Test.startTest();
        AEIR_UserNotificationService.notifyForErrorLogs(logs);
        Test.stopTest();

        System.assertEquals(0, [SELECT count() FROM User_Notification__c WHERE Target_User__c = :UserInfo.getUserId()],
            'Disabling the USER_NOTIFICATIONS flag must suppress all alerts.');
    }

    @IsTest
    static void featureFlagBlocksRemediation() {
        Account a = new Account(Name = 'Aegis Flag Test');
        insert a;
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, false);

        AEIR_RemediationOrchestrator.RemediationRequest req = new AEIR_RemediationOrchestrator.RemediationRequest();
        req.actionKey = 'UPDATE_ACCOUNT_DESCRIPTION';
        req.objectApiName = 'Account';
        req.recordId = a.Id;
        req.fieldApiName = 'Description';
        req.newValue = 'should not apply';
        req.confirmed = true;

        Test.startTest();
        AEIR_RemediationOrchestrator.RemediationResult res = AEIR_RemediationOrchestrator.execute(req);
        Test.stopTest();

        System.assertEquals(false, res.success, 'Remediation must be blocked when its feature flag is off.');
        System.assert(res.technicalMessage.contains('disabled'), res.technicalMessage);
        System.assertEquals(null, [SELECT Description FROM Account WHERE Id = :a.Id].Description);
    }

    @IsTest
    static void enabledFlagsResolveFromMetadata() {
        System.assertEquals(true, AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.USER_NOTIFICATIONS));
        System.assertEquals(false, AEIR_FeatureFlagService.isEnabled('NO_SUCH_FEATURE'),
            'Unknown feature keys must resolve to disabled.');
        System.assertEquals(false, AEIR_FeatureFlagService.isEnabled(null));
    }

    /**
     * AF-24: the async round trip. Capture publishes a Detected alert and a diagnosis
     * request; the gateway then upgrades the same notification to Diagnosed. Previously
     * nothing published either side, so the utility spinner never resolved.
     */
    @IsTest
    static void eventDeliveryRespectsSubscriberAuthorization() {
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AI_DIAGNOSIS, true);

        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.sourceType = 'Apex Class';
        input.sourceName = 'RoundTripTest';
        input.originalMessage = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: Tax Code is required.';
        input.severity = 'High';

        Test.startTest();
        AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(input);
        Boolean subscriberAuthorized = AEIR_CoreTest.eventSubscriberAuthorized(captured.errorLogId);

        // Before the event bus drains, only the "Detected" spinner state exists.
        User_Notification__c detected = [
            SELECT Notification_Type__c, Headline__c, Action_Available__c FROM User_Notification__c
            WHERE Correlation_Id__c = :captured.correlationId LIMIT 1
        ];
        System.assertEquals('Detected', detected.Notification_Type__c, 'Capture should create the Detected alert.');

        // Exercise the real transport. Its native principal must either complete
        // processing when authorized or fail closed with observable telemetry.
        Test.getEventBus().deliver();
        Test.stopTest();

        User_Notification__c upgraded = [
            SELECT Notification_Type__c, Headline__c, Action_Available__c FROM User_Notification__c
            WHERE Correlation_Id__c = :captured.correlationId LIMIT 1
        ];
        if (!subscriberAuthorized) {
            System.assertEquals('Detected', upgraded.Notification_Type__c, 'An unauthorized subscriber must not fabricate an outcome.');
            System.assertEquals(detected.Headline__c, upgraded.Headline__c);
            System.assertEquals(1, [SELECT count() FROM User_Notification__c WHERE Correlation_Id__c = :captured.correlationId]);
            System.assertEquals('New', [SELECT Status__c FROM Error_Log__c WHERE Id = :captured.errorLogId].Status__c);
            AEIR_CoreTest.assertSubscriberRejection(captured.errorLogId, captured.correlationId);
            return;
        }
        System.assertEquals('Diagnosed', upgraded.Notification_Type__c,
            'An authorized diagnosis subscriber must upgrade the same notification in place.');
        System.assertEquals(1, [SELECT count() FROM User_Notification__c WHERE Correlation_Id__c = :captured.correlationId],
            'The upgrade must replace the alert, not stack a second one.');
        System.assertNotEquals(detected.Headline__c, upgraded.Headline__c,
            'The upgraded alert should carry an outcome-specific headline.');
        System.assertEquals('Diagnosed', [SELECT Status__c FROM Error_Log__c WHERE Id = :captured.errorLogId].Status__c);
    }

    @IsTest
    static void configuredProcessorUpgradesTheAlertInPlace() {
        // Transport authorization is tested independently above. Exercise the same
        // handler with an explicitly configured normal runtime user's native grants.
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AI_DIAGNOSIS, false);
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.sourceType = 'Apex Class'; input.sourceName = 'ConfiguredRoundTripTest';
        input.originalMessage = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: Tax Code is required.';
        input.severity = 'High';
        User processor = AEIR_CoreTest.eventActor('Notification', true);
        Test.startTest();
        AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(input);
        User_Notification__c detected = [SELECT Notification_Type__c, Headline__c
            FROM User_Notification__c WHERE Correlation_Id__c = :captured.correlationId LIMIT 1];
        System.assertEquals('Detected', detected.Notification_Type__c);
        System.runAs(processor) {
            System.assert(FeatureManagement.checkPermission('AEIR_Process_Diagnostics'), 'Use the native runtime capability.');
            System.assert(!FeatureManagement.checkPermission('AEIR_View_Sensitive_Context'));
            System.assertEquals(0, [SELECT count() FROM User_Notification__c
                WHERE Correlation_Id__c = :captured.correlationId], 'The processor cannot browse the private alert.');
            System.assertEquals(null, AEIR_UserNotificationService.resolveAlert(captured.correlationId));
            AEIR_AgentDiagnosisRequestedEventHandler.handle(new List<Agent_Diagnosis_Requested__e>{
                new Agent_Diagnosis_Requested__e(Correlation_Id__c = captured.correlationId,
                    Error_Log_Id__c = String.valueOf(captured.errorLogId))
            });
        }
        Test.stopTest();
        User_Notification__c upgraded = [SELECT Notification_Type__c, Headline__c, Action_Available__c
            FROM User_Notification__c WHERE Correlation_Id__c = :captured.correlationId LIMIT 1];
        System.assertEquals('Diagnosed', upgraded.Notification_Type__c,
            'The configured processor must upgrade the same notification in place.');
        System.assertEquals(1, [SELECT count() FROM User_Notification__c WHERE Correlation_Id__c = :captured.correlationId],
            'The upgrade must replace the alert, not stack a second one.');
        System.assertNotEquals(detected.Headline__c, upgraded.Headline__c,
            'The upgraded alert must carry an outcome-specific headline.');
        System.assertEquals('Diagnosed', [SELECT Status__c FROM Error_Log__c WHERE Id = :captured.errorLogId].Status__c);
        AI_Diagnosis__c diagnosis = [SELECT CreatedById, OwnerId FROM AI_Diagnosis__c WHERE Error_Log__c = :captured.errorLogId];
        System.assertEquals(processor.Id, diagnosis.CreatedById);
        System.assertEquals(UserInfo.getUserId(), diagnosis.OwnerId, 'Preserve affected-user result ownership.');
    }

    @IsTest
    static void dismissedAlertIsNotResurrectedByDiagnosis() {
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.sourceType = 'Apex Class';
        input.sourceName = 'DismissTest';
        input.originalMessage = 'System.NullPointerException: probe';
        input.severity = 'High';
        AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(input);

        Test.startTest();
        AEIR_UserNotificationService.dismiss(captured.correlationId);
        Error_Log__c log = [SELECT Id, Correlation_Id__c, User__c, Severity__c FROM Error_Log__c WHERE Id = :captured.errorLogId];
        AEIR_UserNotificationService.notifyDiagnosisComplete(log, 'DEVELOPER_ONLY', 'Developer attention required.');
        Test.stopTest();

        System.assertEquals('Dismissed',
            [SELECT Status__c FROM User_Notification__c WHERE Correlation_Id__c = :captured.correlationId LIMIT 1].Status__c,
            'A dismissed alert must stay dismissed (spec 20.1 cooldown behaviour).');
    }
}
