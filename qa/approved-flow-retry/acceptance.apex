// QA-only real Flow proof. Root selects the development org and coordinates execution.
// Requires deployed product + this isolated QA project and the explicit QA permission.
System.assert(FeatureManagement.checkPermission('AEIR_Execute_Retry'));
System.assert(FeatureManagement.checkPermission('AEIR_QA_Flow_Retry'));
String qaCorrelation = 'AEIR-QA-FLOW-' + Datetime.now().getTime();
String qaHandler = 'AEIR_QA_APPROVED_RECOVERY';
Savepoint qaSavepoint = Database.setSavepoint();
Id qaTargetId;
Set<Id> qaAuditIds = new Set<Id>();
try {
    Error_Feedback__c target = new Error_Feedback__c(Comments__c = 'AEIR-QA-RECOVERY:SETUP');
    insert target;
    qaTargetId = target.Id;
    String recoveryKey = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(
        qaHandler.toLowerCase() + '|' + String.valueOf(qaTargetId) + '|' + qaCorrelation.toLowerCase())));
    target.Comments__c = 'AEIR-QA-RECOVERY:PENDING:' + recoveryKey;
    update target;

    AEIR_RetryOrchestrationService.RetryRequest request = new AEIR_RetryOrchestrationService.RetryRequest();
    request.handlerKey = qaHandler; request.targetRecordId = qaTargetId;
    request.correlationId = qaCorrelation; request.attemptNumber = 1;
    AEIR_RetryOrchestrationService.RetryResult first = AEIR_RetryOrchestrationService.requestRetry(request);
    System.assertEquals(true, first.success, first.message);
    qaAuditIds.add(first.retryAttemptId);
    System.assertEquals('AEIR-QA-RECOVERY:DONE:' + recoveryKey,
        [SELECT Comments__c FROM Error_Feedback__c WHERE Id = :qaTargetId].Comments__c,
        'The real Flow must have performed and verified its approved write.');
    AEIR_RetryOrchestrationService.RetryResult duplicate = AEIR_RetryOrchestrationService.requestRetry(request);
    System.assertEquals(true, duplicate.success, duplicate.message);
    System.assertEquals(first.retryAttemptId, duplicate.retryAttemptId);

    // A different retry attempt deliberately invokes the real Flow again: its own
    // idempotency branch must recognize the same stored result without another effect.
    request.attemptNumber = 2;
    AEIR_RetryOrchestrationService.RetryResult repeated = AEIR_RetryOrchestrationService.requestRetry(request);
    System.assertEquals(true, repeated.success, repeated.message);
    System.assertNotEquals(first.retryAttemptId, repeated.retryAttemptId);
    qaAuditIds.add(repeated.retryAttemptId);
    System.assertEquals('AEIR-QA-RECOVERY:DONE:' + recoveryKey,
        [SELECT Comments__c FROM Error_Feedback__c WHERE Id = :qaTargetId].Comments__c);

    // A real accessible record without the marker must never be changed by this fixture.
    target.Comments__c = 'AEIR-QA-RECOVERY:UNAPPROVED';
    update target;
    request.attemptNumber = 3;
    AEIR_RetryOrchestrationService.RetryResult rejected = AEIR_RetryOrchestrationService.requestRetry(request);
    System.assertEquals(false, rejected.success);
    qaAuditIds.add(rejected.retryAttemptId);
    System.assertEquals('AEIR-QA-RECOVERY:UNAPPROVED',
        [SELECT Comments__c FROM Error_Feedback__c WHERE Id = :qaTargetId].Comments__c);
    System.assertEquals(2, [SELECT count() FROM Retry_Attempt__c WHERE Id IN :qaAuditIds AND Status__c = 'Succeeded']);
    System.assertEquals(1, [SELECT count() FROM Retry_Attempt__c WHERE Id IN :qaAuditIds AND Status__c = 'Failed']);
    System.assertEquals(0, Limits.getCallouts());
    System.assertEquals(0, Limits.getEmailInvocations());
} finally {
    Database.rollback(qaSavepoint);
    Database.releaseSavepoint(qaSavepoint);
}
System.assertEquals(0, [SELECT count() FROM Error_Feedback__c WHERE Id = :qaTargetId]);
System.assertEquals(0, [SELECT count() FROM Retry_Attempt__c WHERE Id IN :qaAuditIds]);
System.debug(LoggingLevel.INFO, 'AEIR_QA_REAL_FLOW_RESULT=' + JSON.serialize(new Map<String, Object>{
    'correlation' => qaCorrelation, 'realFlowWrite' => 'PASS', 'serviceDedupe' => 'PASS',
    'flowIdempotency' => 'PASS', 'unapprovedMarker' => 'DENIED', 'cleanup' => 'ROLLED_BACK'
}));
