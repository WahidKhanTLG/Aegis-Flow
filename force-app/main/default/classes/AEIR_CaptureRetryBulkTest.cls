@IsTest
public class AEIR_CaptureRetryBulkTest {
    @TestSetup
    static void grantRetryPermission() {
        createAuthorizedRetryUser('Bulk');
        insert deniedUser();
    }

    /** A fresh user context ensures native custom-permission evaluation is not cached
     * from the validation caller before deployment/test limit contexts are switched. */
    public static User createAuthorizedRetryUser(String label) {
        User authorized = new User(Alias = ('aera' + label).substring(0, Math.min(8, 4 + label.length())),
            Email = 'aegis-retry-' + label.toLowerCase() + '@example.invalid',
            Username = 'aegis-retry-' + label.toLowerCase() + '-' + Datetime.now().getTime() + '@example.invalid',
            LastName = 'AegisRetryAuthorized' + label, ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
        insert authorized;
        CustomPermission permission = [SELECT Id FROM CustomPermission WHERE DeveloperName = 'AEIR_Execute_Retry' LIMIT 1];
        PermissionSet retryPermission = new PermissionSet(Name = 'AEIR_Retry_Regression_' + label, Label = 'Aegis Retry Regression ' + label);
        insert retryPermission;
        insert new SetupEntityAccess(ParentId = retryPermission.Id, SetupEntityId = permission.Id);
        PermissionSet productAdmin = [SELECT Id FROM PermissionSet WHERE Name = 'AEIR_Product_Admin' LIMIT 1];
        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(AssigneeId = authorized.Id, PermissionSetId = retryPermission.Id),
            new PermissionSetAssignment(AssigneeId = authorized.Id, PermissionSetId = productAdmin.Id)
        };
        return authorized;
    }
    private static User authorizedUser() {
        return [SELECT Id FROM User WHERE LastName = 'AegisRetryAuthorizedBulk' LIMIT 1];
    }

    private static Integer actualHandlerDml = 0;

    public class UpdatingHandler implements AEIR_RetryHandler {
        public AEIR_RetryOrchestrationService.RetryResult retry(AEIR_RetryOrchestrationService.RetryRequest request) {
            Integer beforeBusinessDml = Limits.getDmlStatements();
            update new Account(Id = request.targetRecordId, Description = 'Retried ' + request.correlationId);
            // Include customer automation triggered by this real business write.
            AEIR_CaptureRetryBulkTest.actualHandlerDml += Limits.getDmlStatements() - beforeBusinessDml;
            AEIR_RetryOrchestrationService.RetryResult result = new AEIR_RetryOrchestrationService.RetryResult();
            result.success = true;
            result.message = 'The test business update completed.';
            result.externalReference = String.valueOf(request.targetRecordId);
            return result;
        }
    }
    public class FailingAfterWriteHandler implements AEIR_RetryHandler {
        public AEIR_RetryOrchestrationService.RetryResult retry(AEIR_RetryOrchestrationService.RetryRequest request) {
            update new Account(Id = request.targetRecordId, Description = 'This write must be rolled back');
            throw new ControlledFailureException('The registered operation failed after its first write.');
        }
    }
    public class FalseAfterWriteHandler implements AEIR_RetryHandler {
        public AEIR_RetryOrchestrationService.RetryResult retry(AEIR_RetryOrchestrationService.RetryRequest request) {
            update new Account(Id = request.targetRecordId, Description = 'This write must also be rolled back');
            AEIR_RetryOrchestrationService.RetryResult result = new AEIR_RetryOrchestrationService.RetryResult();
            result.success = false;
            result.message = 'The operation did not pass its verification.';
            return result;
        }
    }
    public class ControlledFailureException extends Exception {}

    /** Shared by legacy integration tests so a business mutation proves real success. */
    public static void useUpdatingHandler(String key) {
        AEIR_RetryOrchestrationService.configurationOverrides = new Map<String, Retry_Handler__mdt>{
            key => configuration(key, 'AEIR_CaptureRetryBulkTest.UpdatingHandler', null)
        };
    }
    private static Retry_Handler__mdt configuration(String key, String className, Decimal backoff) {
        return new Retry_Handler__mdt(
            Handler_Key__c = key, Apex_Class__c = className, Active__c = true,
            Max_Attempts__c = 3, Backoff_Minutes__c = backoff,
            Idempotency_Strategy__c = 'Correlation Id plus target record id'
        );
    }
    private static AEIR_RetryOrchestrationService.RetryRequest retry(String correlation, Id target, String key) {
        AEIR_RetryOrchestrationService.RetryRequest request = new AEIR_RetryOrchestrationService.RetryRequest();
        request.correlationId = correlation;
        request.targetRecordId = target;
        request.handlerKey = key;
        request.attemptNumber = 1;
        return request;
    }
    private static AEIR_ErrorCaptureService.ErrorInput error(String correlation) {
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.correlationId = correlation;
        input.sourceType = 'Flow';
        input.sourceName = 'Cross_Business_Capture';
        input.originalMessage = 'REQUIRED_FIELD_MISSING: Name';
        return input;
    }

    @IsTest
    static void mixedExistingNewAndDuplicatesKeepInputOrder() {
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.USER_NOTIFICATIONS, false);
        AEIR_ErrorCaptureService.CaptureResult existing = AEIR_ErrorCaptureService.capture(error('ORDER-EXISTING'));
        List<AEIR_ErrorCaptureService.ErrorInput> inputs = new List<AEIR_ErrorCaptureService.ErrorInput>{
            error('ORDER-NEW-A'), error('ORDER-EXISTING'), error('ORDER-NEW-B'), error('order-new-a'), null
        };
        Test.startTest();
        List<AEIR_ErrorCaptureService.CaptureResult> results = AEIR_ErrorCaptureService.captureFromEvents(inputs);
        Test.stopTest();
        System.assertEquals(5, results.size());
        System.assertEquals('ORDER-NEW-A', results[0].correlationId);
        System.assertEquals(existing.errorLogId, results[1].errorLogId);
        System.assertEquals('ORDER-NEW-B', results[2].correlationId);
        System.assertEquals(results[0].errorLogId, results[3].errorLogId, 'Case-insensitive duplicate inputs share one persisted log.');
        System.assertEquals(1, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c = 'ORDER-NEW-A']);
        System.assertNotEquals(null, results[4], 'A null input must retain its response slot.');
    }

    @IsTest
    static void crossUserCorrelationDoesNotLeakAnotherDiagnostic() {
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.USER_NOTIFICATIONS, false);
        AEIR_ErrorCaptureService.CaptureResult existing = AEIR_ErrorCaptureService.capture(error('PRIVATE-CORRELATION'));
        User other = [SELECT Id FROM User WHERE LastName = 'AegisRetryUnprivileged' LIMIT 1];
        AEIR_ErrorCaptureService.ErrorInput input = error('PRIVATE-CORRELATION');
        input.userId = other.Id;
        List<AEIR_ErrorCaptureService.CaptureResult> results = AEIR_ErrorCaptureService.captureFromEvents(
            new List<AEIR_ErrorCaptureService.ErrorInput>{ input });
        System.assertEquals(false, results[0].success);
        System.assertEquals(null, results[0].errorLogId, 'A cross-user collision cannot return the other diagnostic Id.');
        System.assertEquals(null, results[0].normalizedMessage);
    }

    @IsTest
    static void oversizedCorrelationFailsWithoutLosingOtherInputs() {
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.USER_NOTIFICATIONS, false);
        String longCorrelation = '';
        for (Integer i = 0; i < 81; i++) longCorrelation += 'x';
        List<AEIR_ErrorCaptureService.CaptureResult> results = AEIR_ErrorCaptureService.captureFromEvents(
            new List<AEIR_ErrorCaptureService.ErrorInput>{ error(longCorrelation), error('VALID-SALES-CAPTURE') });
        System.assertEquals(false, results[0].success);
        System.assertEquals(true, results[1].success);
        System.assertEquals('VALID-SALES-CAPTURE', results[1].correlationId);
    }

    @IsTest
    static void rollbackSafeFlowCaptureReturnsAsyncAcknowledgement() {
        AEIR_CaptureFlowFaultAction.Request request = new AEIR_CaptureFlowFaultAction.Request();
        request.varCorrelationId = 'ROLLBACK-SAFE-FAULT';
        request.varRollbackSafe = true;
        request.varFlowApiName = 'Cross_Business_Fault';
        request.varFlowVersion = '2';
        request.varFailedElement = 'Update_Records';
        request.varErrorMessage = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: required business value';
        request.varContextJson = '{"businessProcess":"service"}';
        Test.startTest();
        Savepoint pointBeforeCapture = Database.setSavepoint();
        List<AEIR_CaptureFlowFaultAction.Response> responses = AEIR_CaptureFlowFaultAction.captureFlowFault(
            new List<AEIR_CaptureFlowFaultAction.Request>{ request });
        Database.rollback(pointBeforeCapture);
        Database.releaseSavepoint(pointBeforeCapture);
        Test.getEventBus().deliver();
        Test.stopTest();
        System.assertEquals(true, responses[0].success);
        System.assertEquals('Published', responses[0].status);
        System.assertEquals(null, responses[0].errorLogId, 'Asynchronous acceptance must not invent a persisted Id.');
        Error_Log__c captured = [SELECT Source_Name__c, Context_JSON__c FROM Error_Log__c
            WHERE Correlation_Id__c = 'ROLLBACK-SAFE-FAULT' LIMIT 1];
        System.assertEquals('Cross_Business_Fault', captured.Source_Name__c);
        System.assert(captured.Context_JSON__c.contains('Update_Records'));
    }

    @IsTest
    static void retryBatchPrefetchesAndWritesOneAuditPerUniqueWorkItem() {
        Test.startTest();
        System.runAs(authorizedUser()) {
            System.assert(FeatureManagement.checkPermission('AEIR_Execute_Retry'), 'The dedicated retry fixture must have its native custom permission.');
            useUpdatingHandler('TEST_UPDATE');
            List<Account> accounts = new List<Account>();
            for (Integer i = 0; i < 20; i++) accounts.add(new Account(Name = 'Cross-business retry ' + i));
            insert accounts;
            List<AEIR_RetryOrchestrationService.RetryRequest> requests = new List<AEIR_RetryOrchestrationService.RetryRequest>();
            for (Integer i = 0; i < 20; i++) requests.add(retry('RETRY-BULK-' + i, accounts[i].Id, 'TEST_UPDATE'));
            actualHandlerDml = 0;
            Integer beforeQueries = Limits.getQueries();
            Integer beforeDml = Limits.getDmlStatements();
            List<AEIR_RetryOrchestrationService.RetryResult> results = AEIR_ExecuteRetryHandlerAction.run(requests);
            Integer queries = Limits.getQueries() - beforeQueries;
            Integer dml = Limits.getDmlStatements() - beforeDml;
            System.assertEquals(20, results.size());
            for (AEIR_RetryOrchestrationService.RetryResult result : results) System.assertEquals(true, result.success, result.message);
            System.assert(queries <= 3, 'State queries must be prefetched instead of repeated per retry; used ' + queries);
            Integer frameworkDml = dml - actualHandlerDml;
            System.assert(actualHandlerDml >= 20, 'Each unique retry must execute a real business write.');
            System.assert(frameworkDml <= 45, 'Framework overhead must remain bounded: 21 savepoints, 21 releases and 2 audit writes; used '
                + frameworkDml + ', business/automation DML ' + actualHandlerDml);
            System.assertEquals(20, [SELECT count() FROM Retry_Attempt__c WHERE Handler_Key__c = 'TEST_UPDATE' AND Status__c = 'Succeeded']);
            Map<Id, String> expectedDescriptions = new Map<Id, String>();
            for (Integer i = 0; i < accounts.size(); i++) expectedDescriptions.put(accounts[i].Id, 'Retried RETRY-BULK-' + i);
            List<Account> updatedAccounts = [SELECT Id, Description FROM Account WHERE Id IN :accounts];
            System.assertEquals(20, updatedAccounts.size());
            for (Account updated : updatedAccounts) System.assertEquals(expectedDescriptions.get(updated.Id), updated.Description);
        }
        Test.stopTest();
    }

    @IsTest
    static void duplicateRequestsShareOneHandlerExecutionAndAudit() {
        Test.startTest();
        System.runAs(authorizedUser()) {
            System.assert(FeatureManagement.checkPermission('AEIR_Execute_Retry'), 'The dedicated retry fixture must have its native custom permission.');
            useUpdatingHandler('TEST_UPDATE');
            Account accountRecord = new Account(Name = 'Duplicate retry');
            insert accountRecord;
            AEIR_RetryOrchestrationService.RetryRequest request = retry('RETRY-ONCE', accountRecord.Id, 'TEST_UPDATE');
            List<AEIR_RetryOrchestrationService.RetryResult> first = AEIR_ExecuteRetryHandlerAction.run(
                new List<AEIR_RetryOrchestrationService.RetryRequest>{ request, request });
            System.assertEquals(true, first[0].success, first[0].message);
            System.assertEquals(first[0].retryAttemptId, first[1].retryAttemptId);
            update new Account(Id = accountRecord.Id, Description = 'Changed after first retry');
            AEIR_RetryOrchestrationService.RetryResult again = AEIR_RetryOrchestrationService.requestRetry(request);
            System.assertEquals(first[0].retryAttemptId, again.retryAttemptId);
            System.assertEquals('Changed after first retry', [SELECT Description FROM Account WHERE Id = :accountRecord.Id].Description);
            System.assertEquals(1, [SELECT count() FROM Retry_Attempt__c WHERE Handler_Key__c = 'TEST_UPDATE']);
        }
        Test.stopTest();
    }

    @IsTest
    static void nullUnknownAndOversizedBatchesDoNotRunHandlers() {
        Test.startTest();
        System.runAs(authorizedUser()) {
            System.assert(FeatureManagement.checkPermission('AEIR_Execute_Retry'), 'The dedicated retry fixture must have its native custom permission.');
            useUpdatingHandler('TEST_UPDATE');
            System.assertEquals(0, AEIR_ExecuteRetryHandlerAction.run(null).size());
            List<AEIR_RetryOrchestrationService.RetryResult> invalid = AEIR_ExecuteRetryHandlerAction.run(
                new List<AEIR_RetryOrchestrationService.RetryRequest>{ null, retry('UNKNOWN', null, 'UNKNOWN') });
            System.assertEquals(false, invalid[0].success);
            System.assertEquals(false, invalid[1].success);
            List<AEIR_RetryOrchestrationService.RetryRequest> tooMany = new List<AEIR_RetryOrchestrationService.RetryRequest>();
            for (Integer i = 0; i < 21; i++) tooMany.add(retry('LIMIT-' + i, null, 'TEST_UPDATE'));
            Integer beforeDml = Limits.getDmlStatements();
            List<AEIR_RetryOrchestrationService.RetryResult> rejected = AEIR_ExecuteRetryHandlerAction.run(tooMany);
            System.assertEquals(beforeDml, Limits.getDmlStatements(), 'Reject unsupported batches before any side effect.');
            System.assertEquals(21, rejected.size());
            System.assertEquals(false, rejected[0].success);
            System.assertEquals(0, [SELECT count() FROM Retry_Attempt__c]);
        }
        Test.stopTest();
    }

    @IsTest
    static void handlerFailureRollsBackItsBusinessWrites() {
        Test.startTest();
        System.runAs(authorizedUser()) {
            System.assert(FeatureManagement.checkPermission('AEIR_Execute_Retry'), 'The dedicated retry fixture must have its native custom permission.');
            AEIR_RetryOrchestrationService.configurationOverrides = new Map<String, Retry_Handler__mdt>{
                'THROWING' => configuration('THROWING', 'AEIR_CaptureRetryBulkTest.FailingAfterWriteHandler', null),
                'FALSE' => configuration('FALSE', 'AEIR_CaptureRetryBulkTest.FalseAfterWriteHandler', null)
            };
            List<Account> accounts = new List<Account>{ new Account(Name = 'Thrown failure', Description = 'Original'),
                new Account(Name = 'False failure', Description = 'Original') };
            insert accounts;
            List<AEIR_RetryOrchestrationService.RetryResult> results = AEIR_ExecuteRetryHandlerAction.run(
                new List<AEIR_RetryOrchestrationService.RetryRequest>{ retry('THROW-FAIL', accounts[0].Id, 'THROWING'),
                    retry('FALSE-FAIL', accounts[1].Id, 'FALSE') });
            for (AEIR_RetryOrchestrationService.RetryResult result : results) System.assertEquals(false, result.success);
            for (Account accountRecord : [SELECT Description FROM Account WHERE Id IN :accounts]) System.assertEquals('Original', accountRecord.Description);
            System.assertEquals(2, [SELECT count() FROM Retry_Attempt__c WHERE Status__c = 'Failed']);
        }
        Test.stopTest();
    }

    @IsTest
    static void backoffAndMaximumAttemptsAreEnforced() {
        Test.startTest();
        System.runAs(authorizedUser()) {
            System.assert(FeatureManagement.checkPermission('AEIR_Execute_Retry'), 'The dedicated retry fixture must have its native custom permission.');
            AEIR_RetryOrchestrationService.configurationOverrides = new Map<String, Retry_Handler__mdt>{
                'BACKOFF' => configuration('BACKOFF', 'AEIR_CaptureRetryBulkTest.UpdatingHandler', 15)
            };
            Account accountRecord = new Account(Name = 'Backoff retry');
            insert accountRecord;
            AEIR_RetryOrchestrationService.RetryRequest first = retry('BACKOFF-CORRELATION', accountRecord.Id, 'BACKOFF');
            System.assertEquals(true, AEIR_RetryOrchestrationService.requestRetry(first).success);
            AEIR_RetryOrchestrationService.RetryRequest next = retry('BACKOFF-CORRELATION', accountRecord.Id, 'BACKOFF');
            next.attemptNumber = 2;
            AEIR_RetryOrchestrationService.RetryResult refused = AEIR_RetryOrchestrationService.requestRetry(next);
            System.assertEquals(false, refused.success);
            System.assert(refused.message.contains('backoff'));
            next.attemptNumber = 4;
            refused = AEIR_RetryOrchestrationService.requestRetry(next);
            System.assertEquals(false, refused.success);
            System.assert(refused.message.contains('maximum'));
            System.assertEquals(1, [SELECT count() FROM Retry_Attempt__c]);
        }
        Test.stopTest();
    }

    private static User deniedUser() {
        return new User(Alias = 'aeretry', Email = 'retry-denied@example.invalid',
            Username = 'aegis-retry-denied-' + Datetime.now().getTime() + '@example.invalid',
            LastName = 'AegisRetryUnprivileged', ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
    }

    @IsTest
    static void userWithoutRetryPermissionIsDeniedBeforeAuditWrites() {
        User caller = [SELECT Id FROM User WHERE LastName = 'AegisRetryUnprivileged' LIMIT 1];
        System.runAs(caller) {
            Integer beforeDml = Limits.getDmlStatements();
            AEIR_RetryOrchestrationService.RetryResult result = AEIR_RetryOrchestrationService.requestRetry(
                retry('DENIED-RETRY', null, 'TEST_UPDATE'));
            System.assertEquals(false, result.success);
            System.assertEquals('Denied', result.status);
            System.assertEquals(beforeDml, Limits.getDmlStatements());
        }
    }

    @IsTest
    static void sampleHandlerCannotClaimUnperformedBusinessSuccess() {
        AEIR_RetryOrchestrationService.RetryResult result = new AEIR_SampleTaxRetryHandler().retry(null);
        System.assertEquals(false, result.success);
        System.assertEquals('Failed', result.status);
        System.assert(result.message.contains('No customer tax recalculation is configured'));
    }
}
