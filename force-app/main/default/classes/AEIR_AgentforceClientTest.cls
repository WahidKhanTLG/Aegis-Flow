@IsTest
private class AEIR_AgentforceClientTest {
    private static final String SESSION = '00000000-0000-4000-8000-000000000001';

    private static void enableConnection() {
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AI_DIAGNOSIS, true);
        AEIR_AgentforceClient.connectionOverride = new Agent_Connection__mdt(
            Active__c = true, Named_Credential__c = 'aegis__Diagnostic_Agent',
            Agent_Id__c = '0Xx000000000001', Timeout_Milliseconds__c = 15000);
    }

    private static Map<String, Object> responseValues() {
        return new Map<String, Object>{
            'summary' => 'A required field is missing.', 'rootCause' => 'Required field validation failed.',
            'fixability' => 'USER_FIXABLE', 'confidence' => 88, 'recommendedAction' => 'Review the required Name field.',
            'needsUserInput' => true, 'escalationRequired' => false, 'safeRemediationActionKey' => null
        };
    }

    private class AgentMock implements HttpCalloutMock {
        Integer startStatus = 200;
        Integer messageStatus = 200;
        Integer endStatus = 200;
        Integer starts = 0;
        Integer messages = 0;
        Integer ends = 0;
        Boolean safe = true;
        String envelope;
        String diagnosisText = JSON.serialize(responseValues());

        public HttpResponse respond(HttpRequest request) {
            System.assert(request.getEndpoint().startsWith('callout:aegis__Diagnostic_Agent/einstein/ai-agent/v1/'),
                'All requests stay within the namespaced Named Credential.');
            System.assertEquals('application/json', request.getHeader('Content-Type'));
            HttpResponse response = new HttpResponse();
            if (request.getEndpoint().endsWith('/agents/0Xx000000000001/sessions')) {
                starts++;
                System.assertEquals('POST', request.getMethod());
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
                System.assertEquals(false, body.get('bypassUser'), 'Never switch to the agent-assigned user.');
                System.assertEquals('Sync', body.get('featureSupport'));
                System.assert(Pattern.matches('[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-8[a-f0-9]{3}-[a-f0-9]{12}',
                    (String) body.get('externalSessionKey')));
                System.assertEquals(URL.getOrgDomainUrl().toExternalForm(),
                    ((Map<String, Object>) body.get('instanceConfig')).get('endpoint'));
                response.setStatusCode(startStatus);
                response.setBody(startStatus == 200 ? JSON.serialize(new Map<String, Object>{
                    'sessionId' => SESSION,
                    '_links' => new Map<String, Object>{ 'messages' => new Map<String, Object>{ 'href' => 'https://untrusted.example.invalid/' } }
                }) : '{"access_token":"PROVIDER_SECRET_SENTINEL"}');
            } else if (request.getEndpoint().endsWith('/sessions/' + SESSION + '/messages')) {
                messages++;
                System.assertEquals('POST', request.getMethod());
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
                Map<String, Object> message = (Map<String, Object>) body.get('message');
                System.assertEquals(Decimal.valueOf('1'), message.get('sequenceId'));
                System.assertEquals('Text', message.get('type'));
                System.assert(!request.getBody().contains('OUTBOUND_SECRET_SENTINEL'), 'Mask the payload before the HTTP boundary.');
                response.setStatusCode(messageStatus);
                response.setBody(messageStatus != 200 ? '{"access_token":"PROVIDER_SECRET_SENTINEL"}' :
                    (envelope == null ? JSON.serialize(new Map<String, Object>{ 'messages' => new List<Object>{
                        new Map<String, Object>{ 'type' => 'Inform', 'isContentSafe' => safe,
                            'message' => diagnosisText, 'result' => new List<Object>() }
                    } }) : envelope));
            } else {
                ends++;
                System.assertEquals('callout:aegis__Diagnostic_Agent/einstein/ai-agent/v1/sessions/' + SESSION, request.getEndpoint());
                System.assertEquals('DELETE', request.getMethod());
                System.assertEquals('UserRequest', request.getHeader('x-session-end-reason'));
                response.setStatusCode(endStatus);
                response.setBody('{"messages":[]}');
            }
            return response;
        }
    }

    @IsTest
    static void sessionLifecycleUsesSafePayloadAndCleansUp() {
        enableConnection();
        AgentMock mock = new AgentMock();
        Map<String, Object> values = responseValues();
        values.put('rootCause', 'password=RETURNED_SECRET_SENTINEL');
        mock.diagnosisText = JSON.serialize(values);
        Test.setMock(HttpCalloutMock.class, mock);
        AEIR_AgentforceClient.Outcome result = AEIR_AgentforceClient.diagnose(
            '{"password":"OUTBOUND_SECRET_SENTINEL","originalMessage":"REQUIRED_FIELD_MISSING"}');
        System.assertEquals(true, result.success, result.status);
        System.assertEquals('COMPLETED', result.cleanupStatus);
        System.assertEquals(1, mock.starts);
        System.assertEquals(1, mock.messages);
        System.assertEquals(1, mock.ends);
        System.assertEquals('password=[MASKED]', result.diagnosis.rootCause);
        System.assert(!JSON.serialize(result).contains('RETURNED_SECRET_SENTINEL'));
    }

    @IsTest
    static void authenticationFailureDoesNotStoreProviderBodyOrCreateSession() {
        enableConnection();
        AgentMock mock = new AgentMock();
        mock.startStatus = 401;
        Test.setMock(HttpCalloutMock.class, mock);
        AEIR_AgentforceClient.Outcome result = AEIR_AgentforceClient.diagnose('{}');
        System.assertEquals(false, result.success);
        System.assertEquals('START_HTTP_401', result.status);
        System.assertEquals(1, mock.starts);
        System.assertEquals(0, mock.messages);
        System.assertEquals(0, mock.ends);
        System.assert(!JSON.serialize(result).contains('PROVIDER_SECRET_SENTINEL'));
    }

    @IsTest
    static void throttlingAndServerErrorsPreserveFallbackWithoutAutomaticRetry() {
        enableConnection();
        for (Integer status : new List<Integer>{ 429, 503 }) {
            AgentMock mock = new AgentMock();
            mock.messageStatus = status;
            Test.setMock(HttpCalloutMock.class, mock);
            List<AI_Diagnosis__c> rows = new List<AI_Diagnosis__c>{ fallback() };
            AEIR_AgentforceDiagnosisJob.enrich(rows);
            System.assertEquals('Fallback summary', rows[0].Summary__c);
            System.assertEquals('Failed', rows[0].Agent_Status__c);
            System.assert(rows[0].Output_JSON__c.contains('MESSAGE_HTTP_' + status));
            System.assert(!rows[0].Output_JSON__c.contains('PROVIDER_SECRET_SENTINEL'));
            System.assertEquals(1, mock.messages);
            System.assertEquals(1, mock.ends, 'Close sessions even after a rejected message.');
        }
    }

    @IsTest
    static void malformedApiAndStructuredResponsesAreRejectedAndSessionsClosed() {
        enableConnection();
        AgentMock mock = new AgentMock();
        mock.envelope = '{not valid JSON';
        Test.setMock(HttpCalloutMock.class, mock);
        AEIR_AgentforceClient.Outcome result = AEIR_AgentforceClient.diagnose('{}');
        System.assertEquals('INVALID_RESPONSE_JSON', result.status);
        System.assertEquals(false, result.success);
        System.assertEquals(1, mock.ends);
        mock = new AgentMock();
        mock.diagnosisText = 'An unstructured answer must not be treated as a diagnosis.';
        Test.setMock(HttpCalloutMock.class, mock);
        result = AEIR_AgentforceClient.diagnose('{}');
        System.assertEquals('INVALID_RESPONSE_JSON', result.status);
        System.assertEquals(false, result.success);
        System.assertEquals(1, mock.ends);
    }

    @IsTest
    static void unknownActionsAndInvalidConfidenceOrBooleanTypesAreRejected() {
        enableConnection();
        for (String invalidField : new List<String>{ 'safeRemediationActionKey', 'confidence', 'needsUserInput', 'executeApex' }) {
            AgentMock mock = new AgentMock();
            Map<String, Object> values = responseValues();
            values.put(invalidField, invalidField == 'safeRemediationActionKey' ? 'UNREGISTERED_ACTION' : 'invalid');
            mock.diagnosisText = JSON.serialize(values);
            Test.setMock(HttpCalloutMock.class, mock);
            List<AI_Diagnosis__c> rows = new List<AI_Diagnosis__c>{ fallback() };
            AEIR_AgentforceDiagnosisJob.enrich(rows);
            System.assertEquals('Fallback summary', rows[0].Summary__c);
            System.assertEquals('Failed', rows[0].Agent_Status__c);
            System.assertEquals(null, rows[0].Safe_Remediation_Action_Key__c);
            System.assertEquals(1, mock.ends);
        }
    }

    @IsTest
    static void unsafeContentAndFailedCleanupCannotReplaceFallback() {
        enableConnection();
        AgentMock mock = new AgentMock();
        mock.safe = false;
        Test.setMock(HttpCalloutMock.class, mock);
        List<AI_Diagnosis__c> rows = new List<AI_Diagnosis__c>{ fallback() };
        AEIR_AgentforceDiagnosisJob.enrich(rows);
        System.assertEquals('Fallback summary', rows[0].Summary__c);
        System.assert(rows[0].Output_JSON__c.contains('UNSAFE_OR_AMBIGUOUS_MESSAGE'));
        System.assertEquals(1, mock.ends);
        mock = new AgentMock();
        mock.endStatus = 503;
        Test.setMock(HttpCalloutMock.class, mock);
        rows = new List<AI_Diagnosis__c>{ fallback() };
        AEIR_AgentforceDiagnosisJob.enrich(rows);
        System.assertEquals('Fallback summary', rows[0].Summary__c);
        System.assert(rows[0].Output_JSON__c.contains('END_HTTP_503'));
    }

    @IsTest
    static void featureAndConnectionGatesPreventEveryHttpCall() {
        enableConnection();
        AgentMock mock = new AgentMock();
        Test.setMock(HttpCalloutMock.class, mock);
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AI_DIAGNOSIS, false);
        System.assertEquals('AI_DISABLED', AEIR_AgentforceClient.diagnose('{}').status);
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AI_DIAGNOSIS, true);
        AEIR_AgentforceClient.connectionOverride.Active__c = false;
        System.assertEquals('CONNECTION_DISABLED', AEIR_AgentforceClient.diagnose('{}').status);
        AEIR_AgentforceClient.connectionOverride.Active__c = true;
        AEIR_AgentforceClient.connectionOverride.Named_Credential__c = 'Alias/../../untrusted';
        System.assertEquals('INVALID_CONNECTION', AEIR_AgentforceClient.diagnose('{}').status);
        System.assertEquals(0, mock.starts);
    }

    @IsTest
    static void enrichmentIsBoundedAndKeepsDeterministicEvidence() {
        enableConnection();
        AgentMock mock = new AgentMock();
        Test.setMock(HttpCalloutMock.class, mock);
        List<AI_Diagnosis__c> rows = new List<AI_Diagnosis__c>{ fallback(), fallback(), fallback(), fallback() };
        AEIR_AgentforceDiagnosisJob.enrich(rows);
        System.assertEquals(3, mock.starts);
        System.assertEquals(3, mock.messages);
        System.assertEquals(3, mock.ends);
        System.assertEquals('Completed', rows[0].Agent_Status__c);
        System.assertEquals('A required field is missing.', rows[0].Summary__c);
        Map<String, Object> output = (Map<String, Object>) JSON.deserializeUntyped(rows[0].Output_JSON__c);
        System.assertEquals('Fallback summary', ((Map<String, Object>) output.get('deterministicFallback')).get('summary'));
        System.assertEquals('Fallback summary', rows[3].Summary__c);
        System.assertEquals('Deterministic Fallback', rows[3].Agent_Status__c);
        System.assert(rows[3].Output_JSON__c.contains('BATCH_CAPACITY'));
    }

    @IsTest
    static void confidenceAndRegisteredActionValidationRemainServerSide() {
        Map<String, Object> values = responseValues();
        values.put('safeRemediationActionKey', 'UPDATE_ACCOUNT_DESCRIPTION');
        AEIR_AgentforceGatewayService.DiagnosisResult result = AEIR_AgentforceClient.validatedDiagnosis(JSON.serialize(values));
        System.assertEquals('UPDATE_ACCOUNT_DESCRIPTION', result.safeRemediationActionKey);
        values.put('safeRemediationActionKey', null);
        values.put('confidence', 20);
        values.put('escalationRequired', false);
        result = AEIR_AgentforceClient.validatedDiagnosis(JSON.serialize(values));
        System.assertEquals(true, result.escalationRequired, 'Low confidence must escalate, not offer a correction.');
        for (Decimal confidence : new List<Decimal>{ -1, 101 }) {
            values.put('confidence', confidence);
            Boolean rejected = false;
            try { AEIR_AgentforceClient.validatedDiagnosis(JSON.serialize(values)); }
            catch (AEIR_AgentforceClient.AgentApiException expected) { rejected = true; }
            System.assert(rejected, 'Reject confidence outside the documented 0-100 scale.');
        }
    }

    @IsTest
    static void configuredTimeoutIsBounded() {
        enableConnection();
        AEIR_AgentforceClient.connectionOverride.Timeout_Milliseconds__c = 99999;
        System.assertEquals(20000, AEIR_AgentforceClient.configuredConnection().timeoutMilliseconds);
        AEIR_AgentforceClient.connectionOverride.Timeout_Milliseconds__c = 1;
        System.assertEquals(1000, AEIR_AgentforceClient.configuredConnection().timeoutMilliseconds);
    }

    @IsTest
    static void fallbackExistsBeforeOptionalQueueableRuns() {
        enableConnection();
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.USER_NOTIFICATIONS, false);
        Test.setMock(HttpCalloutMock.class, new AgentMock());
        Error_Log__c log = new Error_Log__c(Correlation_Id__c = 'AGENT-QUEUE-TEST',
            Source_Type__c = 'Flow', Source_Name__c = 'Agent_API_Test',
            Original_Error_Message__c = 'REQUIRED_FIELD_MISSING: Name',
            Normalized_Message__c = 'A required field is missing.',
            Error_Category__c = 'Missing Data', Severity__c = 'Medium', Status__c = 'New',
            User__c = UserInfo.getUserId());
        insert log;
        Test.startTest();
        AEIR_AgentforceGatewayService.DiagnosisResult result = AEIR_AgentforceGatewayService.diagnoseError(log.Id);
        AI_Diagnosis__c beforeAsync = [SELECT Summary__c, Agent_Status__c, Output_JSON__c
            FROM AI_Diagnosis__c WHERE Id = :result.diagnosisId];
        System.assertNotEquals(null, beforeAsync.Summary__c, 'Persist useful fallback before remote work.');
        System.assert(beforeAsync.Output_JSON__c.contains('QUEUED'));
        System.assertEquals(1, Limits.getQueueableJobs(), 'Enrichment must run in a separate transaction.');
        Test.stopTest();
        AI_Diagnosis__c afterAsync = [SELECT Summary__c, Output_JSON__c FROM AI_Diagnosis__c WHERE Id = :result.diagnosisId];
        System.assertNotEquals(null, afterAsync.Summary__c);
        System.assert(afterAsync.Output_JSON__c.contains('agentAttemptStatus'), 'Keep an audit of optional enrichment.');
        System.assertEquals(1, [SELECT count() FROM AsyncApexJob
            WHERE ApexClass.Name = 'AEIR_AgentforceDiagnosisJob' AND Status = 'Completed']);
    }

    private static AI_Diagnosis__c fallback() {
        return new AI_Diagnosis__c(Summary__c = 'Fallback summary', Root_Cause__c = 'Known deterministic rule',
            Fixability__c = 'UNKNOWN', Confidence__c = 55, Recommended_Action__c = 'Escalate with evidence',
            Needs_User_Input__c = false, Escalation_Required__c = true,
            Agent_Status__c = 'Deterministic Fallback',
            Input_Payload_JSON__c = '{"password":"OUTBOUND_SECRET_SENTINEL","sourceType":"Flow"}',
            Output_JSON__c = '{"summary":"Fallback summary","fixability":"UNKNOWN"}');
    }
}
