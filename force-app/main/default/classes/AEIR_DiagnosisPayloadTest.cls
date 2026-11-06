@IsTest
private class AEIR_DiagnosisPayloadTest {
    @TestSetup
    static void setupReaders() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        List<User> users = new List<User>();
        String uniquePart = UserInfo.getOrganizationId() + '.' + Datetime.now().getTime();
        for (Integer i = 0; i < 3; i++) {
            users.add(new User(LastName = 'Aegis Diagnosis Payload', Alias = 'aegdp' + i,
                Email = 'diagnosis.' + i + '@example.invalid', Username = 'diagnosis.' + uniquePart + '.' + i + '@example.invalid',
                ProfileId = standardProfile.Id, TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'));
        }
        insert users;
        Id endUserRole = [SELECT Id FROM PermissionSet WHERE Name = 'AEIR_End_User' LIMIT 1].Id;
        Id integrationRole = [SELECT Id FROM PermissionSet WHERE Name = 'AEIR_Integration_User' LIMIT 1].Id;
        PermissionSet sensitiveOnly = new PermissionSet(Name = 'Aegis_Diagnosis_Sensitive_Test', Label = 'Aegis Diagnosis Sensitive Test');
        insert sensitiveOnly;
        Id sensitivePermission = [SELECT Id FROM CustomPermission WHERE DeveloperName = 'AEIR_View_Sensitive_Context' LIMIT 1].Id;
        insert new SetupEntityAccess(ParentId = sensitiveOnly.Id, SetupEntityId = sensitivePermission);
        // Check-only validation can retain the native permission-set's old custom
        // permission cache. Materialize only its exact declared capability in a new,
        // tab-free fixture role; Integration_User still supplies all data access.
        Id processorPermission = [SELECT Id FROM CustomPermission WHERE DeveloperName = 'AEIR_Process_Diagnostics' LIMIT 1].Id;
        PermissionSet processorCapability = new PermissionSet(Name = 'Aegis_Diagnosis_Processor_Test', Label = 'Aegis Diagnosis Processor Test');
        insert processorCapability;
        insert new SetupEntityAccess(ParentId = processorCapability.Id, SetupEntityId = processorPermission);
        List<ObjectPermissions> processorVisibility = new List<ObjectPermissions>();
        for (String objectName : new List<String>{'Error_Log__c', 'Diagnostic_Session__c', 'AI_Diagnosis__c'}) {
            processorVisibility.add(new ObjectPermissions(ParentId = processorCapability.Id, SObjectType = objectName,
                PermissionsRead = true, PermissionsViewAllRecords = true, PermissionsModifyAllRecords = false));
        }
        insert processorVisibility;
        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(AssigneeId = users[0].Id, PermissionSetId = endUserRole),
            new PermissionSetAssignment(AssigneeId = users[1].Id, PermissionSetId = endUserRole),
            new PermissionSetAssignment(AssigneeId = users[1].Id, PermissionSetId = sensitiveOnly.Id),
            new PermissionSetAssignment(AssigneeId = users[2].Id, PermissionSetId = integrationRole),
            new PermissionSetAssignment(AssigneeId = users[2].Id, PermissionSetId = processorCapability.Id)
        };
        Id foreignUserId = UserInfo.getUserId();
        // Test-setup data is committed before the callout tests. This avoids using
        // a fake transport bypass for uncommitted fixture DML in direct job tests.
        System.runAs(users[0]) {
            disableOptionalWork();
            Error_Log__c ownLog = errorFor(users[0].Id, 'DIAGNOSIS-JOB-OWN', false);
            Database.insert(ownLog, AccessLevel.SYSTEM_MODE);
            AEIR_AgentforceGatewayService.diagnoseError(ownLog.Id);
            Error_Log__c foreignLog = errorFor(users[0].Id, 'DIAGNOSIS-JOB-FOREIGN', false);
            foreignLog.User__c = foreignUserId;
            Database.insert(foreignLog, AccessLevel.SYSTEM_MODE);
            Database.insert(new List<AI_Diagnosis__c>{
                new AI_Diagnosis__c(OwnerId = users[0].Id, Error_Log__c = foreignLog.Id,
                    Correlation_Id__c = 'DIAGNOSIS-JOB-FOREIGN', Summary__c = 'Foreign parent fallback',
                    Agent_Status__c = 'Deterministic Fallback', Input_Payload_JSON__c = '{}', Output_JSON__c = '{}'),
                new AI_Diagnosis__c(OwnerId = users[0].Id, Correlation_Id__c = 'DIAGNOSIS-JOB-ORPHAN',
                    Summary__c = 'Orphan fallback', Agent_Status__c = 'Deterministic Fallback',
                    Input_Payload_JSON__c = '{}', Output_JSON__c = '{}')
            }, true, AccessLevel.SYSTEM_MODE);
        }
    }

    private static User reader(Integer index) {
        String alias = 'aegdp' + index;
        return [SELECT Id FROM User WHERE Alias = :alias AND LastName = 'Aegis Diagnosis Payload' LIMIT 1];
    }
    private static void disableOptionalWork() {
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.USER_NOTIFICATIONS, false);
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AI_DIAGNOSIS, false);
    }
    private static String denseText(Integer maximum) {
        String unit = '"\\' + '\n' + '\t' + '漢🙂';
        String value = unit;
        while (value.length() < maximum) value += value;
        Integer completeUnits = maximum / unit.length();
        return value.substring(0, completeUnits * unit.length());
    }
    private static Error_Log__c errorFor(Id userId, String correlation, Boolean large) {
        String detail = large ? denseText(32600) : 'AccountId is required.';
        String context = large ? JSON.serialize(new Map<String, Object>{'observations' => denseText(12000)})
            : '{"password":"DIAGNOSIS-DO-NOT-SEND","operation":"save"}';
        return new Error_Log__c(OwnerId = userId, User__c = userId, Correlation_Id__c = correlation,
            Source_Type__c = 'Flow', Source_Name__c = 'Business process', Object_API_Name__c = 'Account',
            Original_Error_Message__c = 'REQUIRED_FIELD_MISSING: ' + detail,
            Normalized_Message__c = large ? denseText(32760) : 'A required value is missing.',
            Context_JSON__c = context, Error_Category__c = 'Missing Data', Severity__c = 'Medium', Status__c = 'New');
    }
    private static void assertJsonFits(AI_Diagnosis__c diagnosis) {
        System.assert(diagnosis.Input_Payload_JSON__c.length() <= AI_Diagnosis__c.Input_Payload_JSON__c.getDescribe().getLength());
        System.assert(diagnosis.Input_Payload_JSON__c.length() <= 12000, 'Stored input must also fit the optional transport.');
        System.assert(AEIR_SecuritySanitizerService.mask(diagnosis.Input_Payload_JSON__c).length() <= 12000,
            'Transport re-sanitization must remain within its input contract.');
        System.assert(diagnosis.Output_JSON__c.length() <= AI_Diagnosis__c.Output_JSON__c.getDescribe().getLength());
        System.assert(JSON.deserializeUntyped(diagnosis.Input_Payload_JSON__c) instanceof Map<String, Object>);
        System.assert(JSON.deserializeUntyped(diagnosis.Output_JSON__c) instanceof Map<String, Object>);
        System.assert(diagnosis.Summary__c.length() <= AI_Diagnosis__c.Summary__c.getDescribe().getLength());
        System.assert(diagnosis.Root_Cause__c.length() <= AI_Diagnosis__c.Root_Cause__c.getDescribe().getLength());
        System.assert(diagnosis.Recommended_Action__c.length() <= AI_Diagnosis__c.Recommended_Action__c.getDescribe().getLength());
    }

    @IsTest
    static void largeEscapedUnicodeEvidenceProducesBoundedValidJsonWithoutChangingTheCapture() {
        disableOptionalWork();
        Error_Log__c log = errorFor(UserInfo.getUserId(), 'DIAGNOSIS-LARGE-ONE', true);
        insert log;
        String originalMessage = log.Original_Error_Message__c;
        String originalContext = log.Context_JSON__c;
        AEIR_AgentforceGatewayService.DiagnosisResult result = AEIR_AgentforceGatewayService.diagnoseError(log.Id);
        System.assertNotEquals(null, result.diagnosisId);
        System.assertEquals('USER_FIXABLE', result.fixability);
        AI_Diagnosis__c diagnosis = [SELECT Input_Payload_JSON__c, Output_JSON__c, Summary__c, Root_Cause__c,
            Recommended_Action__c, Fixability__c FROM AI_Diagnosis__c WHERE Id = :result.diagnosisId];
        assertJsonFits(diagnosis);
        Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(diagnosis.Input_Payload_JSON__c);
        Map<String, Object> output = (Map<String, Object>) JSON.deserializeUntyped(diagnosis.Output_JSON__c);
        System.assertEquals('DIAGNOSIS-LARGE-ONE', input.get('correlationId'));
        System.assertEquals(String.valueOf(log.Id), input.get('errorLogId'));
        System.assertEquals('Missing Data', input.get('errorCategory'));
        System.assert(((List<Object>) input.get('omittedEvidenceFields')).contains('context'));
        System.assert(((List<Object>) input.get('truncatedEvidenceFields')).contains('originalMessage'));
        System.assert(((List<Object>) output.get('truncatedFields')).contains('summary'));
        System.assertEquals('USER_FIXABLE', output.get('fixability'));
        System.assertEquals(true, output.get('fullValuesRetainedInDiagnosisFields'));
        System.assertEquals(result.summary, diagnosis.Summary__c);
        Error_Log__c retained = [SELECT Original_Error_Message__c, Context_JSON__c, Status__c FROM Error_Log__c WHERE Id = :log.Id];
        System.assertEquals(originalMessage, retained.Original_Error_Message__c);
        System.assertEquals(originalContext, retained.Context_JSON__c);
        System.assertEquals('Diagnosed', retained.Status__c);
    }

    @IsTest
    static void mixedBulkSmallAndLargeEvidenceDiagnosesEveryItemAndPreservesClassification() {
        disableOptionalWork();
        List<Error_Log__c> logs = new List<Error_Log__c>();
        for (Integer i = 0; i < 6; i++) {
            Error_Log__c log = errorFor(UserInfo.getUserId(), 'DIAGNOSIS-BULK-' + i, i < 2);
            log.Object_API_Name__c = i == 0 ? 'Opportunity' : i == 1 ? 'Case' : 'Incident__c';
            if (i < 2) {
                log.Original_Error_Message__c = 'UNABLE_TO_LOCK_ROW: ' + denseText(32600);
                log.Error_Category__c = 'Locking';
                log.Retry_Eligible__c = true;
            }
            logs.add(log);
        }
        insert logs;
        Map<Id, Error_Log__c> sourceById = new Map<Id, Error_Log__c>(logs);
        Map<Id, AEIR_AgentforceGatewayService.DiagnosisResult> results =
            AEIR_AgentforceGatewayService.diagnoseErrors(new List<Id>(sourceById.keySet()));
        System.assertEquals(6, results.size());
        List<AI_Diagnosis__c> diagnoses = [SELECT Error_Log__c, Input_Payload_JSON__c, Output_JSON__c,
            Summary__c, Root_Cause__c, Recommended_Action__c FROM AI_Diagnosis__c WHERE Error_Log__c IN :sourceById.keySet()];
        System.assertEquals(6, diagnoses.size(), 'A large item must not discard small siblings in the same batch.');
        for (AI_Diagnosis__c diagnosis : diagnoses) {
            assertJsonFits(diagnosis);
            String expected = sourceById.get(diagnosis.Error_Log__c).Retry_Eligible__c == true ? 'RETRYABLE' : 'USER_FIXABLE';
            System.assertEquals(expected, results.get(diagnosis.Error_Log__c).fixability);
            System.assert(!diagnosis.Input_Payload_JSON__c.contains('DIAGNOSIS-DO-NOT-SEND'), 'Sanitize optional outbound context.');
        }
        for (Error_Log__c retained : [SELECT Id, Original_Error_Message__c, Context_JSON__c, Status__c FROM Error_Log__c WHERE Id IN :sourceById.keySet()]) {
            System.assertEquals(sourceById.get(retained.Id).Original_Error_Message__c, retained.Original_Error_Message__c);
            System.assertEquals(sourceById.get(retained.Id).Context_JSON__c, retained.Context_JSON__c);
            System.assertEquals('Diagnosed', retained.Status__c);
        }
    }

    @IsTest
    static void largeManualContextKeepsTheOriginalDescriptionAndAUsableBoundedInput() {
        disableOptionalWork();
        Diagnostic_Session__c session = new Diagnostic_Session__c(User__c = UserInfo.getUserId(),
            Correlation_Id__c = 'DIAGNOSIS-LARGE-MANUAL', User_Description__c = denseText(32760), Resolution_Status__c = 'Open');
        insert session;
        AEIR_AgentforceGatewayService.DiagnosisResult result = AEIR_AgentforceGatewayService.diagnoseSession(session.Id);
        AI_Diagnosis__c diagnosis = [SELECT Input_Payload_JSON__c, Output_JSON__c, Summary__c, Root_Cause__c,
            Recommended_Action__c FROM AI_Diagnosis__c WHERE Id = :result.diagnosisId];
        assertJsonFits(diagnosis);
        Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(diagnosis.Input_Payload_JSON__c);
        System.assertEquals(String.valueOf(session.Id), input.get('diagnosticSessionId'));
        System.assert(((List<Object>) input.get('truncatedEvidenceFields')).contains('userDescription'));
        Diagnostic_Session__c retained = [SELECT User_Description__c, Agent_Response__c, Resolution_Status__c FROM Diagnostic_Session__c WHERE Id = :session.Id];
        System.assertEquals(session.User_Description__c, retained.User_Description__c);
        System.assertEquals('Pending User', retained.Resolution_Status__c);
        System.assert(retained.Agent_Response__c.length() <= Diagnostic_Session__c.Agent_Response__c.getDescribe().getLength());
    }

    @IsTest
    static void endUserCanDiagnoseOwnEvidenceWithoutArbitraryAiRecordWriteRights() {
        User owner = reader(0);
        Error_Log__c log = errorFor(owner.Id, 'DIAGNOSIS-ENDUSER-ERROR', false);
        log.Original_Error_Message__c += ' PRIVATE_TECHNICAL_SENTINEL';
        insert log;
        Diagnostic_Session__c session = new Diagnostic_Session__c(OwnerId = owner.Id, User__c = owner.Id,
            Correlation_Id__c = 'DIAGNOSIS-ENDUSER-SESSION', User_Description__c = 'I could not save the record.', Resolution_Status__c = 'Open');
        insert session;
        System.runAs(owner) {
            disableOptionalWork();
            System.assertEquals(false, AI_Diagnosis__c.SObjectType.getDescribe().isCreateable());
            System.assertEquals(false, AI_Diagnosis__c.SObjectType.getDescribe().isUpdateable());
            System.assertEquals(false, Error_Log__c.SObjectType.getDescribe().isUpdateable());
            AEIR_AgentforceGatewayService.DiagnosisResult errorResult = AEIR_AgentforceGatewayService.diagnoseError(log.Id);
            AEIR_AgentforceGatewayService.DiagnosisResult sessionResult = AEIR_HelpMeController.diagnoseSession(session.Id);
            System.assertNotEquals(null, errorResult.diagnosisId);
            System.assertNotEquals(null, sessionResult.diagnosisId);
            System.assertEquals('USER_FIXABLE', errorResult.fixability);
            System.assert(!JSON.serialize(errorResult).contains('PRIVATE_TECHNICAL_SENTINEL'));
            System.assertEquals('Diagnosed', [SELECT Status__c FROM Error_Log__c WHERE Id = :log.Id].Status__c);
            System.assertEquals('Pending User', [SELECT Resolution_Status__c FROM Diagnostic_Session__c WHERE Id = :session.Id].Resolution_Status__c);
        }
    }

    @IsTest
    static void sharedForeignEvidenceStillNeedsTheSensitiveRole() {
        User owner = reader(0);
        Error_Log__c foreign = errorFor(owner.Id, 'DIAGNOSIS-FOREIGN-SHARED', false);
        foreign.User__c = UserInfo.getUserId();
        insert foreign;
        Diagnostic_Session__c session = new Diagnostic_Session__c(OwnerId = owner.Id, User__c = UserInfo.getUserId(),
            Correlation_Id__c = 'DIAGNOSIS-FOREIGN-SESSION', Resolution_Status__c = 'Open');
        insert session;
        System.runAs(owner) {
            disableOptionalWork();
            System.assertEquals(false, FeatureManagement.checkPermission('AEIR_View_Sensitive_Context'));
            System.assertEquals(1, [SELECT count() FROM Error_Log__c WHERE Id = :foreign.Id WITH USER_MODE], 'Sharing alone must not imply diagnostic attribution.');
            System.assertEquals(null, AEIR_AgentforceGatewayService.diagnoseError(foreign.Id));
            System.assertEquals(null, AEIR_AgentforceGatewayService.diagnoseSession(session.Id));
        }
        System.assertEquals(0, [SELECT count() FROM AI_Diagnosis__c WHERE Error_Log__c = :foreign.Id OR Diagnostic_Session__c = :session.Id]);
    }

    @IsTest
    static void sensitiveRoleAlsoRequiresSharingAndMapsEverySessionLinkedToAnAuthorizedError() {
        User support = reader(1);
        Error_Log__c hidden = errorFor(UserInfo.getUserId(), 'DIAGNOSIS-PRIVATE', false);
        Error_Log__c visible = errorFor(support.Id, 'DIAGNOSIS-SENSITIVE-VISIBLE', false);
        visible.User__c = UserInfo.getUserId();
        insert new List<Error_Log__c>{hidden, visible};
        List<Diagnostic_Session__c> sessions = new List<Diagnostic_Session__c>();
        for (Integer i = 0; i < 2; i++) {
            sessions.add(new Diagnostic_Session__c(OwnerId = support.Id, User__c = support.Id,
                Correlation_Id__c = 'DIAGNOSIS-LINK-' + i, Recent_Error_Log__c = visible.Id, Resolution_Status__c = 'Open'));
        }
        insert sessions;
        System.runAs(support) {
            disableOptionalWork();
            System.assertEquals(true, FeatureManagement.checkPermission('AEIR_View_Sensitive_Context'));
            System.assertEquals(null, AEIR_AgentforceGatewayService.diagnoseError(hidden.Id), 'Sensitive permission does not bypass sharing.');
            Map<Id, AEIR_AgentforceGatewayService.DiagnosisResult> results = AEIR_AgentforceGatewayService.diagnoseSessions(new List<Id>{sessions[0].Id, sessions[1].Id});
            System.assertEquals(2, results.size(), 'Both sessions linked to one error must receive their result.');
            System.assertNotEquals(null, results.get(sessions[0].Id).diagnosisId);
            System.assertEquals(results.get(sessions[0].Id).diagnosisId, results.get(sessions[1].Id).diagnosisId);
        }
    }

    private class EnrichmentMock implements HttpCalloutMock {
        Integer calls = 0;
        public HttpResponse respond(HttpRequest request) {
            calls++;
            System.assert(request.getEndpoint().startsWith('callout:aegis__Diagnostic_Agent/einstein/ai-agent/v1/'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            if (request.getEndpoint().endsWith('/sessions')) {
                response.setBody('{"sessionId":"00000000-0000-4000-8000-000000000001"}');
            } else if (request.getMethod() == 'DELETE') {
                response.setBody('{"messages":[]}');
            } else {
                System.assert(!request.getBody().contains('DIAGNOSIS-DO-NOT-SEND'));
                response.setBody(JSON.serialize(new Map<String, Object>{'messages' => new List<Object>{
                    new Map<String, Object>{'type' => 'Inform', 'isContentSafe' => true, 'result' => new List<Object>(),
                        'message' => JSON.serialize(new Map<String, Object>{
                            'summary' => 'Agent reviewed the required field issue.',
                            'rootCause' => 'A required relationship was not supplied.',
                            'fixability' => 'USER_FIXABLE', 'confidence' => 88,
                            'recommendedAction' => 'Ask the user to select the required relationship.',
                            'needsUserInput' => true, 'escalationRequired' => false, 'safeRemediationActionKey' => null
                        })}
                }}));
            }
            return response;
        }
    }
    private static EnrichmentMock enableMockEnrichment() {
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AI_DIAGNOSIS, true);
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.USER_NOTIFICATIONS, false);
        AEIR_AgentforceClient.connectionOverride = new Agent_Connection__mdt(Active__c = true,
            Named_Credential__c = 'aegis__Diagnostic_Agent', Agent_Id__c = '0Xx000000000001', Timeout_Milliseconds__c = 15000);
        EnrichmentMock mock = new EnrichmentMock();
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    @IsTest
    static void endUserOptionalJobReadsOnlyAuthorizedEvidenceAndPersistsCuratedResults() {
        User owner = reader(0);
        Id diagnosisId;
        Test.startTest();
        System.runAs(owner) {
            System.assertEquals(false, AI_Diagnosis__c.SObjectType.getDescribe().isUpdateable());
            AI_Diagnosis__c diagnosis = [SELECT Id, Error_Log__c, Agent_Status__c FROM AI_Diagnosis__c WHERE Correlation_Id__c = 'DIAGNOSIS-JOB-OWN' LIMIT 1];
            diagnosisId = diagnosis.Id;
            System.assertNotEquals(null, diagnosis.Error_Log__c);
            System.assert(AEIR_AgentforceGatewayService.authorizedErrors(new List<Id>{diagnosis.Error_Log__c}).contains(diagnosis.Error_Log__c),
                'The end user must own and read the stored diagnosis parent.');
            System.assertNotEquals('Completed', diagnosis.Agent_Status__c, 'The stored fixture must still require enrichment.');
            enableMockEnrichment();
            System.assertEquals(true, AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.AI_DIAGNOSIS));
            System.assertNotEquals(null, AEIR_AgentforceClient.configuredConnection());
            Integer callsBefore = Limits.getCallouts();
            new AEIR_AgentforceDiagnosisJob(new List<Id>{diagnosis.Id}).execute(null);
            List<AI_Diagnosis__c> audit = Database.queryWithBinds(
                'SELECT Agent_Status__c, Output_JSON__c FROM AI_Diagnosis__c WHERE Id = :diagnosisId',
                new Map<String, Object>{'diagnosisId' => diagnosis.Id}, AccessLevel.SYSTEM_MODE);
            System.assertEquals(3, Limits.getCallouts() - callsBefore,
                'Execute start/message/cleanup; actual stored outcome: ' + audit[0].Agent_Status__c + ' ' + audit[0].Output_JSON__c);
            System.assertEquals('Completed', [SELECT Agent_Status__c FROM AI_Diagnosis__c WHERE Id = :diagnosis.Id].Agent_Status__c);
        }
        Test.stopTest();
        AI_Diagnosis__c stored = [SELECT Agent_Status__c, Summary__c, Output_JSON__c FROM AI_Diagnosis__c WHERE Id = :diagnosisId];
        System.assertEquals('Completed', stored.Agent_Status__c);
        System.assertEquals('Agent reviewed the required field issue.', stored.Summary__c);
        System.assertEquals('COMPLETED', ((Map<String, Object>) JSON.deserializeUntyped(stored.Output_JSON__c)).get('agentAttemptStatus'));
        System.assertEquals('COMPLETED', ((Map<String, Object>) JSON.deserializeUntyped(stored.Output_JSON__c)).get('sessionCleanupStatus'));
        System.assertEquals('Completed', [SELECT Agentforce_Status__c FROM Error_Log__c WHERE Correlation_Id__c = 'DIAGNOSIS-JOB-OWN' LIMIT 1].Agentforce_Status__c);
    }

    @IsTest
    static void endUserOptionalJobCannotEnrichForeignParentsOrOrphanRecords() {
        Test.startTest();
        System.runAs(reader(0)) {
            enableMockEnrichment();
            List<AI_Diagnosis__c> rows = [SELECT Id, Agent_Status__c FROM AI_Diagnosis__c
                WHERE Correlation_Id__c IN ('DIAGNOSIS-JOB-FOREIGN', 'DIAGNOSIS-JOB-ORPHAN')];
            System.assertEquals(2, rows.size(), 'The test caller can read both diagnosis records under sharing.');
            Integer callsBefore = Limits.getCallouts();
            new AEIR_AgentforceDiagnosisJob(new List<Id>{rows[0].Id, rows[1].Id}).execute(null);
            System.assertEquals(callsBefore, Limits.getCallouts(), 'Parent authority is required before technical reads or callouts.');
            Set<Id> rowIds = new Map<Id, AI_Diagnosis__c>(rows).keySet();
            for (AI_Diagnosis__c stored : [SELECT Agent_Status__c FROM AI_Diagnosis__c WHERE Id IN :rowIds]) {
                System.assertEquals('Deterministic Fallback', stored.Agent_Status__c);
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void nativeProcessorCanDiagnoseVisibleForeignEvidenceWithoutSensitiveContextExport() {
        User processor = reader(2);
        Error_Log__c log = errorFor(processor.Id, 'DIAGNOSIS-NATIVE-PROCESSOR', false);
        log.User__c = reader(0).Id;
        insert log;
        Test.startTest();
        System.runAs(processor) {
            disableOptionalWork();
            System.assertEquals(true, FeatureManagement.checkPermission('AEIR_Process_Diagnostics'));
            System.assertEquals(false, FeatureManagement.checkPermission('AEIR_View_Sensitive_Context'));
            AEIR_AgentforceGatewayService.DiagnosisResult result = AEIR_AgentforceGatewayService.diagnoseError(log.Id);
            System.assertNotEquals(null, result.diagnosisId);
            System.assertEquals('USER_FIXABLE', result.fixability);
            AEIR_GetErrorContextAction.Request request = new AEIR_GetErrorContextAction.Request();
            request.errorLogId = String.valueOf(log.Id);
            AEIR_GetErrorContextAction.Response context = AEIR_GetErrorContextAction.run(new List<AEIR_GetErrorContextAction.Request>{request})[0];
            System.assertEquals(null, context.contextJson, 'Processing authority must not grant foreign sensitive-context export.');
        }
        Test.stopTest();
    }

    @IsTest
    static void integrationProducedDiagnosisRemainsReadableByTheAffectedParentOwner() {
        User affected = reader(0);
        User processor = reader(2);
        Error_Log__c log = errorFor(affected.Id, 'DIAGNOSIS-OWNER-CONTINUITY', false);
        insert log;
        Id diagnosisId;
        Test.startTest();
        System.runAs(processor) {
            enableMockEnrichment();
            System.assertEquals(true, FeatureManagement.checkPermission('AEIR_Process_Diagnostics'));
            System.assertEquals(1, [SELECT count() FROM Error_Log__c WHERE Id = :log.Id WITH USER_MODE],
                'The native processor role must have the source-defined visible-parent access.');
            Database.SaveResult rawLogWrite = Database.update(new Error_Log__c(Id = log.Id, Status__c = 'Escalated'), false, AccessLevel.USER_MODE);
            System.assertEquals(false, rawLogWrite.isSuccess(), 'Read All must not grant arbitrary writes to affected-user evidence.');
            Integer jobsBefore = Limits.getQueueableJobs();
            AEIR_AgentforceGatewayService.DiagnosisResult result = AEIR_AgentforceGatewayService.diagnoseError(log.Id);
            System.assertNotEquals(null, result, 'The native processing capability and visible parent must admit diagnosis.');
            diagnosisId = result.diagnosisId;
            System.assertNotEquals(null, diagnosisId);
            System.assertEquals(jobsBefore + 1, Limits.getQueueableJobs(), 'The native runtime role must admit optional enrichment.');
            System.assertEquals('Invoked', [SELECT Agent_Status__c FROM AI_Diagnosis__c
                WHERE Id = :diagnosisId WITH USER_MODE].Agent_Status__c,
                'The processor must persist the queued audit while diagnosis ownership remains with the affected user.');
            Database.SaveResult rawDiagnosisWrite = Database.update(new AI_Diagnosis__c(Id = diagnosisId,
                Summary__c = 'Unauthorized direct change'), false, AccessLevel.USER_MODE);
            System.assertEquals(false, rawDiagnosisWrite.isSuccess(), 'Only the curated workflow may update another owner\'s diagnosis.');
        }
        System.runAs(affected) {
            AI_Diagnosis__c diagnosis = [SELECT Id, OwnerId, Summary__c FROM AI_Diagnosis__c
                WHERE Id = :diagnosisId WITH USER_MODE];
            System.assertEquals(affected.Id, diagnosis.OwnerId);
            System.assertNotEquals(null, diagnosis.Summary__c);
            AEIR_UserNotificationService.DetailDTO details = AEIR_UserNotificationService.getAlertDetails(log.Correlation_Id__c);
            System.assertNotEquals(null, details.diagnosis, 'Canonical alert details must retain the asynchronously produced diagnosis.');
            System.assertEquals(diagnosisId, details.diagnosis.Id);
        }
        Test.stopTest();
    }

    private static void whitelistFeedbackComments() {
        AEIR_ContextSnapshotService.configurationOverrides = new Map<String, List<Context_Field_Setting__mdt>>{
            'Error_Feedback__c' => new List<Context_Field_Setting__mdt>{new Context_Field_Setting__mdt(
                Object__c = 'Error_Feedback__c', Field_API_Name__c = 'Comments__c',
                Active__c = true, Include_In_Agent__c = true, Include_In_Escalation__c = false)}
        };
    }

    @IsTest
    static void backgroundProcessorCannotAddItsPrivateBusinessSnapshotToAnotherUsersReport() {
        disableOptionalWork();
        whitelistFeedbackComments();
        User affected = reader(0), support = reader(1);
        String privateValue = 'SUPPORT-PRIVATE-BUSINESS-VALUE';
        Error_Feedback__c businessRecord = new Error_Feedback__c(OwnerId = support.Id, Comments__c = privateValue);
        insert businessRecord;
        Error_Log__c reported = errorFor(affected.Id, 'DIAGNOSIS-PRIVATE-BUSINESS', false);
        reported.Object_API_Name__c = 'Error_Feedback__c';
        reported.Record_Id__c = String.valueOf(businessRecord.Id);
        Error_Log__c supportOwnReport = errorFor(support.Id, 'DIAGNOSIS-SUPPORT-OWN-BUSINESS', false);
        supportOwnReport.Object_API_Name__c = 'Error_Feedback__c';
        supportOwnReport.Record_Id__c = String.valueOf(businessRecord.Id);
        insert new List<Error_Log__c>{reported, supportOwnReport};
        insert new Error_Log__Share(ParentId = reported.Id, UserOrGroupId = support.Id,
            AccessLevel = 'Read', RowCause = 'Manual');

        System.runAs(affected) {
            System.assert(Schema.sObjectType.Error_Feedback__c.isAccessible());
            System.assertEquals(0, [SELECT count() FROM Error_Feedback__c
                WHERE Id = :businessRecord.Id WITH USER_MODE], 'The affected user cannot read the reported business record.');
        }
        Map<Id, AEIR_AgentforceGatewayService.DiagnosisResult> results;
        Test.startTest();
        System.runAs(support) {
            System.assert(FeatureManagement.checkPermission('AEIR_View_Sensitive_Context'));
            System.assertEquals(privateValue, [SELECT Comments__c FROM Error_Feedback__c
                WHERE Id = :businessRecord.Id WITH USER_MODE].Comments__c, 'The support processor can read its own private record.');
            results = AEIR_AgentforceGatewayService.diagnoseErrors(new List<Id>{reported.Id, supportOwnReport.Id});
        }
        Test.stopTest();
        System.assertEquals(2, results.size(), 'Access-denied reports remain valid diagnostics.');
        Set<Id> diagnosisIds = new Set<Id>{results.get(reported.Id).diagnosisId, results.get(supportOwnReport.Id).diagnosisId};
        Map<Id, AI_Diagnosis__c> storedByLog = new Map<Id, AI_Diagnosis__c>();
        for (AI_Diagnosis__c row : [SELECT Error_Log__c, Input_Payload_JSON__c FROM AI_Diagnosis__c WHERE Id IN :diagnosisIds]) {
            storedByLog.put(row.Error_Log__c, row);
        }
        String protectedInput = storedByLog.get(reported.Id).Input_Payload_JSON__c;
        Map<String, Object> payload = (Map<String, Object>)JSON.deserializeUntyped(protectedInput);
        System.assertEquals('OMITTED_DIFFERENT_AFFECTED_USER', payload.get('recordSnapshotStatus'));
        System.assertEquals(false, payload.containsKey('recordSnapshot'));
        System.assert(((List<Object>)payload.get('omittedEvidenceFields')).contains('recordSnapshot'));
        System.assert(!protectedInput.contains(privateValue), 'Processor visibility must never enrich another user\'s AI input.');
        System.assert(((String)payload.get('context')).contains('save'), 'Captured caller-provided evidence remains usable.');
        System.assert(!protectedInput.contains('DIAGNOSIS-DO-NOT-SEND'), 'Captured evidence is still sanitized.');
        Map<String, Object> ownPayload = (Map<String, Object>)JSON.deserializeUntyped(storedByLog.get(supportOwnReport.Id).Input_Payload_JSON__c);
        System.assert(((String)ownPayload.get('recordSnapshot')).contains(privateValue),
            'The same-user snapshot in a mixed batch must not leak into the foreign-user payload.');
    }

    @IsTest
    static void affectedUserRetainsWhitelistedSnapshotWithNativeFieldAccessAndLegacyOwnerFallback() {
        disableOptionalWork();
        whitelistFeedbackComments();
        User affected = reader(0);
        Error_Feedback__c businessRecord = new Error_Feedback__c(OwnerId = affected.Id,
            Comments__c = 'AFFECTED-USER-VISIBLE-SNAPSHOT');
        insert businessRecord;
        Error_Log__c reported = errorFor(affected.Id, 'DIAGNOSIS-OWN-BUSINESS', false);
        reported.User__c = null;
        reported.Object_API_Name__c = 'Error_Feedback__c';
        reported.Record_Id__c = String.valueOf(businessRecord.Id);
        insert reported;
        Id diagnosisId;
        Test.startTest();
        System.runAs(affected) {
            System.assertEquals(false, FeatureManagement.checkPermission('AEIR_View_Sensitive_Context'));
            System.assert(Error_Feedback__c.Comments__c.getDescribe().isAccessible());
            System.assertEquals('AFFECTED-USER-VISIBLE-SNAPSHOT', [SELECT Comments__c FROM Error_Feedback__c
                WHERE Id = :businessRecord.Id WITH USER_MODE].Comments__c);
            diagnosisId = AEIR_AgentforceGatewayService.diagnoseError(reported.Id).diagnosisId;
        }
        Test.stopTest();
        AI_Diagnosis__c diagnosis = [SELECT Input_Payload_JSON__c FROM AI_Diagnosis__c WHERE Id = :diagnosisId];
        Map<String, Object> payload = (Map<String, Object>)JSON.deserializeUntyped(diagnosis.Input_Payload_JSON__c);
        System.assert(((String)payload.get('recordSnapshot')).contains('AFFECTED-USER-VISIBLE-SNAPSHOT'));
        System.assertEquals(false, payload.containsKey('recordSnapshotStatus'));
        System.assertEquals(false, ((List<Object>)payload.get('omittedEvidenceFields')).contains('recordSnapshot'));
    }
}
