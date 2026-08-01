System.debug('AEIR smoke test started.');

Account acct = new Account(Name = 'AEIR Smoke Test ' + String.valueOf(Datetime.now().getTime()));
insert acct;

AEIR_ErrorCaptureService.ErrorInput err = new AEIR_ErrorCaptureService.ErrorInput();
err.sourceType = 'Apex Class';
err.sourceName = 'SmokeTest';
err.objectApiName = 'Account';
err.recordId = acct.Id;
err.actionName = 'Smoke Test Capture';
err.pageUrl = '/lightning/r/Account/' + acct.Id + '/view';
err.originalMessage = 'REQUIRED_FIELD_MISSING: Required fields are missing: [Tax_Code__c]';
err.contextJson = '{"scenario":"smoke-test","screen":"Account Record Page"}';
AEIR_ErrorCaptureService.CaptureResult capture = AEIR_ErrorCaptureService.capture(err);
System.debug('AEIR Error Log Id: ' + capture.errorLogId + ' correlationId=' + capture.correlationId);

AEIR_AgentforceGatewayService.DiagnosisResult diagnosis = AEIR_AgentforceGatewayService.diagnoseError(capture.errorLogId);
System.debug('AEIR Diagnosis Id: ' + diagnosis.diagnosisId + ' fixability=' + diagnosis.fixability);

AEIR_DiagnosticSessionService.SessionInput sessionInput = new AEIR_DiagnosticSessionService.SessionInput();
sessionInput.contextRecordId = acct.Id;
sessionInput.objectApiName = 'Account';
sessionInput.pageUrl = '/lightning/r/Account/' + acct.Id + '/view';
sessionInput.pageReferenceJson = '{"type":"standard__recordPage","attributes":{"recordId":"' + acct.Id + '","objectApiName":"Account","actionName":"view"}}';
sessionInput.userDescription = 'Smoke test manual Help Me session.';
sessionInput.detectedIssueType = 'Report Issue';
AEIR_DiagnosticSessionService.SessionResult session = AEIR_DiagnosticSessionService.createSession(sessionInput);
System.debug('AEIR Diagnostic Session Id: ' + session.sessionId);

AEIR_RemediationOrchestrator.RemediationRequest remediation = new AEIR_RemediationOrchestrator.RemediationRequest();
remediation.correlationId = capture.correlationId;
remediation.actionKey = 'UPDATE_ACCOUNT_DESCRIPTION';
remediation.objectApiName = 'Account';
remediation.recordId = acct.Id;
remediation.fieldApiName = 'Description';
remediation.newValue = 'Updated by AEIR smoke test';
remediation.confirmed = true;
remediation.errorLogId = capture.errorLogId;
AEIR_RemediationOrchestrator.RemediationResult remResult = AEIR_RemediationOrchestrator.execute(remediation);
System.debug('AEIR Remediation Status: ' + remResult.status + ' success=' + remResult.success);

AEIR_EscalationService.EscalationResult escalation = AEIR_EscalationService.createForError(capture.errorLogId, 'DEFAULT_DEV_EMAIL', false);
System.debug('AEIR Escalation Id: ' + escalation.escalationId + ' channel=' + escalation.channel);

Integer errorCount = [SELECT count() FROM Error_Log__c WHERE Id = :capture.errorLogId];
Integer diagnosisCount = [SELECT count() FROM AI_Diagnosis__c WHERE Id = :diagnosis.diagnosisId];
Integer sessionCount = [SELECT count() FROM Diagnostic_Session__c WHERE Id = :session.sessionId];
Integer remediationCount = [SELECT count() FROM Remediation_Action__c WHERE Id = :remResult.remediationActionId];
Integer escalationCount = [SELECT count() FROM Developer_Escalation__c WHERE Id = :escalation.escalationId];

if (errorCount != 1 || diagnosisCount != 1 || sessionCount != 1 || remediationCount != 1 || escalationCount != 1 || remResult.success != true) {
    throw new AuraHandledException('AEIR smoke test failed. Check generated records and debug logs.');
}

System.debug('AEIR SMOKE TEST PASS. Account=' + acct.Id + ' Error=' + capture.errorLogId + ' Session=' + session.sessionId + ' Escalation=' + escalation.escalationId);
