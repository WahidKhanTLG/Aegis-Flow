// STAGED ONLY: root coordinates target-org authorization and execution.
// Runs synchronous application acceptance; always rolls back synthetic records.
// Does not prove committed event delivery, a customer's business rule or a real provider.
// No escalation, email, HTTP or external delivery is requested by this script.
System.assertEquals(false, AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.AI_DIAGNOSIS),
    'Disable AI_DIAGNOSIS before this rollback-only acceptance: remote enrichment is outside this harness.');
System.assertEquals(false, AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.CONNECTOR_EXTENSIONS),
    'Keep external connector delivery disabled during isolated application acceptance.');
// Avoid an uninterrupted 13-digit timestamp: the payment/identifier masking
// policy deliberately redacts those even in otherwise non-sensitive values.
String acceptanceRun = 'AEIR-ACCEPT-' + Datetime.now().formatGMT('yyyy-MM-dd_HH:mm:ss.SSS');
Savepoint acceptanceSavepoint = Database.setSavepoint();
Set<Id> acceptanceRecordIds = new Set<Id>();
Set<Id> acceptanceLogIds = new Set<Id>();
Set<Id> acceptanceDiagnosisIds = new Set<Id>();
Map<String, Object> acceptanceReport = new Map<String, Object>{
    'run' => acceptanceRun,
    'scope' => 'Synchronous synthetic diagnostics; rollback cleanup; no remote connectivity assertion'
};
try {
    Account salesRecord = new Account(Name = acceptanceRun + ' Sales');
    Case serviceRecord = new Case(Subject = acceptanceRun + ' Service');
    Error_Feedback__c customRecord = new Error_Feedback__c(Comments__c = acceptanceRun + ' Custom');
    insert salesRecord;
    insert serviceRecord;
    insert customRecord;
    acceptanceRecordIds.add(salesRecord.Id);
    acceptanceRecordIds.add(serviceRecord.Id);
    acceptanceRecordIds.add(customRecord.Id);

    // These are deliberately supplied diagnostic samples, not invented customer
    // tax/order rules and not actual requests to an external integration endpoint.
    List<String> areas = new List<String>{'Sales', 'Service', 'Custom', 'Integration'};
    List<String> objectNames = new List<String>{'Account', 'Case',
        Error_Feedback__c.SObjectType.getDescribe().getName(), 'Account'};
    List<Id> targets = new List<Id>{salesRecord.Id, serviceRecord.Id, customRecord.Id, salesRecord.Id};
    List<String> sources = new List<String>{'Flow', 'LWC', 'Apex Class', 'API'};
    List<String> messages = new List<String>{
        'REQUIRED_FIELD_MISSING: synthetic sales diagnostic sample',
        'DUPLICATES_DETECTED: synthetic service diagnostic sample',
        'Too many SOQL queries: synthetic custom-object diagnostic sample',
        'HTTP 503: synthetic unavailable upstream diagnostic sample'
    };
    List<String> expectedCategories = new List<String>{'Missing Data', 'Validation Rule', 'Governor Limit', 'Integration'};
    List<AEIR_ErrorCaptureService.ErrorInput> inputs = new List<AEIR_ErrorCaptureService.ErrorInput>();
    for (Integer i = 0; i < areas.size(); i++) {
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.correlationId = acceptanceRun + '-' + areas[i];
        input.sourceType = sources[i];
        input.sourceName = acceptanceRun;
        input.objectApiName = objectNames[i];
        input.recordId = String.valueOf(targets[i]);
        input.originalMessage = messages[i];
        input.severity = 'Critical';
        input.userId = UserInfo.getUserId();
        input.contextJson = JSON.serialize(new Map<String, Object>{
            'acceptanceRun' => acceptanceRun, 'businessArea' => areas[i],
            'password' => 'SYNTHETIC-SECRET-MUST-BE-MASKED'
        });
        inputs.add(input);
    }
    AEIR_ErrorCaptureService.CaptureOptions captureOptions = new AEIR_ErrorCaptureService.CaptureOptions();
    captureOptions.notifyUser = false;
    captureOptions.requestDiagnosis = false;
    List<AEIR_ErrorCaptureService.CaptureResult> captures = AEIR_ErrorCaptureService.captureFromEvents(inputs, captureOptions);
    System.assertEquals(4, captures.size());
    for (Integer i = 0; i < captures.size(); i++) {
        System.assertEquals(true, captures[i].success, areas[i] + ': ' + captures[i].message);
        System.assertEquals(inputs[i].correlationId, captures[i].correlationId);
        System.assertEquals(expectedCategories[i], captures[i].category, areas[i]);
        acceptanceLogIds.add(captures[i].errorLogId);
    }
    List<AEIR_ErrorCaptureService.CaptureResult> duplicates = AEIR_ErrorCaptureService.captureFromEvents(inputs, captureOptions);
    for (Integer i = 0; i < duplicates.size(); i++) {
        System.assertEquals(captures[i].errorLogId, duplicates[i].errorLogId,
            'The same diagnostic must not create another log.');
    }

    Map<Id, AEIR_AgentforceGatewayService.DiagnosisResult> diagnoses =
        AEIR_AgentforceGatewayService.diagnoseErrors(new List<Id>(acceptanceLogIds));
    System.assertEquals(4, diagnoses.size(), 'All four current-user diagnostic records must be authorized.');
    for (AEIR_AgentforceGatewayService.DiagnosisResult diagnosis : diagnoses.values()) {
        System.assertNotEquals(null, diagnosis.diagnosisId);
        System.assert(!String.isBlank(diagnosis.summary));
        System.assert(!String.isBlank(diagnosis.recommendedAction));
        acceptanceDiagnosisIds.add(diagnosis.diagnosisId);
    }
    for (Error_Log__c log : [SELECT Id, User__c, OwnerId, Status__c, Context_JSON__c
            FROM Error_Log__c WHERE Id IN :acceptanceLogIds]) {
        System.assertEquals(UserInfo.getUserId(), log.User__c);
        System.assertEquals(UserInfo.getUserId(), log.OwnerId);
        System.assertEquals('Diagnosed', log.Status__c);
        System.assert(!log.Context_JSON__c.contains('SYNTHETIC-SECRET-MUST-BE-MASKED'));
        System.assert(log.Context_JSON__c.contains(acceptanceRun));
    }
    System.assertEquals(4, [SELECT count() FROM Error_Log__c WHERE Id IN :acceptanceLogIds]);
    System.assertEquals(4, [SELECT count() FROM AI_Diagnosis__c WHERE Id IN :acceptanceDiagnosisIds]);
    System.assertEquals(0, Limits.getCallouts(), 'This harness must not make external requests.');
    System.assertEquals(0, Limits.getEmailInvocations(), 'This harness must not send email.');
    acceptanceReport.put('businessAreas', areas);
    acceptanceReport.put('captures', acceptanceLogIds.size());
    acceptanceReport.put('diagnoses', acceptanceDiagnosisIds.size());
    acceptanceReport.put('synchronousAssertions', 'PASS');
} finally {
    // This discards PublishAfterCommit diagnosis/user-alert hints and transaction-owned
    // queued work. Capture options suppress capture follow-up; captureFromEvents does
    // not publish the immediate, rollback-safe Error_Captured__e ingress event.
    Database.rollback(acceptanceSavepoint);
    Database.releaseSavepoint(acceptanceSavepoint);
}
System.assertEquals(0, [SELECT count() FROM Account WHERE Id IN :acceptanceRecordIds]);
System.assertEquals(0, [SELECT count() FROM Case WHERE Id IN :acceptanceRecordIds]);
System.assertEquals(0, [SELECT count() FROM Error_Feedback__c WHERE Id IN :acceptanceRecordIds]);
System.assertEquals(0, [SELECT count() FROM Error_Log__c WHERE Id IN :acceptanceLogIds]);
System.assertEquals(0, [SELECT count() FROM AI_Diagnosis__c WHERE Id IN :acceptanceDiagnosisIds]);
acceptanceReport.put('cleanup', 'PASS: synthetic records rolled back');
System.debug(LoggingLevel.INFO, 'AEIR_ACCEPTANCE_RESULT=' + JSON.serialize(acceptanceReport));
