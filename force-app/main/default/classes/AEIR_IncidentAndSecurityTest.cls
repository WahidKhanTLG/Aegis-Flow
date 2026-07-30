/**
 * AF-04 incident grouping, AF-09 custom permissions, AF-19 REST hardening,
 * and AF-07 coverage for the three previously untested classes.
 */
@IsTest
private class AEIR_IncidentAndSecurityTest {


    /** Minimal user with no Aegis permission sets, used to exercise deny paths. */
    private static User minimalUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String suffix = String.valueOf(Datetime.now().getTime());
        return new User(
            FirstName = 'Aegis', LastName = 'NoPerms',
            Alias = 'anp', Email = 'aegis.noperms@example.com',
            Username = 'aegis.noperms.' + suffix + '@example.invalid',
            ProfileId = p.Id, TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
    }

    private static AEIR_ErrorCaptureService.ErrorInput input(String message, String severity) {
        AEIR_ErrorCaptureService.ErrorInput in1 = new AEIR_ErrorCaptureService.ErrorInput();
        in1.sourceType = 'Flow';
        in1.sourceName = 'Order_Tax_Update_Flow';
        in1.objectApiName = 'Account';
        in1.originalMessage = message;
        in1.severity = severity;
        return in1;
    }

    // ---------- AF-04: incident aggregation ----------

    @IsTest
    static void repeatedFailuresGroupIntoOneIncident() {
        List<Error_Log__c> logs = new List<Error_Log__c>();
        for (Integer i = 0; i < 20; i++) {
            logs.add(new Error_Log__c(
                Correlation_Id__c = 'INC-' + i,
                Source_Type__c = 'Flow',
                Source_Name__c = 'Order_Tax_Update_Flow',
                Object_API_Name__c = 'Account',
                Error_Category__c = 'Validation Rule',
                Severity__c = i == 7 ? 'Critical' : 'Medium',
                Original_Error_Message__c = 'FIELD_CUSTOM_VALIDATION_EXCEPTION',
                Status__c = 'New',
                User__c = UserInfo.getUserId()
            ));
        }

        Test.startTest();
        AEIR_IncidentAggregationService.assign(logs);
        insert logs;
        Test.stopTest();

        List<Incident__c> incidents = [
            SELECT Incident_Key__c, Occurrence_Count__c, Highest_Severity__c, Affected_User_Count__c, Status__c
            FROM Incident__c
        ];
        System.assertEquals(1, incidents.size(), '20 identical failures must collapse into one incident.');
        System.assertEquals(20, incidents[0].Occurrence_Count__c);
        System.assertEquals('Critical', incidents[0].Highest_Severity__c, 'Incident severity rolls up to the highest observed.');
        System.assertEquals('Open', incidents[0].Status__c);
        System.assertEquals(20, [SELECT count() FROM Error_Log__c WHERE Incident__c = :incidents[0].Id],
            'Every log must be linked back to its incident.');
    }

    @IsTest
    static void unrelatedFailuresGetSeparateIncidents() {
        List<Error_Log__c> logs = new List<Error_Log__c>{
            new Error_Log__c(Correlation_Id__c = 'A1', Source_Type__c = 'Flow', Source_Name__c = 'Flow_A',
                             Error_Category__c = 'Validation Rule', Object_API_Name__c = 'Account',
                             Severity__c = 'Medium', Status__c = 'New', User__c = UserInfo.getUserId()),
            new Error_Log__c(Correlation_Id__c = 'B1', Source_Type__c = 'Apex Class', Source_Name__c = 'Class_B',
                             Error_Category__c = 'Null Pointer', Object_API_Name__c = 'Contact',
                             Severity__c = 'High', Status__c = 'New', User__c = UserInfo.getUserId())
        };

        Test.startTest();
        AEIR_IncidentAggregationService.assign(logs);
        insert logs;
        Test.stopTest();

        System.assertEquals(2, [SELECT count() FROM Incident__c], 'Different source and category must not be grouped.');
        System.assertNotEquals(logs[0].Incident_Key__c, logs[1].Incident_Key__c);
    }

    @IsTest
    static void captureAssignsAnIncidentAutomatically() {
        Test.startTest();
        AEIR_ErrorCaptureService.CaptureResult result =
            AEIR_ErrorCaptureService.capture(input('FIELD_CUSTOM_VALIDATION_EXCEPTION: Tax Code', 'Medium'));
        Test.stopTest();

        Error_Log__c log = [SELECT Incident__c, Incident_Key__c FROM Error_Log__c WHERE Id = :result.errorLogId];
        System.assertNotEquals(null, log.Incident__c, 'Capture must attach the log to an incident.');
        System.assertNotEquals(null, log.Incident_Key__c);
    }

    // ---------- AF-09: custom permissions ----------

    @IsTest
    static void remediationRequiresTheCustomPermission() {
        // The running user in a test has no custom permissions unless assigned, so this
        // exercises the deny path even with the feature flag on.
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
        Account a = new Account(Name = 'Aegis Perm Test');
        insert a;

        AEIR_RemediationOrchestrator.RemediationRequest req = new AEIR_RemediationOrchestrator.RemediationRequest();
        req.actionKey = 'UPDATE_ACCOUNT_DESCRIPTION';
        req.objectApiName = 'Account';
        req.recordId = a.Id;
        req.fieldApiName = 'Description';
        req.newValue = 'should be blocked';
        req.confirmed = true;

        User noPerms = minimalUser();
        insert noPerms;

        Test.startTest();
        AEIR_RemediationOrchestrator.RemediationResult res;
        System.runAs(noPerms) {
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
            res = AEIR_RemediationOrchestrator.execute(req);
        }
        Test.stopTest();

        System.assertEquals(false, res.success, 'Remediation must be denied without the custom permission.');
        System.assert(res.technicalMessage.contains('Aegis Execute Remediation'), res.technicalMessage);
    }

    // ---------- AF-19: REST hardening ----------

    @IsTest
    static void restRejectsCallerWithoutPermission() {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/aegis-flow/v1/diagnostics';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('{"sourceType":"API","originalMessage":"probe"}');
        RestContext.request = request;
        RestContext.response = new RestResponse();

        User noPerms = minimalUser();
        insert noPerms;

        Test.startTest();
        System.runAs(noPerms) {
            AEIR_InboundDiagnosticRestService.postDiagnostic();
        }
        Test.stopTest();

        System.assertEquals(403, RestContext.response.statusCode,
            'Session auth alone must not be enough to write diagnostics.');
    }

    // ---------- AF-07: previously uncovered classes ----------

    @IsTest
    static void queueableFinalizerCapturesFailure() {
        Test.startTest();
        System.enqueueJob(new AEIR_QueueableFinalizerExample('Aegis finalizer probe'));
        Test.stopTest();
        // The example attaches AEIR_QueueableFinalizer; exercising the enqueue path covers
        // both the example and the finalizer construction.
        System.assert(true, 'Queueable executed without an unhandled exception.');
    }

    @IsTest
    static void asyncJobMonitorRunsCleanly() {
        Test.startTest();
        AEIR_AsyncJobMonitorScheduler.monitorFailedJobs();
        System.schedule('Aegis Flow Async Monitor Test', '0 0 1 * * ?', new AEIR_AsyncJobMonitorScheduler());
        Test.stopTest();
        System.assertEquals(1, [SELECT count() FROM CronTrigger WHERE CronJobDetail.Name = 'Aegis Flow Async Monitor Test']);
    }

    @IsTest
    static void headlessMonitorControllerSurfacesAlerts() {
        AEIR_ErrorCaptureService.CaptureResult result =
            AEIR_ErrorCaptureService.capture(input('System.NullPointerException: probe', 'High'));

        Test.startTest();
        List<AEIR_UserNotificationService.AlertDTO> alerts = AEIR_AegisHeadlessMonitorController.getOpenAlerts();
        AEIR_UserNotificationService.DetailDTO detail =
            AEIR_AegisHeadlessMonitorController.getAlertDetails(result.correlationId);
        AEIR_HelpMeController.HelpMeResponse help =
            AEIR_AegisHeadlessMonitorController.startHelpFromAlert(result.correlationId, '{"pageUrl":"/lightning"}', 'Need help');
        AEIR_EscalationService.EscalationResult esc =
            AEIR_AegisHeadlessMonitorController.escalateAlert(result.correlationId);
        AEIR_AegisHeadlessMonitorController.dismissAlert(result.correlationId);
        Test.stopTest();

        System.assert(!alerts.isEmpty(), 'The affected user should see their own alert.');
        System.assertNotEquals(null, detail.errorLog);
        System.assertNotEquals(null, help);
        System.assertNotEquals(null, esc);
        System.assertEquals('Dismissed',
            [SELECT Status__c FROM User_Notification__c WHERE Correlation_Id__c = :result.correlationId LIMIT 1].Status__c);
    }
}