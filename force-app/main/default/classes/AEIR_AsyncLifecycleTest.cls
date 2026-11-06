@IsTest
private class AEIR_AsyncLifecycleTest {
    /**
     * The production interface is injected by Apex. Implementing its documented
     * contract lets failure assertions exercise the same execute method without
     * adding test-only branches or deliberately failing a deployed example job.
     */
    private class OutcomeContext implements System.FinalizerContext {
        private System.ParentJobResult outcome;
        private Exception failure;
        private Id parentId = (Id) '70700000000000A';
        OutcomeContext(System.ParentJobResult outcome, Exception failure) {
            this.outcome = outcome;
            this.failure = failure;
        }
        public Id getAsyncApexJobId() { return parentId; }
        public String getRequestId() { return 'ASYNC-UNIT-REQUEST'; }
        public System.ParentJobResult getResult() { return outcome; }
        public Exception getException() { return failure; }
    }

    private class WorkerFailureException extends Exception {}

    private class SuccessfulWorker implements Queueable {
        private Id accountId;
        private String correlation;
        SuccessfulWorker(Id accountId, String correlation) {
            this.accountId = accountId;
            this.correlation = correlation;
        }
        public void execute(QueueableContext context) {
            System.attachFinalizer(new AEIR_QueueableFinalizer(correlation, 'Async success probe',
                'Account', String.valueOf(accountId), '{"phase":"save"}'));
            update new Account(Id = accountId, Description = 'Committed by successful Queueable');
        }
    }

    private static Exception businessFailure() {
        try {
            throw new WorkerFailureException('Queueable business operation failed.');
        } catch (WorkerFailureException expected) {
            return expected;
        }
    }

    @IsTest
    static void realSuccessfulQueueableCommitsWithoutCreatingFalseDiagnostics() {
        Account accountRecord = new Account(Name = 'Async success boundary', Description = 'Before');
        insert accountRecord;
        Test.startTest();
        System.enqueueJob(new SuccessfulWorker(accountRecord.Id, 'ASYNC-SUCCESS-NO-ERROR'));
        Test.stopTest();
        System.assertEquals('Committed by successful Queueable', [SELECT Description FROM Account WHERE Id = :accountRecord.Id].Description);
        System.assertEquals(0, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c = 'ASYNC-SUCCESS-NO-ERROR'],
            'The finalizer must not turn a successful job into an error.');
    }

    @IsTest
    static void successfulOutcomeDoesNotQueryOrWriteDiagnosticEvidence() {
        AEIR_QueueableFinalizer finalizer = new AEIR_QueueableFinalizer('ASYNC-SUCCESS-DIRECT',
            'No-op success', null, null, null);
        Test.startTest();
        Integer beforeQueries = Limits.getQueries();
        Integer beforeDml = Limits.getDmlStatements();
        finalizer.execute(new OutcomeContext(System.ParentJobResult.SUCCESS, null));
        System.assertEquals(beforeQueries, Limits.getQueries());
        System.assertEquals(beforeDml, Limits.getDmlStatements());
        Test.stopTest();
    }

    @IsTest
    static void failureHandlerPreservesEvidenceAfterAnExplicitCallerRollback() {
        Account accountRecord = new Account(Name = 'Async rollback boundary', Description = 'Before');
        insert accountRecord;
        Savepoint businessBoundary = Database.setSavepoint();
        update new Account(Id = accountRecord.Id, Description = 'Uncommitted business change');
        Exception failure = businessFailure();
        Database.rollback(businessBoundary);
        Database.releaseSavepoint(businessBoundary);
        System.assertEquals('Before', [SELECT Description FROM Account WHERE Id = :accountRecord.Id].Description);

        // This is a deterministic outcome-handler test after explicit rollback. It
        // does not claim to emulate Apex's separate finalizer transaction boundary.
        AEIR_QueueableFinalizer finalizer = new AEIR_QueueableFinalizer('ASYNC-FAILURE-EVIDENCE',
            'Account save worker', 'Account', String.valueOf(accountRecord.Id), '{"phase":"after rollback"}');
        Test.startTest();
        finalizer.execute(new OutcomeContext(System.ParentJobResult.UNHANDLED_EXCEPTION, failure));
        finalizer.execute(new OutcomeContext(System.ParentJobResult.UNHANDLED_EXCEPTION, failure));
        Test.stopTest();
        List<Error_Log__c> logs = [SELECT Source_Type__c, Source_Name__c, Object_API_Name__c, Record_Id__c,
            Original_Error_Message__c, Stack_Trace__c, Context_JSON__c, Severity__c, User__c
            FROM Error_Log__c WHERE Correlation_Id__c = 'ASYNC-FAILURE-EVIDENCE'];
        System.assertEquals(1, logs.size(), 'Repeated finalizer delivery must reuse its correlation.');
        System.assertEquals('Queueable', logs[0].Source_Type__c);
        System.assertEquals('Account save worker', logs[0].Source_Name__c);
        System.assertEquals('Account', logs[0].Object_API_Name__c);
        System.assertEquals(String.valueOf(accountRecord.Id), logs[0].Record_Id__c);
        System.assertEquals('Queueable business operation failed.', logs[0].Original_Error_Message__c);
        System.assert(!String.isBlank(logs[0].Stack_Trace__c), 'Keep the actual exception trace.');
        System.assertEquals('after rollback', ((Map<String, Object>) JSON.deserializeUntyped(logs[0].Context_JSON__c)).get('phase'));
        System.assertEquals('High', logs[0].Severity__c);
        System.assertEquals(UserInfo.getUserId(), logs[0].User__c);
        System.assertEquals('Before', [SELECT Description FROM Account WHERE Id = :accountRecord.Id].Description,
            'Capturing failure evidence must not reapply the rolled-back business write.');
    }

    @IsTest
    static void failureWithoutExceptionStillExplainsItsOutcome() {
        new AEIR_QueueableFinalizer('ASYNC-NO-EXCEPTION', 'Unknown failing worker', null, null, null)
            .execute(new OutcomeContext(System.ParentJobResult.UNHANDLED_EXCEPTION, null));
        Error_Log__c log = [SELECT Original_Error_Message__c, Stack_Trace__c FROM Error_Log__c
            WHERE Correlation_Id__c = 'ASYNC-NO-EXCEPTION' LIMIT 1];
        System.assertEquals('Queueable failed with result: UNHANDLED_EXCEPTION', log.Original_Error_Message__c);
        System.assertEquals(null, log.Stack_Trace__c);
    }

    @IsTest
    static void exampleAttachmentRemainsASuccessfulSafeDemonstration() {
        Test.startTest();
        System.enqueueJob(new AEIR_QueueableFinalizerExample('ASYNC-EXAMPLE-SUCCESS'));
        Test.stopTest();
        AsyncApexJob job = [SELECT Status, NumberOfErrors FROM AsyncApexJob
            WHERE ApexClass.Name = 'AEIR_QueueableFinalizerExample' AND JobType = 'Queueable'
            ORDER BY CreatedDate DESC LIMIT 1];
        System.assertEquals('Completed', job.Status);
        System.assertEquals(0, job.NumberOfErrors);
        System.assertEquals(0, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c = 'ASYNC-EXAMPLE-SUCCESS']);
    }

    @IsTest
    static void exampleFailureIncludesJobAndRequestEvidence() {
        OutcomeContext context = new OutcomeContext(System.ParentJobResult.UNHANDLED_EXCEPTION, businessFailure());
        new AEIR_QueueableFinalizerExample('ASYNC-EXAMPLE-FAILURE').execute(context);
        Error_Log__c log = [SELECT Source_Type__c, Source_Name__c, Original_Error_Message__c, Context_JSON__c
            FROM Error_Log__c WHERE Correlation_Id__c = 'ASYNC-EXAMPLE-FAILURE' LIMIT 1];
        System.assertEquals('Queueable', log.Source_Type__c);
        System.assertEquals(String.valueOf(context.getAsyncApexJobId()), log.Source_Name__c);
        System.assertEquals('Queueable business operation failed.', log.Original_Error_Message__c);
        Map<String, Object> evidence = (Map<String, Object>) JSON.deserializeUntyped(log.Context_JSON__c);
        System.assertEquals(String.valueOf(context.getAsyncApexJobId()), evidence.get('asyncApexJobId'));
        System.assertEquals(context.getRequestId(), evidence.get('requestId'));
        System.assertEquals('UNHANDLED_EXCEPTION', evidence.get('result'));
    }

    @IsTest
    static void exampleFailureWithoutExceptionUsesAnExplicitFallback() {
        new AEIR_QueueableFinalizerExample('ASYNC-EXAMPLE-NO-EXCEPTION')
            .execute(new OutcomeContext(System.ParentJobResult.UNHANDLED_EXCEPTION, null));
        System.assertEquals('Queueable failed with unknown exception.', [SELECT Original_Error_Message__c
            FROM Error_Log__c WHERE Correlation_Id__c = 'ASYNC-EXAMPLE-NO-EXCEPTION' LIMIT 1].Original_Error_Message__c);
    }

    @IsTest
    static void exampleDoesNotOverwriteAConflictingDiagnostic() {
        insert new Error_Log__c(Correlation_Id__c = 'ASYNC-EXAMPLE-CONFLICT', Source_Type__c = 'API',
            Original_Error_Message__c = 'Original evidence', User__c = null, Severity__c = 'Medium');
        new AEIR_QueueableFinalizerExample('ASYNC-EXAMPLE-CONFLICT')
            .execute(new OutcomeContext(System.ParentJobResult.UNHANDLED_EXCEPTION, businessFailure()));
        List<Error_Log__c> logs = [SELECT Original_Error_Message__c FROM Error_Log__c WHERE Correlation_Id__c = 'ASYNC-EXAMPLE-CONFLICT'];
        System.assertEquals(1, logs.size());
        System.assertEquals('Original evidence', logs[0].Original_Error_Message__c,
            'A capture failure must not overwrite evidence belonging to a different attribution.');
    }

    @IsTest
    static void linkedDebugLogReturnsAndPersistsOnlyItsReference() {
        String debugLogId = '07L000000000001AAA';
        Error_Log__c log = new Error_Log__c(Correlation_Id__c = 'ASYNC-DEBUG-LINKED', Source_Type__c = 'Queueable',
            Debug_Log_Id__c = debugLogId, User__c = UserInfo.getUserId());
        insert log;
        Test.startTest();
        AEIR_LogCollectorService.LogCollectionResult result = AEIR_LogCollectorService.collectForError(log.Id);
        Test.stopTest();
        String expectedLink = URL.getOrgDomainUrl().toExternalForm() + '/' + debugLogId;
        System.assertEquals(true, result.available);
        System.assertEquals(debugLogId, result.debugLogId);
        System.assertEquals(expectedLink, result.debugLogLink);
        System.assertEquals(expectedLink, [SELECT Debug_Log_Link__c FROM Error_Log__c WHERE Id = :log.Id].Debug_Log_Link__c);
        System.assertEquals(false, result.bodyRetrieved);
        System.assertEquals(null, result.debugLogBody);
        System.assert(result.message.contains('Debug-log body retrieval is disabled'),
            'Returning a linked Id must not imply that debug-log contents were retrieved.');
    }

    @IsTest
    static void missingDebugLogRemainsAnExplicitNonMutatingOutcome() {
        Error_Log__c log = new Error_Log__c(Correlation_Id__c = 'ASYNC-DEBUG-MISSING', Source_Type__c = 'Queueable',
            User__c = UserInfo.getUserId());
        insert log;
        Test.startTest();
        Integer beforeDml = Limits.getDmlStatements();
        AEIR_LogCollectorService.LogCollectionResult result = AEIR_LogCollectorService.collectForError(log.Id);
        System.assertEquals(beforeDml, Limits.getDmlStatements(), 'Missing logs must not manufacture links or evidence.');
        Test.stopTest();
        System.assertEquals(false, result.available);
        System.assertEquals(null, result.debugLogId);
        System.assertEquals(null, result.debugLogLink);
        System.assert(result.message.contains('No debug log id is available'));
        System.assertEquals(null, [SELECT Debug_Log_Link__c FROM Error_Log__c WHERE Id = :log.Id].Debug_Log_Link__c);
    }
}
