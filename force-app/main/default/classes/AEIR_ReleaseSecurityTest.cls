@IsTest
private class AEIR_ReleaseSecurityTest {
    private static final String MASK = '[MASKED]';

    @TestSetup
    static void setupUsers() {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String suffix = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 12);
        List<User> users = new List<User>();
        for (String alias : new List<String>{ 'afrelok', 'afrelnop' }) {
            users.add(new User(
                FirstName = 'Aegis', LastName = 'ReleaseSecurity', Alias = alias,
                Email = alias + '@example.invalid', Username = alias + '.' + suffix + '@example.invalid',
                ProfileId = standard.Id, TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'));
        }
        insert users;
        List<PermissionSetAssignment> grants = new List<PermissionSetAssignment>();
        for (PermissionSet permission : [SELECT Id FROM PermissionSet
                WHERE Name IN ('AEIR_Product_Admin', 'AEIR_Sample_Account_Remediation')]) {
            grants.add(new PermissionSetAssignment(AssigneeId = users[0].Id, PermissionSetId = permission.Id));
        }
        insert grants;
    }

    @IsTest
    static void nestedJsonMasksValuesAndPreservesKeysAndSafeTypes() {
        Map<String, Object> input = new Map<String, Object>{
            'password' => 'json-password-value',
            'safe' => 'Diagnostic remains useful',
            'nested' => new List<Object>{ new Map<String, Object>{
                'SessionId' => 'json-session-value', 'count' => 3, 'enabled' => true, 'missing' => null } },
            'authorization' => new Map<String, Object>{ 'bearer' => 'json-nested-auth-value' },
            'serialized' => JSON.serialize(new Map<String, Object>{ 'refresh_token' => 'json-refresh-value' })
        };
        String output = AEIR_SecuritySanitizerService.mask(JSON.serialize(input));
        Map<String, Object> sanitized = (Map<String, Object>) JSON.deserializeUntyped(output);
        System.assertEquals(input.keySet(), sanitized.keySet(), 'Mask values without renaming diagnostic keys.');
        System.assertEquals(MASK, sanitized.get('password'));
        System.assertEquals(MASK, sanitized.get('authorization'), 'Entire sensitive objects must be redacted.');
        System.assertEquals('Diagnostic remains useful', sanitized.get('safe'));
        Map<String, Object> nested = (Map<String, Object>) ((List<Object>) sanitized.get('nested'))[0];
        System.assertEquals(MASK, nested.get('SessionId'));
        System.assertEquals(Decimal.valueOf('3'), nested.get('count'));
        System.assertEquals(true, nested.get('enabled'));
        System.assertEquals(null, nested.get('missing'));
        for (String original : new List<String>{ 'json-password-value', 'json-session-value',
                'json-nested-auth-value', 'json-refresh-value' }) {
            System.assert(!output.contains(original), 'A JSON credential must never survive masking.');
        }
    }

    @IsTest
    static void builtinJsonMaskingWorksWithoutMetadataRules() {
        AEIR_SecuritySanitizerService.setSensitiveFieldsForTest(new List<Sensitive_Field__mdt>());
        Map<String, Object> input = new Map<String, Object>{
            'access_token' => 'access-value', 'client-secret' => 'client-value',
            'apiKey' => 'api-value', 'password' => 'escaped "quote" and \\slash',
            'token' => 12345, 'safe' => 'kept'
        };
        String output = AEIR_SecuritySanitizerService.mask(JSON.serialize(input));
        Map<String, Object> sanitized = (Map<String, Object>) JSON.deserializeUntyped(output);
        for (String key : input.keySet()) {
            System.assertEquals(key == 'safe' ? 'kept' : MASK, sanitized.get(key));
        }
    }

    @IsTest
    static void configuredFieldsAreLiteralAndValuePatternsStillApply() {
        AEIR_SecuritySanitizerService.setSensitiveFieldsForTest(new List<Sensitive_Field__mdt>{
            new Sensitive_Field__mdt(Field__c = 'Account.Secret[Value]__c', Active__c = true),
            new Sensitive_Field__mdt(Regex__c = 'ACCT-[0-9]{4}', Active__c = true)
        });
        String output = AEIR_SecuritySanitizerService.mask(JSON.serialize(new Map<String, Object>{
            'Account.Secret[Value]__c' => 'configured-field-value', 'reference' => 'ACCT-1234',
            'safe' => 'unchanged'
        }));
        Map<String, Object> sanitized = (Map<String, Object>) JSON.deserializeUntyped(output);
        System.assertEquals(MASK, sanitized.get('Account.Secret[Value]__c'));
        System.assertEquals(MASK, sanitized.get('reference'));
        System.assertEquals('unchanged', sanitized.get('safe'));
        System.assert(!output.contains('configured-field-value'));
        System.assert(!output.contains('ACCT-1234'));
    }

    @IsTest
    static void freeTextUrlsAndMalformedJsonDoNotBypassMasking() {
        String output = AEIR_SecuritySanitizerService.mask(
            'password="two words"; access_token=access-value; Authorization: Bearer bearer-value; '
            + 'url=https://example.invalid/path?refresh_token=url-value&state=kept; '
            + 'card=4111111111111111');
        for (String original : new List<String>{ 'two words', 'access-value', 'bearer-value',
                'url-value', '4111111111111111' }) {
            System.assert(!output.contains(original), 'Text credentials must be removed: ' + original);
        }
        System.assert(output.contains('password="[MASKED]"'), 'Retain the label and quoting.');
        System.assert(output.contains('access_token=[MASKED]'), 'Retain the token label.');
        System.assert(output.contains('Authorization: [MASKED]'), 'Retain the header name.');
        System.assert(output.contains('state=kept'), 'Safe query parameters remain useful.');
        String malformed = AEIR_SecuritySanitizerService.mask('{"password":"unfinished-value');
        System.assert(!malformed.contains('unfinished-value'), 'Broken JSON must still be sanitized.');
    }

    @IsTest
    static void invalidMaskingRegexFailsClosed() {
        AEIR_SecuritySanitizerService.setSensitiveFieldsForTest(new List<Sensitive_Field__mdt>{
            new Sensitive_Field__mdt(Field__c = 'password', Regex__c = '[invalid', Active__c = true)
        });
        System.assertEquals(MASK, AEIR_SecuritySanitizerService.mask('{"password":"sensitive-value"}'));
        System.assertEquals(MASK, AEIR_SecuritySanitizerService.mask('unstructured diagnostic evidence'));
        System.assertEquals(null, AEIR_SecuritySanitizerService.mask(null));
        System.assertEquals('', AEIR_SecuritySanitizerService.mask(''));
    }

    private static AEIR_RemediationOrchestrator.RemediationRequest requestFor(Account accountRecord) {
        AEIR_RemediationOrchestrator.RemediationRequest request = new AEIR_RemediationOrchestrator.RemediationRequest();
        request.correlationId = 'RELEASE-SECURITY';
        request.actionKey = 'UPDATE_ACCOUNT_DESCRIPTION';
        request.objectApiName = 'Account';
        request.recordId = accountRecord.Id;
        request.fieldApiName = 'Description';
        request.newValue = 'Approved correction';
        request.confirmed = true;
        return request;
    }

    private static User authorizedUser() {
        return [SELECT Id FROM User WHERE Alias = 'afrelok' LIMIT 1];
    }

    @IsTest
    static void successfulRemediationsCommitAndReleaseTheirSavepoints() {
        System.runAs(authorizedUser()) {
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
            System.assert(FeatureManagement.checkPermission('AEIR_Execute_Remediation'));
            Account accountRecord = new Account(Name = 'Release success', Description = 'Before');
            insert accountRecord;
            AEIR_RemediationOrchestrator.RemediationRequest request = requestFor(accountRecord);
            Test.startTest();
            for (Integer i = 0; i < 8; i++) {
                request.newValue = 'Approved correction ' + i;
                AEIR_RemediationOrchestrator.RemediationResult result = AEIR_RemediationOrchestrator.execute(request);
                System.assertEquals(true, result.success, result.technicalMessage);
                System.assertNotEquals(null, result.remediationActionId);
            }
            Test.stopTest();
            System.assertEquals('Approved correction 7', [SELECT Description FROM Account WHERE Id = :accountRecord.Id].Description);
            List<Remediation_Action__c> audits = [SELECT Status__c, Executed_By__c, Approved_By__c
                FROM Remediation_Action__c WHERE Target_Record_Id__c = :request.recordId];
            System.assertEquals(8, audits.size(), 'Every successful update must have an audit.');
            for (Remediation_Action__c audit : audits) {
                System.assertEquals('Executed', audit.Status__c);
                System.assertEquals(UserInfo.getUserId(), audit.Executed_By__c);
                System.assertEquals(UserInfo.getUserId(), audit.Approved_By__c);
            }
        }
    }

    @IsTest
    static void invalidAuditLookupRollsBackCustomerUpdateAndRecordsFailure() {
        System.runAs(authorizedUser()) {
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
            Account accountRecord = new Account(Name = 'Release invalid lookup', Description = 'Before');
            insert accountRecord;
            AEIR_RemediationOrchestrator.RemediationRequest request = requestFor(accountRecord);
            request.errorLogId = accountRecord.Id; // Valid Id, wrong lookup type: the audit insert must fail.
            Test.startTest();
            AEIR_RemediationOrchestrator.RemediationResult result = AEIR_RemediationOrchestrator.execute(request);
            Test.stopTest();
            System.assertEquals(false, result.success);
            System.assertEquals('Failed', result.status);
            System.assertEquals('Before', [SELECT Description FROM Account WHERE Id = :accountRecord.Id].Description,
                'A successful target update must roll back if its success audit is rejected.');
            System.assertNotEquals(null, result.remediationActionId, 'Retain a durable failure audit.');
            Remediation_Action__c audit = [SELECT Status__c, Error_Log__c, Executed_By__c, Approved_By__c
                FROM Remediation_Action__c WHERE Id = :result.remediationActionId];
            System.assertEquals('Failed', audit.Status__c);
            System.assertEquals(null, audit.Error_Log__c, 'Do not retry an invalid diagnostic reference.');
            System.assertEquals(null, audit.Executed_By__c);
            System.assertEquals(null, audit.Approved_By__c);
        }
    }

    @IsTest
    static void oversizedSuccessAuditRollsBackAndPersistsBoundedFailureAudit() {
        System.runAs(authorizedUser()) {
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
            Account accountRecord = new Account(Name = 'Release audit length', Description = 'Before');
            insert accountRecord;
            AEIR_RemediationOrchestrator.RemediationRequest request = requestFor(accountRecord);
            request.correlationId = '';
            for (Integer i = 0; i < 81; i++) request.correlationId += 'x';
            AEIR_RemediationOrchestrator.RemediationResult result = AEIR_RemediationOrchestrator.execute(request);
            System.assertEquals(false, result.success);
            System.assertEquals('Before', [SELECT Description FROM Account WHERE Id = :accountRecord.Id].Description);
            System.assertNotEquals(null, result.remediationActionId);
            Remediation_Action__c audit = [SELECT Status__c, Correlation_Id__c FROM Remediation_Action__c
                WHERE Id = :result.remediationActionId];
            System.assertEquals('Failed', audit.Status__c);
            System.assert(audit.Correlation_Id__c.length() <= 80);
        }
    }

    @IsTest
    static void customPermissionAndFeatureFlagDenyBeforeAnyWrite() {
        User noPermission = [SELECT Id FROM User WHERE Alias = 'afrelnop' LIMIT 1];
        System.runAs(noPermission) {
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
            Account accountRecord = new Account(Name = 'Release denied', Description = 'Before');
            insert accountRecord;
            Integer beforeDml = Limits.getDmlStatements();
            AEIR_RemediationOrchestrator.RemediationResult result = AEIR_RemediationOrchestrator.execute(requestFor(accountRecord));
            System.assertEquals('Denied', result.status);
            System.assertEquals(false, result.success);
            System.assertEquals(beforeDml, Limits.getDmlStatements(), 'Unauthorized execution must not write an audit or record.');
        }
        System.runAs(authorizedUser()) {
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, false);
            Account accountRecord = new Account(Name = 'Release disabled', Description = 'Before');
            insert accountRecord;
            Integer beforeDml = Limits.getDmlStatements();
            AEIR_RemediationOrchestrator.RemediationResult result = AEIR_RemediationOrchestrator.execute(requestFor(accountRecord));
            System.assertEquals('Denied', result.status);
            System.assertEquals(beforeDml, Limits.getDmlStatements());
        }
        System.assertEquals(0, [SELECT count() FROM Remediation_Action__c]);
    }

    @IsTest
    static void missingConfirmationCannotModifyCustomerRecord() {
        System.runAs(authorizedUser()) {
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
            Account accountRecord = new Account(Name = 'Release unconfirmed', Description = 'Before');
            insert accountRecord;
            AEIR_RemediationOrchestrator.RemediationRequest request = requestFor(accountRecord);
            request.confirmed = false;
            AEIR_RemediationOrchestrator.RemediationResult result = AEIR_RemediationOrchestrator.execute(request);
            System.assertEquals(false, result.success);
            System.assertEquals('Before', [SELECT Description FROM Account WHERE Id = :accountRecord.Id].Description);
            System.assertNotEquals(null, result.remediationActionId, 'Record a permitted but unconfirmed request as failed.');
        }
    }

    @IsTest
    static void insufficientDmlCapacityRefusesBeforeCustomerWrite() {
        System.runAs(authorizedUser()) {
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
            Account accountRecord = new Account(Name = 'Release budget', Description = 'Before');
            insert accountRecord;
            Test.startTest();
            // Consume real statement budget without repeatedly invoking customer automation.
            while (Limits.getDmlStatements() < 144) {
                Savepoint budget = Database.setSavepoint();
                Database.releaseSavepoint(budget);
            }
            Savepoint callerBoundary = Database.setSavepoint();
            Integer beforeDml = Limits.getDmlStatements();
            System.assertEquals(5, Limits.getLimitDmlStatements() - beforeDml,
                'Five remaining statements cannot guarantee rollback, release, and a failed audit.');
            AEIR_RemediationOrchestrator.RemediationResult result = AEIR_RemediationOrchestrator.execute(requestFor(accountRecord));
            System.assertEquals('Denied', result.status);
            System.assertEquals(beforeDml, Limits.getDmlStatements(), 'Capacity refusal must precede every write.');
            Database.releaseSavepoint(callerBoundary);
            Test.stopTest();
            System.assertEquals('Before', [SELECT Description FROM Account WHERE Id = :accountRecord.Id].Description);
        }
    }

    @IsTest
    static void sixReservedStatementsCanRollbackAndPersistFailureAudit() {
        System.runAs(authorizedUser()) {
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
            // Use a package-owned object so unrelated customer Account triggers do not
            // add their own DML to the framework's six-statement rollback budget.
            Error_Feedback__c customRecord = new Error_Feedback__c(Comments__c = 'Before');
            insert customRecord;
            String objectName = Error_Feedback__c.SObjectType.getDescribe().getName();
            String fieldName = Error_Feedback__c.Comments__c.getDescribe().getName();
            AEIR_RemediationOrchestrator.actionOverrides = new Map<String, Remediation_Action_Setting__mdt>{
                'TEST_RELEASE_CUSTOM' => new Remediation_Action_Setting__mdt(Active__c = true,
                    Requires_Confirmation__c = true, Object__c = objectName, Field__c = fieldName)
            };
            AEIR_RemediationOrchestrator.RemediationRequest request = new AEIR_RemediationOrchestrator.RemediationRequest();
            request.actionKey = 'TEST_RELEASE_CUSTOM';
            request.objectApiName = objectName;
            request.fieldApiName = fieldName;
            request.recordId = customRecord.Id;
            request.newValue = 'Approved custom-object correction';
            request.confirmed = true;
            request.errorLogId = customRecord.Id; // Force the success audit's lookup validation to fail.
            Test.startTest();
            while (Limits.getDmlStatements() < 144) {
                Savepoint budget = Database.setSavepoint();
                Database.releaseSavepoint(budget);
            }
            System.assertEquals(6, Limits.getLimitDmlStatements() - Limits.getDmlStatements());
            AEIR_RemediationOrchestrator.RemediationResult result = AEIR_RemediationOrchestrator.execute(request);
            System.assertEquals('Failed', result.status);
            System.assertNotEquals(null, result.remediationActionId,
                'The reserved budget must cover rollback, release, and durable failure evidence.');
            System.assertEquals('Before', [SELECT Comments__c FROM Error_Feedback__c WHERE Id = :customRecord.Id].Comments__c);
            System.assertEquals('Failed', [SELECT Status__c FROM Remediation_Action__c
                WHERE Id = :result.remediationActionId].Status__c);
            Test.stopTest();
        }
    }

    @IsTest
    static void configuredSensitiveFieldsNeverExposeBeforeOrAfterAuditValues() {
        System.runAs(authorizedUser()) {
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
            String objectName = Error_Feedback__c.SObjectType.getDescribe().getName();
            String fieldName = Error_Feedback__c.Comments__c.getDescribe().getName();
            AEIR_SecuritySanitizerService.setSensitiveFieldsForTest(new List<Sensitive_Field__mdt>{
                new Sensitive_Field__mdt(Active__c = true, Field__c = fieldName)
            });
            AEIR_RemediationOrchestrator.actionOverrides = new Map<String, Remediation_Action_Setting__mdt>{
                'TEST_SENSITIVE_COMMENTS' => new Remediation_Action_Setting__mdt(Active__c = true,
                    Requires_Confirmation__c = true, Object__c = objectName, Field__c = fieldName)
            };
            Error_Feedback__c customRecord = new Error_Feedback__c(Comments__c = 'PLAIN_BEFORE_SENTINEL');
            insert customRecord;
            AEIR_RemediationOrchestrator.RemediationRequest request = new AEIR_RemediationOrchestrator.RemediationRequest();
            request.actionKey = 'TEST_SENSITIVE_COMMENTS'; request.objectApiName = objectName;
            request.fieldApiName = fieldName; request.recordId = customRecord.Id;
            request.newValue = 'PLAIN_AFTER_SENTINEL'; request.confirmed = true;
            AEIR_RemediationOrchestrator.RemediationResult result = AEIR_RemediationOrchestrator.execute(request);
            System.assertEquals(true, result.success, result.technicalMessage);
            System.assertEquals('PLAIN_AFTER_SENTINEL', [SELECT Comments__c FROM Error_Feedback__c
                WHERE Id = :customRecord.Id].Comments__c, 'Apply the approved business value without changing its contents.');
            Remediation_Action__c audit = [SELECT Before_Value__c, After_Value__c, Status__c FROM Remediation_Action__c
                WHERE Id = :result.remediationActionId];
            System.assertEquals(MASK, audit.Before_Value__c);
            System.assertEquals(MASK, audit.After_Value__c);
            String evidence = JSON.serialize(audit);
            System.assert(!evidence.contains('PLAIN_BEFORE_SENTINEL'));
            System.assert(!evidence.contains('PLAIN_AFTER_SENTINEL'));
        }
    }

    @IsTest
    static void booleanCorrectionsRejectInvalidTextBeforeChangingCustomerData() {
        System.runAs(authorizedUser()) {
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
            String objectName = Error_Feedback__c.SObjectType.getDescribe().getName();
            String fieldName = Error_Feedback__c.Helpful__c.getDescribe().getName();
            AEIR_RemediationOrchestrator.actionOverrides = new Map<String, Remediation_Action_Setting__mdt>{
                'TEST_BOOLEAN' => new Remediation_Action_Setting__mdt(Active__c = true,
                    Requires_Confirmation__c = true, Object__c = objectName, Field__c = fieldName)
            };
            Error_Feedback__c customRecord = new Error_Feedback__c(Helpful__c = true);
            insert customRecord;
            AEIR_RemediationOrchestrator.RemediationRequest request = new AEIR_RemediationOrchestrator.RemediationRequest();
            request.actionKey = 'TEST_BOOLEAN'; request.objectApiName = objectName;
            request.fieldApiName = fieldName; request.recordId = customRecord.Id; request.confirmed = true;
            for (String invalid : new List<String>{ 'not-a-boolean', '1', '', null }) {
                request.newValue = invalid;
                AEIR_RemediationOrchestrator.RemediationResult result = AEIR_RemediationOrchestrator.execute(request);
                System.assertEquals(false, result.success);
                System.assertEquals('Failed', result.status);
                System.assertEquals('A Boolean value must be true or false.', result.technicalMessage);
                System.assertEquals(true, [SELECT Helpful__c FROM Error_Feedback__c WHERE Id = :customRecord.Id].Helpful__c,
                    'Malformed Boolean input must not silently turn an existing true value into false.');
            }
            request.newValue = 'false';
            System.assertEquals(true, AEIR_RemediationOrchestrator.execute(request).success);
            System.assertEquals(false, [SELECT Helpful__c FROM Error_Feedback__c WHERE Id = :customRecord.Id].Helpful__c);
            request.newValue = 'TRUE';
            System.assertEquals(true, AEIR_RemediationOrchestrator.execute(request).success);
            System.assertEquals(true, [SELECT Helpful__c FROM Error_Feedback__c WHERE Id = :customRecord.Id].Helpful__c);
        }
    }
}
