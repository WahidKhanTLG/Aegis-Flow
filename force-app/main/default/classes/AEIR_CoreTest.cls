@IsTest
private class AEIR_CoreTest {
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
        AEIR_RetryOrchestrationService.RetryRequest retry = new AEIR_RetryOrchestrationService.RetryRequest(); retry.handlerKey='ORDER_TAX_RECALCULATION'; retry.targetRecordId=a.Id; retry.attemptNumber=1; retry.correlationId=req.correlationId;
        AEIR_RetryOrchestrationService.RetryResult retryResult = AEIR_RetryOrchestrationService.requestRetry(retry);
        Test.stopTest();
        System.assertEquals(true, rr.success);
        System.assertEquals(true, retryResult.success);
    }
    @IsTest static void sanitizerMasksSecrets() {
        String masked = AEIR_SecuritySanitizerService.mask('password=hello token=abc123 Authorization: Bearer xyz');
        System.assert(masked.contains('[MASKED]'));
    }
    @IsTest static void platformEventHandlersDirect() {
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.sourceType = 'Apex Class';
        input.sourceName = 'EventHandlerTest';
        input.originalMessage = 'UNABLE_TO_LOCK_ROW: unable to obtain exclusive access';
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
        EventBus.publish(dsEvt);
        EventBus.publish(diagEvt);
        EventBus.publish(escEvt);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assert([SELECT count() FROM Diagnostic_Session__c WHERE Correlation_Id__c = :dsEvt.Correlation_Id__c] > 0);
        System.assert([SELECT count() FROM AI_Diagnosis__c WHERE Error_Log__c = :cr.errorLogId] > 0);
        System.assert([SELECT count() FROM Developer_Escalation__c WHERE Error_Log__c = :cr.errorLogId] > 0);
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