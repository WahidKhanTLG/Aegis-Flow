@IsTest
public class AEIR_CoreTest {
    @TestSetup
    static void authorizeRetryFixture() {
        AEIR_CaptureRetryBulkTest.createAuthorizedRetryUser('Core');
        createEventProcessorFixtures('Core');
    }

    /** Native configured processor and readable-but-unprivileged control user. */
    public static void createEventProcessorFixtures(String label) {
        Id standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id;
        List<User> actors = new List<User>();
        for (String suffix : new List<String>{'Processor', 'Denied'}) {
            actors.add(new User(Alias = suffix == 'Processor' ? 'aegproc' : 'aegdeny',
                LastName = 'AegisEvent' + suffix + label, ProfileId = standardProfile,
                Email = 'aegis-event-' + suffix.toLowerCase() + '@example.invalid',
                Username = 'aegis.' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)) + '@example.invalid',
                TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'));
        }
        insert actors;
        Id processing = [SELECT Id FROM CustomPermission
            WHERE DeveloperName = 'AEIR_Process_Diagnostics' LIMIT 1].Id;
        PermissionSet capability = new PermissionSet(Name = 'AEIR_Event_Processor_Test_' + label,
            Label = 'Aegis Event Processor Test ' + label);
        PermissionSet reader = new PermissionSet(Name = 'AEIR_Event_Reader_Test_' + label,
            Label = 'Aegis Event Reader Test ' + label);
        insert new List<PermissionSet>{capability, reader};
        insert new SetupEntityAccess(ParentId = capability.Id, SetupEntityId = processing);
        // Materialize the source-defined evidence access because check-only validation
        // can retain an existing permission set's previous native permission cache.
        List<ObjectPermissions> objectGrants = new List<ObjectPermissions>();
        for (String objectName : new List<String>{'Error_Log__c', 'Diagnostic_Session__c', 'AI_Diagnosis__c'}) {
            objectGrants.add(new ObjectPermissions(ParentId = capability.Id, SObjectType = objectName,
                PermissionsRead = true, PermissionsViewAllRecords = true, PermissionsModifyAllRecords = false));
        }
        objectGrants.add(new ObjectPermissions(ParentId = reader.Id, SObjectType = 'Error_Log__c',
            PermissionsRead = true, PermissionsViewAllRecords = true, PermissionsModifyAllRecords = false));
        insert objectGrants;
        insert new FieldPermissions(ParentId = reader.Id, SObjectType = 'Error_Log__c',
            Field = 'Error_Log__c.User__c', PermissionsRead = true, PermissionsEdit = false);
        Id runtimeRole = [SELECT Id FROM PermissionSet WHERE Name = 'AEIR_Integration_User' LIMIT 1].Id;
        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(AssigneeId = actors[0].Id, PermissionSetId = capability.Id),
            new PermissionSetAssignment(AssigneeId = actors[0].Id, PermissionSetId = runtimeRole),
            new PermissionSetAssignment(AssigneeId = actors[1].Id, PermissionSetId = reader.Id)
        };
    }

    public static User eventActor(String label, Boolean processor) {
        String actorName = 'AegisEvent' + (processor ? 'Processor' : 'Denied') + label;
        return [SELECT Id FROM User WHERE LastName = :actorName LIMIT 1];
    }

    /** Characterize the actual test transport principal, without changing its access. */
    public static Boolean eventSubscriberAuthorized(Id errorId) {
        User subscriber = [SELECT Id FROM User WHERE Alias = 'autoproc' LIMIT 1];
        Boolean allowed = false;
        System.runAs(subscriber) {
            try {
                allowed = AEIR_AgentforceGatewayService.authorizedErrors(new List<Id>{errorId}).contains(errorId);
            } catch (Exception denied) {
                // A permission denial must produce the same fail-closed transport result.
                allowed = false;
            }
        }
        return allowed;
    }

    public static void assertSubscriberRejection(Id errorId, String correlationId) {
        System.assertEquals(0, [SELECT count() FROM AI_Diagnosis__c WHERE Error_Log__c = :errorId],
            'An unauthorized platform event principal must not create a diagnosis.');
        Id subscriberId = [SELECT Id FROM User WHERE Alias = 'autoproc' LIMIT 1].Id;
        List<Delivery_Attempt__c> failures = [SELECT CreatedById, Response_Body__c
            FROM Delivery_Attempt__c WHERE Correlation_Id__c = :correlationId AND Status__c = 'Failed'
                AND Idempotency_Key__c LIKE 'AgentDiagnosisRequested:%' ORDER BY CreatedDate];
        System.assert(!failures.isEmpty(), 'A rejected request must leave subscriber failure telemetry.');
        for (Delivery_Attempt__c failure : failures) {
            System.assertEquals(subscriberId, failure.CreatedById, 'Exercise the real event transport principal.');
            System.assert(String.isNotBlank(failure.Response_Body__c), 'The rejection must remain observable.');
            System.assert(!failure.Response_Body__c.contains('EVENT-DO-NOT-LOG'), 'Failure telemetry must exclude secret values.');
        }
    }

    @IsTest static void captureDiagnoseEscalate() {
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.sourceType = 'Apex Class';
        input.sourceName = 'UnitTest';
        input.originalMessage = 'REQUIRED_FIELD_MISSING: Required fields are missing: [Name]';
        input.contextJson = '{"field":"Name"}';
        Test.startTest();
        AEIR_ErrorCaptureService.CaptureResult cr = AEIR_ErrorCaptureService.capture(input);
        AEIR_AgentforceGatewayService.DiagnosisResult dr = AEIR_AgentforceGatewayService.diagnoseError(cr.errorLogId);
        AEIR_EscalationService.EscalationResult er = AEIR_EscalationService.createForError(cr.errorLogId, 'DEFAULT_DEV_EMAIL', false);
        Test.stopTest();
        System.assertNotEquals(null, cr.errorLogId);
        System.assertEquals('Missing Data', cr.category);
        System.assertNotEquals(null, dr.diagnosisId);
        System.assertNotEquals(null, er.escalationId);
    }
    @IsTest static void diagnosticSessionManual() {
        AEIR_DiagnosticSessionService.SessionInput input = new AEIR_DiagnosticSessionService.SessionInput();
        input.objectApiName = 'Account'; input.pageUrl = '/lightning/o/Account/list'; input.userDescription = 'I need help.'; input.detectedIssueType = 'Navigation Help';
        Test.startTest();
        AEIR_DiagnosticSessionService.SessionResult sr = AEIR_DiagnosticSessionService.createSession(input);
        AEIR_AgentforceGatewayService.DiagnosisResult dr = AEIR_AgentforceGatewayService.diagnoseSession(sr.sessionId);
        AEIR_EscalationService.EscalationResult er = AEIR_EscalationService.createForSession(sr.sessionId, 'DEFAULT_DEV_EMAIL', false);
        Test.stopTest();
        System.assertNotEquals(null, sr.sessionId);
        System.assertEquals('UNKNOWN', dr.fixability);
        System.assertNotEquals(null, er.escalationId);
    }
    @IsTest static void remediationAndRetry() {
        // Governed remediation ships disabled (spec sections 2 and 18); this test exercises it deliberately.
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
        Account a = new Account(Name='AEIR Test Account'); insert a;
        AEIR_RemediationOrchestrator.RemediationRequest req = new AEIR_RemediationOrchestrator.RemediationRequest();
        req.correlationId = AEIR_CorrelationIdService.nextId(); req.actionKey='UPDATE_ACCOUNT_DESCRIPTION'; req.objectApiName='Account'; req.recordId=a.Id; req.fieldApiName='Description'; req.newValue='Updated by AEIR test'; req.confirmed=true;
        Test.startTest();
        AEIR_RemediationOrchestrator.RemediationResult rr = AEIR_RemediationOrchestrator.execute(req);
        AEIR_CaptureRetryBulkTest.useUpdatingHandler('ORDER_TAX_RECALCULATION');
        AEIR_RetryOrchestrationService.RetryRequest retry = new AEIR_RetryOrchestrationService.RetryRequest(); retry.handlerKey='ORDER_TAX_RECALCULATION'; retry.targetRecordId=a.Id; retry.attemptNumber=1; retry.correlationId=req.correlationId;
        AEIR_RetryOrchestrationService.RetryResult retryResult;
        User retryActor = [SELECT Id FROM User WHERE LastName = 'AegisRetryAuthorizedCore' LIMIT 1];
        System.runAs(retryActor) {
            System.assert(FeatureManagement.checkPermission('AEIR_Execute_Retry'), 'The dedicated retry fixture must have its native custom permission.');
            retryResult = AEIR_RetryOrchestrationService.requestRetry(retry);
        }
        Test.stopTest();
        System.assertEquals(true, rr.success);
        System.assertEquals(true, retryResult.success, retryResult.message);
        System.assertEquals('Retried ' + req.correlationId, [SELECT Description FROM Account WHERE Id = :a.Id].Description);
    }
    @IsTest static void sanitizerMasksSecrets() {
        String masked = AEIR_SecuritySanitizerService.mask('password=hello token=abc123 Authorization: Bearer xyz');
        System.assert(masked.contains('[MASKED]'));
    }
    @IsTest static void platformEventDeliveryRespectsRuntimeAuthorization() {
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.sourceType = 'Apex Class';
        input.sourceName = 'EventHandlerTest';
        input.originalMessage = 'UNABLE_TO_LOCK_ROW: password=EVENT-DO-NOT-LOG unable to obtain exclusive access';
        AEIR_ErrorCaptureService.CaptureResult cr = AEIR_ErrorCaptureService.capture(input);

        Diagnostic_Session_Requested__e dsEvt = new Diagnostic_Session_Requested__e(
            Correlation_Id__c = AEIR_CorrelationIdService.nextId(),
            User_Id__c = UserInfo.getUserId(),
            Page_Reference_JSON__c = '{"pageUrl":"/lightning/o/Account/list","objectApiName":"Account"}',
            User_Description__c = 'Manual event-created diagnostic session.'
        );
        Agent_Diagnosis_Requested__e diagEvt = new Agent_Diagnosis_Requested__e(
            Correlation_Id__c = cr.correlationId,
            Error_Log_Id__c = String.valueOf(cr.errorLogId)
        );
        Escalation_Requested__e escEvt = new Escalation_Requested__e(
            Correlation_Id__c = cr.correlationId,
            Error_Log_Id__c = String.valueOf(cr.errorLogId),
            Route_Key__c = 'DEFAULT_DEV_EMAIL'
        );

        Test.startTest();
        Boolean subscriberAuthorized = eventSubscriberAuthorized(cr.errorLogId);
        EventBus.publish(dsEvt);
        EventBus.publish(diagEvt);
        EventBus.publish(escEvt);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assert([SELECT count() FROM Diagnostic_Session__c WHERE Correlation_Id__c = :dsEvt.Correlation_Id__c] > 0);
        List<AI_Diagnosis__c> diagnoses = [SELECT Id, CreatedById, OwnerId FROM AI_Diagnosis__c WHERE Error_Log__c = :cr.errorLogId];
        if (subscriberAuthorized) {
            System.assert(!diagnoses.isEmpty(), 'An authorized transport principal must create a diagnosis.');
            Id subscriberId = [SELECT Id FROM User WHERE Alias = 'autoproc' LIMIT 1].Id;
            System.assertEquals(subscriberId, diagnoses[0].CreatedById, 'Exercise real event delivery under its default principal.');
            System.assertEquals(UserInfo.getUserId(), diagnoses[0].OwnerId, 'The affected user retains access to the diagnosis.');
        } else {
            assertSubscriberRejection(cr.errorLogId, cr.correlationId);
        }
        System.assert([SELECT count() FROM Developer_Escalation__c WHERE Error_Log__c = :cr.errorLogId] > 0);
    }

    @IsTest static void configuredProcessorHandlesDiagnosisRequests() {
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AI_DIAGNOSIS, false);
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.sourceType = 'Apex Class'; input.sourceName = 'ConfiguredEventProcessor';
        input.originalMessage = 'REQUIRED_FIELD_MISSING: AccountId is required.';
        AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(input);
        User processor = eventActor('Core', true);
        Test.startTest();
        System.runAs(processor) {
            System.assert(FeatureManagement.checkPermission('AEIR_Process_Diagnostics'), 'Use the native runtime capability.');
            System.assert(!FeatureManagement.checkPermission('AEIR_View_Sensitive_Context'), 'Processing does not require sensitive export.');
            System.assert(AEIR_AgentforceGatewayService.authorizedErrors(new List<Id>{captured.errorLogId}).contains(captured.errorLogId));
            AEIR_AgentDiagnosisRequestedEventHandler.handle(new List<Agent_Diagnosis_Requested__e>{
                new Agent_Diagnosis_Requested__e(Correlation_Id__c = captured.correlationId,
                    Error_Log_Id__c = String.valueOf(captured.errorLogId))
            });
        }
        Test.stopTest();
        AI_Diagnosis__c diagnosis = [SELECT CreatedById, OwnerId FROM AI_Diagnosis__c WHERE Error_Log__c = :captured.errorLogId];
        System.assertEquals(processor.Id, diagnosis.CreatedById);
        System.assertEquals(UserInfo.getUserId(), diagnosis.OwnerId, 'The affected user retains diagnosis ownership.');
        System.assertEquals('Diagnosed', [SELECT Status__c FROM Error_Log__c WHERE Id = :captured.errorLogId].Status__c);
    }

    @IsTest static void readableEvidenceDoesNotAuthorizeDiagnosisProcessing() {
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AI_DIAGNOSIS, false);
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.sourceType = 'Apex Class'; input.sourceName = 'UnprivilegedEventProcessor';
        input.originalMessage = 'REQUIRED_FIELD_MISSING: password=EVENT-DO-NOT-LOG AccountId is required.';
        AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(input);
        User denied = eventActor('Core', false);
        Test.startTest();
        System.runAs(denied) {
            System.assert(!FeatureManagement.checkPermission('AEIR_Process_Diagnostics'));
            System.assert(!FeatureManagement.checkPermission('AEIR_View_Sensitive_Context'));
            System.assertEquals(1, [SELECT count() FROM Error_Log__c WHERE Id = :captured.errorLogId WITH USER_MODE],
                'Record visibility alone must not confer processing authority.');
            System.assertEquals(0, AEIR_AgentforceGatewayService.authorizedErrors(new List<Id>{captured.errorLogId}).size());
            AEIR_AgentDiagnosisRequestedEventHandler.handle(new List<Agent_Diagnosis_Requested__e>{
                new Agent_Diagnosis_Requested__e(Correlation_Id__c = captured.correlationId,
                    Error_Log_Id__c = String.valueOf(captured.errorLogId))
            });
        }
        Test.stopTest();
        System.assertEquals(0, [SELECT count() FROM AI_Diagnosis__c WHERE Error_Log__c = :captured.errorLogId]);
        System.assertEquals('New', [SELECT Status__c FROM Error_Log__c WHERE Id = :captured.errorLogId].Status__c);
    }

    @IsTest static void actionAndControllerCoverage() {
        // Governed remediation ships disabled (spec sections 2 and 18); this test exercises it deliberately.
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
        Account a = new Account(Name = 'AEIR Controller Coverage');
        insert a;

        AEIR_CaptureFlowFaultAction.Request flowReq = new AEIR_CaptureFlowFaultAction.Request();
        flowReq.varFlowApiName = 'AEIR_Test_Flow';
        flowReq.varFailedElement = 'Get Account';
        flowReq.varErrorMessage = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: sample validation error';
        flowReq.varObjectApiName = 'Account';
        flowReq.varRecordId = a.Id;
        flowReq.varUserAction = 'Save';
        flowReq.varPageUrl = '/lightning/r/Account/' + a.Id + '/view';

        Test.startTest();
        List<AEIR_CaptureFlowFaultAction.Response> flowRes = AEIR_CaptureFlowFaultAction.captureFlowFault(new List<AEIR_CaptureFlowFaultAction.Request>{ flowReq });
        Id errorLogId = flowRes[0].errorLogId;

        AEIR_InvokeDiagnosisAction.Request diagReq = new AEIR_InvokeDiagnosisAction.Request();
        diagReq.errorLogId = errorLogId;
        List<AEIR_InvokeDiagnosisAction.Response> diagRes = AEIR_InvokeDiagnosisAction.invokeDiagnosis(new List<AEIR_InvokeDiagnosisAction.Request>{ diagReq });

        AEIR_CreateEscalationAction.Request escReq = new AEIR_CreateEscalationAction.Request();
        escReq.errorLogId = errorLogId;
        escReq.routeKey = 'DEFAULT_DEV_EMAIL';
        escReq.sendEmailNow = false;
        List<AEIR_CreateEscalationAction.Response> escRes = AEIR_CreateEscalationAction.createEscalation(new List<AEIR_CreateEscalationAction.Request>{ escReq });

        AEIR_ExecuteRemediationAction.Request remReq = new AEIR_ExecuteRemediationAction.Request();
        remReq.correlationId = flowRes[0].correlationId;
        remReq.actionKey = 'UPDATE_ACCOUNT_DESCRIPTION';
        remReq.objectApiName = 'Account';
        remReq.recordId = a.Id;
        remReq.fieldApiName = 'Description';
        remReq.newValue = 'Updated through invocable action test';
        remReq.confirmed = true;
        List<AEIR_ExecuteRemediationAction.Response> remRes = AEIR_ExecuteRemediationAction.executeRemediation(new List<AEIR_ExecuteRemediationAction.Request>{ remReq });

        AEIR_ClientErrorController.reportClientError(null, 'Coverage LWC', 'Client error', 'Stack', '/lightning/page', 'Unit Test');
        AEIR_LogCollectorService.collectForError(errorLogId);
        AEIR_AdminConsoleController.getMetrics();
        AEIR_AdminConsoleController.getRecentErrors(null, null, 10);
        AEIR_AdminConsoleController.getRecentEscalations(10);
        AEIR_RetentionScheduler.purge();
        System.enqueueJob(new AEIR_QueueableFinalizerExample(null));
        Test.stopTest();

        System.assertNotEquals(null, flowRes[0].errorLogId);
        System.assertNotEquals(null, diagRes[0].diagnosisId);
        System.assertNotEquals(null, escRes[0].escalationId);
        System.assertEquals(true, remRes[0].success);
    }

    @IsTest static void helpMeAndEventCoverage() {
        Account a = new Account(Name = 'AEIR HelpMe Coverage');
        insert a;
        String ctx = '{"pageUrl":"/lightning/r/Account/' + a.Id + '/view","objectApiName":"Account","recordId":"' + a.Id + '"}';

        Test.startTest();
        AEIR_HelpMeController.HelpMeResponse help = AEIR_HelpMeController.createSession(ctx, 'I was trying to save the account.', 'Save Error');
        AEIR_HelpMeController.diagnoseSession(help.sessionId);
        AEIR_HelpMeController.getRecentErrors(a.Id, 'Account');
        AEIR_HelpMeController.escalateSession(help.sessionId, 'Escalate from test.');

        Error_Captured__e errEvt = new Error_Captured__e(
            Correlation_Id__c = AEIR_CorrelationIdService.nextId(),
            Source_Type__c = 'API',
            Source_Name__c = 'Unit Event',
            Error_Message__c = 'MIXED_DML_OPERATION: sample mixed DML',
            Object_API_Name__c = 'Account',
            Record_Id__c = a.Id,
            User_Id__c = UserInfo.getUserId(),
            Context_JSON__c = '{}',
            Severity__c = 'High'
        );
        EventBus.publish(errEvt);
        Test.getEventBus().deliver();

        AEIR_BatchApexErrorEventHandler.handle(new List<BatchApexErrorEvent>());
        Test.stopTest();

        System.assertNotEquals(null, help.sessionId);
        System.assert([SELECT count() FROM Error_Log__c WHERE Source_Name__c = 'Unit Event'] > 0);
    }

}
