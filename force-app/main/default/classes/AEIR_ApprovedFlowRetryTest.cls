@IsTest
private class AEIR_ApprovedFlowRetryTest {
    private static final String HANDLER_KEY = 'APPROVED_FLOW_RECOVERY';
    private static Integer calls = 0;
    private static Map<String, Object> lastInputs;
    private static String mode = 'success';

    @TestSetup
    static void actors() {
        AEIR_CaptureRetryBulkTest.createAuthorizedRetryUser('Flow');
        Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id;
        List<User> users = new List<User>();
        for (String label : new List<String>{'NoCapability', 'NoObject', 'RecordReader'}) {
            users.add(new User(Alias = 'afretry', LastName = 'AegisFlowRetry' + label, ProfileId = profileId,
                Email = 'approved-flow-retry@example.invalid',
                Username = 'aegis.flow.' + label + '.' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)) + '@example.invalid',
                TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'));
        }
        insert users;
        PermissionSet capability = new PermissionSet(Name = 'AEIR_Flow_Retry_Capability', Label = 'Aegis Flow Retry Capability');
        PermissionSet reader = new PermissionSet(Name = 'AEIR_Flow_Retry_Record_Reader', Label = 'Aegis Flow Retry Record Reader');
        insert new List<PermissionSet>{capability, reader};
        insert new SetupEntityAccess(ParentId = capability.Id,
            SetupEntityId = [SELECT Id FROM CustomPermission WHERE DeveloperName = 'AEIR_Execute_Retry' LIMIT 1].Id);
        insert new ObjectPermissions(ParentId = reader.Id, SObjectType = 'Error_Feedback__c',
            PermissionsRead = true, PermissionsEdit = true);
        insert new FieldPermissions(ParentId = reader.Id, SObjectType = 'Error_Feedback__c',
            Field = 'Error_Feedback__c.Comments__c', PermissionsRead = true, PermissionsEdit = true);
        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(AssigneeId = users[1].Id, PermissionSetId = capability.Id),
            new PermissionSetAssignment(AssigneeId = users[2].Id, PermissionSetId = capability.Id),
            new PermissionSetAssignment(AssigneeId = users[2].Id, PermissionSetId = reader.Id)
        };
    }

    private class RecoveryFailureException extends Exception {}
    private class WritingRunner extends AEIR_ApprovedFlowRetryHandler.FlowRunner {
        public override Map<String, Object> run(String apiName, Map<String, Object> inputs) {
            System.assertEquals('AEIR_Reviewed_Customer_Recovery', apiName);
            calls++;
            lastInputs = inputs;
            System.assertEquals(new Set<String>{'varTargetRecordId', 'varCorrelationId', 'varAttemptNumber', 'varRecoveryKey'}, inputs.keySet());
            update new Error_Feedback__c(Id = (Id) (String) inputs.get('varTargetRecordId'),
                Comments__c = 'Recovered:' + (String) inputs.get('varRecoveryKey'));
            if (mode == 'throw') throw new RecoveryFailureException(
                'Flow failed at https://qa.invalid/recover?unregisteredCredential=FLOW_PROVIDER_SECRET for person@example.invalid');
            if (mode == 'null') return null;
            Map<String, Object> result = new Map<String, Object>{
                'success' => mode == 'false' ? false : true,
                'recordId' => inputs.get('varTargetRecordId'),
                'message' => '{"password":"PRIVATE_FLOW_RESULT","message":"Recovery completed"}'
            };
            if (mode == 'stringSuccess') result.put('success', 'true');
            if (mode == 'wrongTarget') result.put('recordId', String.valueOf(UserInfo.getUserId()));
            if (mode == 'invalidTarget') result.put('recordId', 'not-a-record');
            if (mode == 'invalidMessage') result.put('message', 123);
            return result;
        }
    }

    private static User actor(String label) {
        String name = label == 'Authorized' ? 'AegisRetryAuthorizedFlow' : 'AegisFlowRetry' + label;
        return [SELECT Id FROM User WHERE LastName = :name LIMIT 1];
    }
    private static Retry_Handler__mdt registration() {
        return new Retry_Handler__mdt(Handler_Key__c = HANDLER_KEY, Active__c = true,
            Apex_Class__c = 'AEIR_ApprovedFlowRetryHandler', Flow_API_Name__c = 'AEIR_Reviewed_Customer_Recovery',
            Target_Object__c = 'Error_Feedback__c', Required_Permission__c = 'AEIR_Execute_Retry',
            Max_Attempts__c = 3, Idempotency_Strategy__c = 'Correlation Id plus target record id');
    }
    private static void configure() {
        Retry_Handler__mdt row = registration();
        AEIR_RetryOrchestrationService.configurationOverrides = new Map<String, Retry_Handler__mdt>{HANDLER_KEY => row};
        AEIR_ApprovedFlowRetryHandler.configurationOverrides = new List<Retry_Handler__mdt>{row};
        AEIR_ApprovedFlowRetryHandler.flowRunner = new WritingRunner();
    }
    private static AEIR_RetryOrchestrationService.RetryRequest request(Id target, String correlation) {
        AEIR_RetryOrchestrationService.RetryRequest item = new AEIR_RetryOrchestrationService.RetryRequest();
        item.handlerKey = HANDLER_KEY; item.targetRecordId = target;
        item.correlationId = correlation; item.attemptNumber = 1;
        return item;
    }

    @IsTest
    static void approvedRecoveryPerformsAuditedWorkAndDeduplicates() {
        Error_Feedback__c target = new Error_Feedback__c(Comments__c = 'Before');
        insert target;
        configure();
        Test.startTest();
        System.runAs(actor('Authorized')) {
            System.assert(FeatureManagement.checkPermission('AEIR_Execute_Retry'));
            AEIR_RetryOrchestrationService.RetryRequest item = request(target.Id, 'FLOW-REAL-WRITE');
            AEIR_RetryOrchestrationService.RetryResult result = AEIR_RetryOrchestrationService.requestRetry(item);
            System.assertEquals(true, result.success, result.message);
            System.assert(!result.message.contains('PRIVATE_FLOW_RESULT'), 'Flow output must be sanitized.');
            System.assertEquals(String.valueOf(target.Id), result.externalReference);
            AEIR_RetryOrchestrationService.RetryResult duplicate = AEIR_RetryOrchestrationService.requestRetry(item);
            System.assertEquals(true, duplicate.success);
            System.assertEquals(result.retryAttemptId, duplicate.retryAttemptId);
            System.assertEquals(1, calls, 'A duplicate request must not invoke the business Flow again.');
            System.assertEquals('Succeeded', [SELECT Status__c FROM Retry_Attempt__c WHERE Id = :result.retryAttemptId].Status__c);
            System.assertEquals('Recovered:' + (String) lastInputs.get('varRecoveryKey'),
                [SELECT Comments__c FROM Error_Feedback__c WHERE Id = :target.Id].Comments__c);
        }
        Test.stopTest();
    }

    @IsTest
    static void unsuccessfulAndThrownFlowMutationsAreRolledBack() {
        Error_Feedback__c target = new Error_Feedback__c(Comments__c = 'Before');
        insert target;
        configure();
        Test.startTest();
        System.runAs(actor('Authorized')) {
            for (String failureMode : new List<String>{'false', 'throw'}) {
                mode = failureMode;
                AEIR_RetryOrchestrationService.RetryResult result =
                    AEIR_RetryOrchestrationService.requestRetry(request(target.Id, 'FLOW-ROLLBACK-' + failureMode));
                System.assertEquals(false, result.success);
                Retry_Attempt__c audit = [SELECT Status__c, Result_Message__c FROM Retry_Attempt__c WHERE Id = :result.retryAttemptId];
                System.assertEquals('Failed', audit.Status__c);
                if (failureMode == 'throw') {
                    System.assert(result.message.contains('FlowExecution'), result.message);
                    for (String secret : new List<String>{'FLOW_PROVIDER_SECRET', 'qa.invalid', 'person@example.invalid'}) {
                        System.assert(!result.message.contains(secret), 'Exception content must not reach the caller.');
                        System.assert(!audit.Result_Message__c.contains(secret), 'Exception content must not reach the retry audit.');
                    }
                }
                System.assertEquals('Before', [SELECT Comments__c FROM Error_Feedback__c WHERE Id = :target.Id].Comments__c);
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void outputContractFailureNeverCommitsTheBusinessWrite() {
        Error_Feedback__c target = new Error_Feedback__c(Comments__c = 'Before');
        insert target;
        configure();
        Test.startTest();
        System.runAs(actor('Authorized')) {
            for (String invalid : new List<String>{'null', 'stringSuccess', 'wrongTarget', 'invalidTarget', 'invalidMessage'}) {
                mode = invalid;
                AEIR_RetryOrchestrationService.RetryResult result =
                    AEIR_RetryOrchestrationService.requestRetry(request(target.Id, 'FLOW-CONTRACT-' + invalid));
                System.assertEquals(false, result.success, invalid);
                System.assertEquals('Failed', [SELECT Status__c FROM Retry_Attempt__c WHERE Id = :result.retryAttemptId].Status__c);
                System.assertEquals('Before', [SELECT Comments__c FROM Error_Feedback__c WHERE Id = :target.Id].Comments__c, invalid);
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void invalidInputsAndUnapprovedRegistrationsFailBeforeInvocation() {
        Error_Feedback__c target = new Error_Feedback__c(Comments__c = 'Before');
        insert target;
        configure();
        Test.startTest();
        System.runAs(actor('Authorized')) {
            AEIR_ApprovedFlowRetryHandler handler = new AEIR_ApprovedFlowRetryHandler();
            System.assertEquals(false, handler.retry(null).success);
            AEIR_RetryOrchestrationService.RetryRequest item = request(target.Id, 'FLOW-VALIDATION');
            item.payloadJson = '{"flowApiName":"UnapprovedFlow"}';
            System.assertEquals(false, handler.retry(item).success, 'Client payload cannot select a Flow or supply extra inputs.');
            item.payloadJson = null;
            AEIR_ApprovedFlowRetryHandler.configurationOverrides = null;
            item.handlerKey = 'AEIR_UNIT_NOT_REGISTERED';
            System.assertEquals(false, handler.retry(item).success, 'An unregistered production action is disabled.');
            item.handlerKey = HANDLER_KEY;
            AEIR_ApprovedFlowRetryHandler.configurationOverrides = new List<Retry_Handler__mdt>();
            System.assertEquals(false, handler.retry(item).success);
            AEIR_ApprovedFlowRetryHandler.configurationOverrides = new List<Retry_Handler__mdt>{registration(), registration()};
            System.assertEquals(false, handler.retry(item).success, 'Ambiguous allowlists must fail closed.');
            Retry_Handler__mdt row = registration();
            row.Flow_API_Name__c = 'https://unapproved.invalid/flow';
            AEIR_ApprovedFlowRetryHandler.configurationOverrides = new List<Retry_Handler__mdt>{row};
            System.assertEquals(false, handler.retry(item).success);
            row.Flow_API_Name__c = 'AEIR_Reviewed_Customer_Recovery';
            row.Required_Permission__c = 'AEIR_Unconfigured_Business_Recovery';
            System.assertEquals(false, handler.retry(item).success, 'A missing recovery permission is denied natively.');
            row.Required_Permission__c = 'AEIR_Execute_Retry';
            item.attemptNumber = 4;
            System.assertEquals(false, handler.retry(item).success);
            item.attemptNumber = 1; item.targetRecordId = UserInfo.getUserId();
            System.assertEquals(false, handler.retry(item).success, 'An accessible record of another type is not the approved target.');
            System.assertEquals(0, calls);
        }
        Test.stopTest();
    }

    @IsTest
    static void nativeCapabilityObjectAndRecordEditBoundariesRemainEnforced() {
        Error_Feedback__c target = new Error_Feedback__c(Comments__c = 'Private');
        insert target;
        configure();
        User reader = actor('RecordReader');
        Test.startTest();
        System.runAs(actor('NoCapability')) {
            System.assert(!FeatureManagement.checkPermission('AEIR_Execute_Retry'));
            System.assertEquals(false, new AEIR_ApprovedFlowRetryHandler().retry(request(target.Id, 'FLOW-DENIED-CP')).success);
        }
        System.runAs(actor('NoObject')) {
            System.assert(FeatureManagement.checkPermission('AEIR_Execute_Retry'));
            System.assert(!Schema.sObjectType.Error_Feedback__c.isAccessible());
            System.assertEquals(false, new AEIR_ApprovedFlowRetryHandler().retry(request(target.Id, 'FLOW-DENIED-OBJECT')).success);
        }
        System.runAs(reader) {
            System.assert(Schema.sObjectType.Error_Feedback__c.isUpdateable());
            System.assertEquals(0, [SELECT count() FROM Error_Feedback__c WHERE Id = :target.Id]);
            System.assertEquals(false, new AEIR_ApprovedFlowRetryHandler().retry(request(target.Id, 'FLOW-DENIED-RECORD')).success);
        }
        // A readable share still does not authorize the Flow to mutate this record.
        insert new Error_Feedback__Share(ParentId = target.Id, UserOrGroupId = reader.Id, AccessLevel = 'Read', RowCause = 'Manual');
        System.runAs(reader) {
            System.assertEquals(1, [SELECT count() FROM Error_Feedback__c WHERE Id = :target.Id]);
            System.assert(FeatureManagement.checkPermission('AEIR_Execute_Retry'));
            List<UserRecordAccess> nativeAccess = Database.queryWithBinds(
                'SELECT RecordId, HasEditAccess FROM UserRecordAccess WHERE UserId = :actorId AND RecordId = :targetId',
                new Map<String, Object>{'actorId' => reader.Id, 'targetId' => target.Id}, AccessLevel.SYSTEM_MODE);
            System.assertEquals(1, nativeAccess.size());
            System.assertEquals(false, nativeAccess[0].HasEditAccess,
                'Object edit permission and a read share must not confer record edit access.');
            AEIR_RetryOrchestrationService.RetryResult result =
                new AEIR_ApprovedFlowRetryHandler().retry(request(target.Id, 'FLOW-DENIED-EDIT'));
            System.assertEquals(false, result.success);
            System.assert(result.message.contains('Edit access'), result.message);
        }
        System.assertEquals(0, calls);
        Test.stopTest();
    }

    @IsTest
    static void nativeRunnerReportsMissingFlowWithoutPretendingSuccess() {
        Error_Feedback__c target = new Error_Feedback__c(Comments__c = 'Before');
        insert target;
        Retry_Handler__mdt row = registration();
        row.Flow_API_Name__c = 'AEIR_NoSuch_Approved_Recovery_Flow';
        AEIR_ApprovedFlowRetryHandler.configurationOverrides = new List<Retry_Handler__mdt>{row};
        Test.startTest();
        System.runAs(actor('Authorized')) {
            AEIR_RetryOrchestrationService.RetryResult result =
                new AEIR_ApprovedFlowRetryHandler().retry(request(target.Id, 'FLOW-MISSING'));
            System.assertEquals(false, result.success);
            System.assert(result.message.contains('failed'), result.message);
            System.assertEquals('Before', [SELECT Comments__c FROM Error_Feedback__c WHERE Id = :target.Id].Comments__c);
        }
        Test.stopTest();
    }

    @IsTest
    static void twentyApprovedTargetsHaveBoundedFrameworkReadsAndRealWrites() {
        List<Error_Feedback__c> targets = new List<Error_Feedback__c>();
        for (Integer i = 0; i < 20; i++) targets.add(new Error_Feedback__c(Comments__c = 'Before'));
        insert targets;
        configure();
        List<AEIR_RetryOrchestrationService.RetryRequest> requests = new List<AEIR_RetryOrchestrationService.RetryRequest>();
        for (Integer i = 0; i < targets.size(); i++) requests.add(request(targets[i].Id, 'FLOW-BULK-' + i));
        Test.startTest();
        System.runAs(actor('Authorized')) {
            Integer beforeQueries = Limits.getQueries();
            List<AEIR_RetryOrchestrationService.RetryResult> results = AEIR_RetryOrchestrationService.requestRetries(requests);
            Integer queryCost = Limits.getQueries() - beforeQueries;
            System.assertEquals(20, calls);
            System.assert(queryCost <= 45, 'At most two target-access reads per handler plus prefetched orchestration reads; actual=' + queryCost);
            Set<Id> audits = new Set<Id>();
            for (AEIR_RetryOrchestrationService.RetryResult result : results) {
                System.assertEquals(true, result.success, result.message);
                audits.add(result.retryAttemptId);
            }
            System.assertEquals(20, [SELECT count() FROM Retry_Attempt__c WHERE Id IN :audits AND Status__c = 'Succeeded']);
            for (Error_Feedback__c target : [SELECT Comments__c FROM Error_Feedback__c WHERE Id IN :targets]) {
                System.assert(target.Comments__c.startsWith('Recovered:'));
            }
        }
        Test.stopTest();
    }
}
