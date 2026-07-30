/**
 * AF-26: proves a non-admin end user can actually complete the product journey.
 *
 * Everything here runs as a Standard User holding only AEIR_End_User. Before this test
 * the permission set granted no application visibility, so an end user could not open
 * the app hosting the utility bar and never saw an alert at all.
 */
@IsTest
private class AEIR_EndUserJourneyTest {

    private static User endUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            FirstName = 'Aegis', LastName = 'EndUser', Alias = 'aeu',
            Email = 'aegis.enduser@example.com',
            Username = 'aegis.enduser.' + Datetime.now().getTime() + '@example.invalid',
            ProfileId = p.Id, TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
    }

    @TestSetup
    static void setup() {
        User u = endUser();
        insert u;
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'AEIR_End_User' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
    }

    @IsTest
    static void endUserCanCompleteTheFullJourney() {
        User u = [SELECT Id FROM User WHERE LastName = 'EndUser' LIMIT 1];

        Test.startTest();
        System.runAs(u) {
            // 1. A failure is captured in the end user's own context.
            AEIR_ErrorCaptureService.ErrorInput in1 = new AEIR_ErrorCaptureService.ErrorInput();
            in1.sourceType = 'Flow';
            in1.sourceName = 'Order_Tax_Update_Flow';
            in1.objectApiName = 'Account';
            in1.originalMessage = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: Tax Code is required.';
            in1.severity = 'High';
            AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(in1);
            System.assertEquals(true, captured.success, 'An end user must be able to capture: ' + captured.message);

            // 2. The utility bar surfaces it to them.
            System.assertNotEquals(null, AEIR_AegisHeadlessMonitorController.getSurfaceSettings());
            System.assert(AEIR_AegisHeadlessMonitorController.getAlertChannel().startsWith('/event/'));
            List<AEIR_UserNotificationService.AlertDTO> alerts =
                AEIR_AegisHeadlessMonitorController.getOpenAlerts();
            System.assert(!alerts.isEmpty(), 'The affected end user must see their own alert.');

            // 3. They can open the details.
            AEIR_UserNotificationService.DetailDTO detail =
                AEIR_AegisHeadlessMonitorController.getAlertDetails(captured.correlationId);
            System.assertNotEquals(null, detail.errorLog, 'Details must be retrievable by the affected user.');

            // 4. Get Help creates a diagnostic session.
            AEIR_HelpMeController.HelpMeResponse help =
                AEIR_AegisHeadlessMonitorController.startHelpFromAlert(
                    captured.correlationId, '{"pageUrl":"/lightning/r/Account/view"}', 'I could not save the account.');
            System.assertNotEquals(null, help, 'Get Help must work for an end user.');

            // 5. They can give feedback (spec 7.4).
            AEIR_FeedbackService.FeedbackInput fb = new AEIR_FeedbackService.FeedbackInput();
            fb.errorLogId = captured.errorLogId;
            fb.helpful = true;
            fb.comments = 'This told me exactly what to fix.';
            System.assertNotEquals(null, AEIR_FeedbackService.submitFeedback(fb));

            // 6. They can escalate and then dismiss.
            System.assertNotEquals(null, AEIR_AegisHeadlessMonitorController.escalateAlert(captured.correlationId));
            AEIR_AegisHeadlessMonitorController.dismissAlert(captured.correlationId);
            System.assertEquals('Dismissed',
                [SELECT Status__c FROM User_Notification__c WHERE Correlation_Id__c = :captured.correlationId LIMIT 1].Status__c);
        }
        Test.stopTest();
    }

    @IsTest
    static void endUserCannotExecuteRemediation() {
        User u = [SELECT Id FROM User WHERE LastName = 'EndUser' LIMIT 1];
        Account a = new Account(Name = 'Aegis End User Guard');
        insert a;

        Test.startTest();
        AEIR_RemediationOrchestrator.RemediationResult res;
        System.runAs(u) {
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
            AEIR_RemediationOrchestrator.RemediationRequest req = new AEIR_RemediationOrchestrator.RemediationRequest();
            req.actionKey = 'UPDATE_ACCOUNT_DESCRIPTION';
            req.objectApiName = 'Account';
            req.recordId = a.Id;
            req.fieldApiName = 'Description';
            req.newValue = 'end user should not be able to do this';
            req.confirmed = true;
            res = AEIR_RemediationOrchestrator.execute(req);
        }
        Test.stopTest();

        System.assertEquals(false, res.success,
            'AEIR_End_User must not carry the Aegis Execute Remediation permission.');
        System.assertEquals(null, [SELECT Description FROM Account WHERE Id = :a.Id].Description);
    }
}