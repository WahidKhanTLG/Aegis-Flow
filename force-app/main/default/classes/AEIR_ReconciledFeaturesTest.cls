@IsTest
private class AEIR_ReconciledFeaturesTest {
    @IsTest
    static void actionsRestAndAuditCoverage() {
        // Governed remediation ships disabled (spec sections 2 and 18); this test exercises it deliberately.
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
        Account accountRecord = new Account(Name = 'Aegis Flow Reconciled Test');
        insert accountRecord;

        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.sourceType = 'API';
        input.sourceName = 'ReconciledTest';
        input.objectApiName = 'Account';
        input.recordId = accountRecord.Id;
        input.originalMessage = 'REQUIRED_FIELD_MISSING: Tax Code';
        input.contextJson = '{"test":true}';
        AEIR_ErrorCaptureService.CaptureResult captureResult = AEIR_ErrorCaptureService.capture(input);

        AEIR_GetErrorContextAction.Request contextRequest = new AEIR_GetErrorContextAction.Request();
        contextRequest.errorLogId = captureResult.errorLogId;
        AEIR_FindRecentErrorsAction.Request recentRequest = new AEIR_FindRecentErrorsAction.Request();
        recentRequest.recordId = accountRecord.Id;
        recentRequest.objectApiName = 'Account';
        AEIR_GetRecordSnapshotAction.Request snapshotRequest = new AEIR_GetRecordSnapshotAction.Request();
        snapshotRequest.objectApiName = 'Account';
        snapshotRequest.recordId = accountRecord.Id;

        AEIR_UpdateMissingFieldAction.Request remediationRequest = new AEIR_UpdateMissingFieldAction.Request();
        remediationRequest.correlationId = captureResult.correlationId;
        remediationRequest.actionKey = 'UPDATE_ACCOUNT_DESCRIPTION';
        remediationRequest.objectApiName = 'Account';
        remediationRequest.recordId = accountRecord.Id;
        remediationRequest.fieldApiName = 'Description';
        remediationRequest.newValue = 'Updated by reconciled feature test';
        remediationRequest.confirmed = true;

        AEIR_RetryOrchestrationService.RetryRequest retryRequest = new AEIR_RetryOrchestrationService.RetryRequest();
        retryRequest.correlationId = captureResult.correlationId;
        retryRequest.handlerKey = 'ORDER_TAX_RECALCULATION';
        retryRequest.targetRecordId = accountRecord.Id;
        retryRequest.attemptNumber = 1;
        retryRequest.payloadJson = '{}';

        Test.startTest();
        List<AEIR_GetErrorContextAction.Response> contextResponses = AEIR_GetErrorContextAction.run(new List<AEIR_GetErrorContextAction.Request>{ contextRequest });
        List<AEIR_FindRecentErrorsAction.Response> recentResponses = AEIR_FindRecentErrorsAction.run(new List<AEIR_FindRecentErrorsAction.Request>{ recentRequest });
        List<AEIR_GetRecordSnapshotAction.Response> snapshotResponses = AEIR_GetRecordSnapshotAction.run(new List<AEIR_GetRecordSnapshotAction.Request>{ snapshotRequest });
        List<AEIR_UpdateMissingFieldAction.Response> remediationResponses = AEIR_UpdateMissingFieldAction.run(new List<AEIR_UpdateMissingFieldAction.Request>{ remediationRequest });
        List<AEIR_RetryOrchestrationService.RetryResult> retryResponses = AEIR_ExecuteRetryHandlerAction.run(new List<AEIR_RetryOrchestrationService.RetryRequest>{ retryRequest });

        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/aegis-flow/v1/diagnostics';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('{"sourceType":"API","sourceName":"REST Test","originalMessage":"Integration timeout"}');
        RestContext.request = request;
        RestContext.response = new RestResponse();
        AEIR_InboundDiagnosticRestService.postDiagnostic();
        Test.stopTest();

        System.assertEquals(captureResult.correlationId, contextResponses[0].correlationId);
        System.assert(recentResponses[0].resultsJson.contains(captureResult.correlationId));
        System.assert(snapshotResponses[0].snapshotJson.contains('Account.Id'));
        System.assertEquals(true, remediationResponses[0].success);
        System.assertEquals(true, retryResponses[0].success);
        System.assertEquals(1, [SELECT count() FROM Retry_Attempt__c WHERE Idempotency_Key__c = :retryResponses[0].idempotencyKey]);
        System.assertEquals(201, RestContext.response.statusCode);
    }

    @IsTest
    static void eventCaptureIsIdempotent() {
        String correlationId = AEIR_CorrelationIdService.nextId();
        Error_Captured__e firstEvent = new Error_Captured__e(
            Correlation_Id__c = correlationId,
            Source_Type__c = 'Flow',
            Source_Name__c = 'IdempotencyTest',
            Error_Message__c = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: test',
            User_Id__c = UserInfo.getUserId()
        );
        AEIR_ErrorCapturedEventHandler.handle(new List<Error_Captured__e>{ firstEvent, firstEvent });
        System.assertEquals(1, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c = :correlationId]);
    }

    /**
     * AF-25: invocable methods receive bulk request lists. The previous implementation
     * issued one SOQL query per request, so 150 requests threw LimitException at 101.
     * This asserts the whole invocation stays within a small, fixed query budget.
     */
    @IsTest
    static void findRecentErrorsIsBulkSafe() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 150; i++) accounts.add(new Account(Name = 'Aegis Bulk ' + i));
        insert accounts;

        List<Error_Log__c> logs = new List<Error_Log__c>();
        for (Integer i = 0; i < 150; i++) {
            logs.add(new Error_Log__c(
                Correlation_Id__c = 'BULK-' + i,
                Source_Type__c = 'Apex Class',
                Object_API_Name__c = 'Account',
                Record_Id__c = accounts[i].Id,
                Original_Error_Message__c = 'Bulk probe ' + i,
                Status__c = 'New',
                User__c = UserInfo.getUserId()
            ));
        }
        insert logs;

        List<AEIR_FindRecentErrorsAction.Request> requests = new List<AEIR_FindRecentErrorsAction.Request>();
        for (Integer i = 0; i < 150; i++) {
            AEIR_FindRecentErrorsAction.Request r = new AEIR_FindRecentErrorsAction.Request();
            r.recordId = accounts[i].Id;
            requests.add(r);
        }
        AEIR_FindRecentErrorsAction.Request byObject = new AEIR_FindRecentErrorsAction.Request();
        byObject.objectApiName = 'Account';
        requests.add(byObject);
        requests.add(new AEIR_FindRecentErrorsAction.Request());

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        List<AEIR_FindRecentErrorsAction.Response> responses = AEIR_FindRecentErrorsAction.run(requests);
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        System.assertEquals(152, responses.size(), 'Every request must receive a response.');
        System.assert(queriesUsed <= 3, 'Expected at most 3 queries for the whole invocation, used ' + queriesUsed);
        System.assert(responses[0].resultsJson.contains('BULK-0'), 'Record-scoped request should return its own error log.');
        System.assert(responses[150].resultsJson.contains('Account'), 'Object-scoped request should return Account errors.');
    }
}