@IsTest
private class AEIR_SecurityBoundaryTest {
    private static User newUser(String label) {
        Profile profile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String suffix = String.valueOf(Datetime.now().getTime()) + label;
        return new User(
            FirstName = 'Aegis',
            LastName = label,
            Alias = ('ae' + label).substring(0, Math.min(8, 2 + label.length())),
            Email = 'aegis.' + label + '@example.invalid',
            Username = 'aegis.' + suffix + '@example.invalid',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    private static void grantEndUserAccess(List<User> users) {
        PermissionSet permissionSet = [
            SELECT Id FROM PermissionSet WHERE Name = 'AEIR_End_User' LIMIT 1
        ];
        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (User userRecord : users) {
            assignments.add(new PermissionSetAssignment(
                AssigneeId = userRecord.Id, PermissionSetId = permissionSet.Id));
        }
        insert assignments;
    }

    @IsTest
    static void auraCaptureAlwaysUsesTheRunningUser() {
        User caller = newUser('AuraCaller');
        User spoofedUser = newUser('AuraTarget');
        insert new List<User>{ caller, spoofedUser };
        grantEndUserAccess(new List<User>{ caller, spoofedUser });

        AEIR_ErrorCaptureService.CaptureResult result;
        System.runAs(caller) {
            AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
            input.sourceType = 'LWC';
            input.sourceName = 'Security Boundary Test';
            input.originalMessage = 'A client-side validation failed.';
            input.userId = spoofedUser.Id;
            result = AEIR_ErrorCaptureService.captureFromJson(JSON.serialize(input));
        }

        Error_Log__c captured = [SELECT User__c, OwnerId FROM Error_Log__c WHERE Id = :result.errorLogId];
        System.assertEquals(caller.Id, captured.User__c,
            'Aura input must not be able to choose a different affected user.');
        System.assertEquals(caller.Id, captured.OwnerId,
            'The log owner must remain the user who initiated the browser request.');
    }

    @IsTest
    static void realTimeFlowCaptureDoesNotTrustPayloadUserId() {
        User caller = newUser('FlowCaller');
        User spoofedUser = newUser('FlowTarget');
        insert new List<User>{ caller, spoofedUser };
        grantEndUserAccess(new List<User>{ caller, spoofedUser });

        String correlationId;
        System.runAs(caller) {
            correlationId = AEIR_AegisHeadlessMonitorController.captureFlowError(JSON.serialize(
                new Map<String, Object>{
                    'InterviewGuid' => 'security-boundary-flow-guid',
                    'FlowApiName' => 'Security_Boundary_Flow',
                    'ElementApiName' => 'Update_Records',
                    'ErrorMessage' => 'REQUIRED_FIELD_MISSING: Name',
                    'UserId' => spoofedUser.Id
                }
            ));
        }

        Error_Log__c captured = [SELECT User__c, OwnerId FROM Error_Log__c WHERE Correlation_Id__c = :correlationId];
        System.assertEquals(caller.Id, captured.User__c,
            'EMP payload fields must not be able to attribute a Flow failure to another user.');
        System.assertEquals(caller.Id, captured.OwnerId);
    }

    @IsTest
    static void unprivilegedDiagnosticsNeverContainTechnicalEvidence() {
        User caller = newUser('LimitedViewer');
        insert caller;
        grantEndUserAccess(new List<User>{ caller });

        System.runAs(caller) {
            AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
            input.sourceType = 'Flow';
            input.sourceName = 'Security_Boundary_Flow';
            input.originalMessage = 'TECHNICAL-ERROR-DO-NOT-EXPOSE';
            input.stackTrace = 'STACK-TRACE-DO-NOT-EXPOSE';
            input.contextJson = '{"diagnosticDetail":"CONTEXT-DO-NOT-EXPOSE"}';
            AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(input);

            AEIR_UserNotificationService.DetailDTO detail =
                AEIR_UserNotificationService.getAlertDetails(captured.correlationId);
            String detailJson = JSON.serialize(detail);
            System.assertNotEquals(null, detail.errorLog, 'The affected user still receives a useful diagnostic summary.');
            System.assert(!detailJson.contains('TECHNICAL-ERROR-DO-NOT-EXPOSE'));
            System.assert(!detailJson.contains('STACK-TRACE-DO-NOT-EXPOSE'));
            System.assert(!detailJson.contains('CONTEXT-DO-NOT-EXPOSE'));

            AEIR_GetErrorContextAction.Request request = new AEIR_GetErrorContextAction.Request();
            request.errorLogId = captured.errorLogId;
            AEIR_GetErrorContextAction.Response response =
                AEIR_GetErrorContextAction.run(new List<AEIR_GetErrorContextAction.Request>{ request })[0];
            System.assertEquals('Limited diagnostic context returned.', response.message);
            System.assert(!response.contextJson.contains('TECHNICAL-ERROR-DO-NOT-EXPOSE'));
            System.assert(!response.contextJson.contains('STACK-TRACE-DO-NOT-EXPOSE'));
            System.assert(!response.contextJson.contains('CONTEXT-DO-NOT-EXPOSE'));
        }
    }
}
