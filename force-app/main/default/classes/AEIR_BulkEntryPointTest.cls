/**
 * Limit-cost tests for every entry point the platform can hand a batch to.
 *
 * Platform events are delivered in batches of up to 200 and Flow calls an invocable action
 * once with the whole batch, so each of these ran its per-record service in a loop. The
 * assertions below are on measured query and DML cost, not merely on "it did not throw" -
 * a loop-based implementation passes a functional test right up until it hits the limit.
 */
@IsTest
private class AEIR_BulkEntryPointTest {

    private static final Integer BATCH = 100;

    private static List<Error_Log__c> seedLogs(Integer count) {
        Account a = new Account(Name = 'Aegis Bulk Entry Point');
        insert a;
        List<Error_Log__c> logs = new List<Error_Log__c>();
        for (Integer i = 0; i < count; i++) {
            logs.add(new Error_Log__c(
                Correlation_Id__c = 'BEP-' + i,
                Source_Type__c = 'Apex Class',
                Source_Name__c = 'BulkEntryPointProbe',
                Object_API_Name__c = 'Account',
                Record_Id__c = a.Id,
                Error_Category__c = 'Null Pointer',
                Severity__c = 'High',
                Original_Error_Message__c = 'System.NullPointerException: probe ' + i,
                Normalized_Message__c = 'A referenced value was empty.',
                Status__c = 'New',
                User__c = UserInfo.getUserId()));
        }
        insert logs;
        return logs;
    }

    // ---------- platform event subscribers ----------

    @IsTest
    static void escalationSubscriberHandlesAFullEventBatch() {
        List<Error_Log__c> logs = seedLogs(BATCH);
        List<Escalation_Requested__e> events = new List<Escalation_Requested__e>();
        for (Error_Log__c log : logs) {
            events.add(new Escalation_Requested__e(
                Correlation_Id__c = log.Correlation_Id__c,
                Error_Log_Id__c = String.valueOf(log.Id)));
        }

        Test.startTest();
        Integer q = Limits.getQueries(), d = Limits.getDmlStatements();
        AEIR_EscalationRequestedEventHandler.handle(events);
        Integer queries = Limits.getQueries() - q, dml = Limits.getDmlStatements() - d;
        Test.stopTest();

        System.assert(queries <= 15, BATCH + ' events used ' + queries + ' queries.');
        System.assert(dml <= 15, BATCH + ' events used ' + dml + ' DML.');
        System.assertEquals(BATCH, [SELECT count() FROM Developer_Escalation__c],
            'Every event must produce an escalation.');
    }

    @IsTest
    static void escalationSubscriberPartitionsByRouteKey() {
        List<Error_Log__c> logs = seedLogs(4);
        List<Escalation_Requested__e> events = new List<Escalation_Requested__e>();
        for (Integer i = 0; i < logs.size(); i++) {
            events.add(new Escalation_Requested__e(
                Correlation_Id__c = logs[i].Correlation_Id__c,
                Error_Log_Id__c = String.valueOf(logs[i].Id),
                // Two named routes and two blank, so all three grouping paths are exercised.
                Route_Key__c = i < 2 ? null : 'DEFAULT_DEV_EMAIL'));
        }

        Test.startTest();
        AEIR_EscalationRequestedEventHandler.handle(events);
        Test.stopTest();

        System.assertEquals(4, [SELECT count() FROM Developer_Escalation__c],
            'Events with different route keys must all still escalate.');
        System.assertEquals(2, [SELECT count() FROM Developer_Escalation__c
                                WHERE Route_Key__c = 'DEFAULT_DEV_EMAIL']);
    }

    @IsTest
    static void agentDiagnosisSubscriberHandlesAFullEventBatch() {
        List<Error_Log__c> logs = seedLogs(BATCH);
        List<Agent_Diagnosis_Requested__e> events = new List<Agent_Diagnosis_Requested__e>();
        for (Error_Log__c log : logs) {
            events.add(new Agent_Diagnosis_Requested__e(
                Correlation_Id__c = log.Correlation_Id__c,
                Error_Log_Id__c = String.valueOf(log.Id)));
        }

        Test.startTest();
        Integer q = Limits.getQueries(), d = Limits.getDmlStatements();
        AEIR_AgentDiagnosisRequestedEventHandler.handle(events);
        Integer queries = Limits.getQueries() - q, dml = Limits.getDmlStatements() - d;
        Test.stopTest();

        System.assert(queries <= 15, BATCH + ' events used ' + queries + ' queries.');
        System.assert(dml <= 15, BATCH + ' events used ' + dml + ' DML.');
        System.assertEquals(BATCH, [SELECT count() FROM AI_Diagnosis__c],
            'Every requested diagnosis must be produced.');
        System.assertEquals(BATCH, [SELECT count() FROM Error_Log__c WHERE Status__c = 'Diagnosed'],
            'Diagnosis must close the round trip on every log, not just the first.');
    }

    @IsTest
    static void diagnosticSessionSubscriberHandlesAFullEventBatch() {
        List<Diagnostic_Session_Requested__e> events = new List<Diagnostic_Session_Requested__e>();
        for (Integer i = 0; i < BATCH; i++) {
            events.add(new Diagnostic_Session_Requested__e(
                Correlation_Id__c = 'BEP-SESS-' + i,
                User_Id__c = String.valueOf(UserInfo.getUserId()),
                User_Description__c = 'Save did nothing, attempt ' + i,
                Page_Reference_JSON__c = '{"objectApiName":"Account","pageUrl":"/lightning/o/Account/home"}'));
        }

        Test.startTest();
        Integer q = Limits.getQueries(), d = Limits.getDmlStatements();
        AEIR_DiagnosticSessionRequestHandler.handle(events);
        Integer queries = Limits.getQueries() - q, dml = Limits.getDmlStatements() - d;
        Test.stopTest();

        System.assert(queries <= 10, BATCH + ' events used ' + queries + ' queries.');
        System.assert(dml <= 5, BATCH + ' events used ' + dml + ' DML.');
        System.assertEquals(BATCH, [SELECT count() FROM Diagnostic_Session__c]);
    }

    @IsTest
    static void diagnosticSessionSubscriberSkipsEventsThatAlreadyHaveASession() {
        List<Diagnostic_Session_Requested__e> events = new List<Diagnostic_Session_Requested__e>{
            new Diagnostic_Session_Requested__e(Correlation_Id__c = 'BEP-EXIST',
                User_Id__c = String.valueOf(UserInfo.getUserId()),
                Session_Id__c = 'a00000000000000AAA')};

        Test.startTest();
        AEIR_DiagnosticSessionRequestHandler.handle(events);
        Test.stopTest();

        System.assertEquals(0, [SELECT count() FROM Diagnostic_Session__c],
            'An event that already carries a session id must not create a duplicate.');
    }

    // ---------- invocable actions ----------

    @IsTest
    static void getErrorContextHandlesAFullFlowBatch() {
        List<Error_Log__c> logs = seedLogs(BATCH);
        List<AEIR_GetErrorContextAction.Request> requests = new List<AEIR_GetErrorContextAction.Request>();
        for (Error_Log__c log : logs) {
            AEIR_GetErrorContextAction.Request r = new AEIR_GetErrorContextAction.Request();
            r.errorLogId = String.valueOf(log.Id);
            requests.add(r);
        }

        Test.startTest();
        Integer q = Limits.getQueries();
        List<AEIR_GetErrorContextAction.Response> responses = AEIR_GetErrorContextAction.run(requests);
        Integer queries = Limits.getQueries() - q;
        Test.stopTest();

        // The old implementation cost four queries each, so it died at 25 requests.
        System.assert(queries <= 10, BATCH + ' requests used ' + queries + ' queries.');
        System.assertEquals(BATCH, responses.size(), 'One response per request is the invocable contract.');
        for (AEIR_GetErrorContextAction.Response response : responses) {
            System.assertNotEquals(null, response.contextJson);
            System.assertEquals('Sanitized error context returned.', response.message);
        }
    }

    @IsTest
    static void getErrorContextReportsBadAndMissingIdsWithoutLosingTheBatch() {
        List<Error_Log__c> logs = seedLogs(1);
        List<AEIR_GetErrorContextAction.Request> requests = new List<AEIR_GetErrorContextAction.Request>();
        AEIR_GetErrorContextAction.Request good = new AEIR_GetErrorContextAction.Request();
        good.errorLogId = String.valueOf(logs[0].Id);
        AEIR_GetErrorContextAction.Request malformed = new AEIR_GetErrorContextAction.Request();
        malformed.errorLogId = 'not-an-id';
        requests.add(malformed);
        requests.add(good);

        Test.startTest();
        List<AEIR_GetErrorContextAction.Response> responses = AEIR_GetErrorContextAction.run(requests);
        Test.stopTest();

        System.assertEquals(2, responses.size());
        System.assert(responses[0].message.contains('Not a valid record id'),
            'A malformed id must be reported in its own slot: ' + responses[0].message);
        System.assertNotEquals(null, responses[1].contextJson,
            'One bad id must not cost the valid request its context.');
    }

    @IsTest
    static void getRecordSnapshotHandlesAFullFlowBatch() {
        Account a = new Account(Name = 'Snapshot Bulk');
        insert a;
        List<AEIR_GetRecordSnapshotAction.Request> requests = new List<AEIR_GetRecordSnapshotAction.Request>();
        for (Integer i = 0; i < BATCH; i++) {
            AEIR_GetRecordSnapshotAction.Request r = new AEIR_GetRecordSnapshotAction.Request();
            r.objectApiName = 'Account';
            r.recordId = a.Id;
            // Alternating so both whitelists are resolved, and neither leaks into the other.
            r.forEscalation = Math.mod(i, 2) == 0;
            requests.add(r);
        }

        Test.startTest();
        Integer q = Limits.getQueries();
        List<AEIR_GetRecordSnapshotAction.Response> responses = AEIR_GetRecordSnapshotAction.run(requests);
        Integer queries = Limits.getQueries() - q;
        Test.stopTest();

        System.assert(queries <= 6, BATCH + ' requests used ' + queries + ' queries.');
        System.assertEquals(BATCH, responses.size());
    }

    @IsTest
    static void invokeDiagnosisHandlesAFullFlowBatch() {
        List<Error_Log__c> logs = seedLogs(BATCH);
        List<AEIR_InvokeDiagnosisAction.Request> requests = new List<AEIR_InvokeDiagnosisAction.Request>();
        for (Error_Log__c log : logs) {
            AEIR_InvokeDiagnosisAction.Request r = new AEIR_InvokeDiagnosisAction.Request();
            r.errorLogId = log.Id;
            requests.add(r);
        }

        Test.startTest();
        Integer d = Limits.getDmlStatements();
        List<AEIR_InvokeDiagnosisAction.Response> responses = AEIR_InvokeDiagnosisAction.invokeDiagnosis(requests);
        Integer dml = Limits.getDmlStatements() - d;
        Test.stopTest();

        System.assert(dml <= 10, BATCH + ' requests used ' + dml + ' DML.');
        System.assertEquals(BATCH, responses.size());
        for (AEIR_InvokeDiagnosisAction.Response response : responses) {
            System.assertNotEquals(null, response.diagnosisId, 'Every request must get a real diagnosis.');
        }
    }

    @IsTest
    static void invokeDiagnosisReportsAnUnreadableRecordRatherThanABlankRow() {
        AEIR_InvokeDiagnosisAction.Request r = new AEIR_InvokeDiagnosisAction.Request();
        r.errorLogId = '000000000000000AAA';

        Test.startTest();
        List<AEIR_InvokeDiagnosisAction.Response> responses =
            AEIR_InvokeDiagnosisAction.invokeDiagnosis(new List<AEIR_InvokeDiagnosisAction.Request>{ r });
        Test.stopTest();

        System.assertEquals('UNKNOWN', responses[0].fixability);
        System.assertEquals(true, responses[0].escalationRequired,
            'An unreadable record must escalate, not read as a clean diagnosis.');
    }

    @IsTest
    static void createEscalationActionHandlesAFullFlowBatch() {
        List<Error_Log__c> logs = seedLogs(BATCH);
        List<AEIR_CreateEscalationAction.Request> requests = new List<AEIR_CreateEscalationAction.Request>();
        for (Error_Log__c log : logs) {
            AEIR_CreateEscalationAction.Request r = new AEIR_CreateEscalationAction.Request();
            r.errorLogId = log.Id;
            r.sendEmailNow = false;
            requests.add(r);
        }

        Test.startTest();
        Integer d = Limits.getDmlStatements();
        List<AEIR_CreateEscalationAction.Response> responses =
            AEIR_CreateEscalationAction.createEscalation(requests);
        Integer dml = Limits.getDmlStatements() - d;
        Test.stopTest();

        System.assert(dml <= 10, BATCH + ' requests used ' + dml + ' DML.');
        System.assertEquals(BATCH, responses.size());
        // Responses are matched by source id, not list position: createForErrors returns in
        // SOQL order, so an index-based match would mislabel these.
        for (AEIR_CreateEscalationAction.Response response : responses) {
            System.assertNotEquals(null, response.escalationId);
            System.assertEquals('New', response.status);
        }
    }

    @IsTest
    static void createEscalationActionSplitsOnTheSendFlag() {
        List<Error_Log__c> logs = seedLogs(4);
        List<AEIR_CreateEscalationAction.Request> requests = new List<AEIR_CreateEscalationAction.Request>();
        for (Integer i = 0; i < logs.size(); i++) {
            AEIR_CreateEscalationAction.Request r = new AEIR_CreateEscalationAction.Request();
            r.errorLogId = logs[i].Id;
            r.sendEmailNow = i < 2;
            requests.add(r);
        }

        Test.startTest();
        List<AEIR_CreateEscalationAction.Response> responses =
            AEIR_CreateEscalationAction.createEscalation(requests);
        Test.stopTest();

        System.assertEquals(4, responses.size());
        System.assertEquals(2, [SELECT count() FROM Developer_Escalation__c WHERE Status__c = 'New'],
            'Requests that asked to hold the email must not have been sent.');
    }

    @IsTest
    static void sessionDiagnosisIsBatchedAndRoutesLinkedSessionsToTheErrorPath() {
        List<Error_Log__c> logs = seedLogs(2);
        List<Diagnostic_Session__c> sessions = new List<Diagnostic_Session__c>();
        for (Integer i = 0; i < 50; i++) {
            sessions.add(new Diagnostic_Session__c(
                Correlation_Id__c = 'BEP-DIAG-' + i,
                User_Description__c = 'Nothing happens when I click Save.',
                User__c = UserInfo.getUserId(),
                // The first two point at a captured error and must take the error path.
                Recent_Error_Log__c = i < 2 ? logs[i].Id : null,
                Resolution_Status__c = 'Open'));
        }
        insert sessions;
        List<Id> sessionIds = new List<Id>();
        for (Diagnostic_Session__c s : sessions) sessionIds.add(s.Id);

        Test.startTest();
        Integer q = Limits.getQueries(), d = Limits.getDmlStatements();
        Map<Id, AEIR_AgentforceGatewayService.DiagnosisResult> results =
            AEIR_AgentforceGatewayService.diagnoseSessions(sessionIds);
        Integer queries = Limits.getQueries() - q, dml = Limits.getDmlStatements() - d;
        Test.stopTest();

        System.assert(queries <= 12, '50 sessions used ' + queries + ' queries.');
        System.assert(dml <= 12, '50 sessions used ' + dml + ' DML.');
        System.assertEquals(50, results.size(), 'Every session must get a diagnosis.');
        System.assertEquals(2, [SELECT count() FROM Error_Log__c WHERE Status__c = 'Diagnosed'],
            'A session linked to a captured error must be diagnosed through the error path.');
        System.assertEquals(48, [SELECT count() FROM Diagnostic_Session__c
                                 WHERE Resolution_Status__c = 'Pending User'],
            'Sessions with no captured error get the guidance fallback.');
    }

    // ---------- governed remediation stays per record ----------

    @IsTest
    static void remediationRefusesAnOversizedBatchInsteadOfHalfApplyingIt() {
        List<AEIR_ExecuteRemediationAction.Request> requests =
            new List<AEIR_ExecuteRemediationAction.Request>();
        for (Integer i = 0; i <= AEIR_ExecuteRemediationAction.MAX_BATCH; i++) {
            AEIR_ExecuteRemediationAction.Request r = new AEIR_ExecuteRemediationAction.Request();
            r.actionKey = 'UPDATE_ACCOUNT_DESCRIPTION';
            r.objectApiName = 'Account';
            r.confirmed = true;
            requests.add(r);
        }

        Test.startTest();
        Integer d = Limits.getDmlStatements();
        List<AEIR_ExecuteRemediationAction.Response> responses =
            AEIR_ExecuteRemediationAction.executeRemediation(requests);
        Integer dml = Limits.getDmlStatements() - d;
        Test.stopTest();

        System.assertEquals(0, dml, 'An oversized batch must be refused before it writes anything.');
        System.assertEquals(requests.size(), responses.size());
        for (AEIR_ExecuteRemediationAction.Response response : responses) {
            System.assertEquals(false, response.success);
            System.assert(response.technicalMessage.contains('one record at a time'),
                'The refusal must explain why: ' + response.technicalMessage);
        }
    }

    @IsTest
    static void updateMissingFieldRefusesAnOversizedBatchToo() {
        List<AEIR_UpdateMissingFieldAction.Request> requests =
            new List<AEIR_UpdateMissingFieldAction.Request>();
        for (Integer i = 0; i <= AEIR_UpdateMissingFieldAction.MAX_BATCH; i++) {
            AEIR_UpdateMissingFieldAction.Request r = new AEIR_UpdateMissingFieldAction.Request();
            r.actionKey = 'UPDATE_ACCOUNT_DESCRIPTION';
            r.objectApiName = 'Account';
            r.fieldApiName = 'Description';
            r.confirmed = true;
            requests.add(r);
        }

        Test.startTest();
        Integer d = Limits.getDmlStatements();
        List<AEIR_UpdateMissingFieldAction.Response> responses = AEIR_UpdateMissingFieldAction.run(requests);
        Integer dml = Limits.getDmlStatements() - d;
        Test.stopTest();

        System.assertEquals(0, dml, 'An oversized batch must be refused before it writes anything.');
        System.assertEquals('Refused', responses[0].status);
    }
}