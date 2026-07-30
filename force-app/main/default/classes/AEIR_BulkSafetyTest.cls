/**
 * Bulk safety for the entry points that receive batched input.
 *
 * These all shared one defect: calling AEIR_ErrorCaptureService.capture() inside a loop.
 * capture() performs several queries, an incident upsert, an insert and an event publish,
 * so per-item invocation exceeded the SOQL limit long before the platform's batch size.
 * Each test asserts a bounded cost rather than merely exercising the path, because a
 * limits fix that is not measured is not a fix.
 */
@IsTest
private class AEIR_BulkSafetyTest {

    private static List<FlowInterview> fakeInterviews(Integer count) {
        List<FlowInterview> rows = new List<FlowInterview>();
        for (Integer i = 0; i < count; i++) {
            rows.add((FlowInterview) JSON.deserialize(
                '{"attributes":{"type":"FlowInterview"},' +
                '"Guid":"bulk-guid-' + i + '",' +
                '"InterviewLabel":"Bulk Probe Flow 7/29/2026, 9:00 AM",' +
                '"CurrentElement":"Update_Records",' +
                '"Error":"FIELD_CUSTOM_VALIDATION_EXCEPTION: bulk probe ' + i + '"}',
                FlowInterview.class));
        }
        return rows;
    }

    @IsTest
    static void flowInterviewReconcileIsBulkSafe() {
        List<FlowInterview> interviews = fakeInterviews(150);

        Test.startTest();
        Integer q = Limits.getQueries(), d = Limits.getDmlStatements();
        Integer captured = AEIR_FlowInterviewMonitor.reconcile(interviews);
        Integer queriesUsed = Limits.getQueries() - q;
        Integer dmlUsed = Limits.getDmlStatements() - d;
        Test.stopTest();

        System.assertEquals(150, captured, 'Every errored interview should be captured.');
        System.assert(queriesUsed <= 10, 'Query cost must not scale with interview count, used ' + queriesUsed);
        System.assert(dmlUsed <= 10, 'DML cost must not scale with interview count, used ' + dmlUsed);
        System.assertEquals(150, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c LIKE 'FLOWINT-bulk-guid-%']);
    }

    @IsTest
    static void flowInterviewReconcileDedupesWithinOneBatch() {
        // The same interview appearing twice in one batch must not create two logs.
        List<FlowInterview> interviews = fakeInterviews(1);
        interviews.addAll(fakeInterviews(1));

        Test.startTest();
        Integer captured = AEIR_FlowInterviewMonitor.reconcile(interviews);
        Test.stopTest();

        System.assertEquals(1, captured, 'A duplicate inside one batch must be collapsed.');
        System.assertEquals(1, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c = 'FLOWINT-bulk-guid-0']);
    }

    @IsTest
    static void flowFaultActionIsBulkSafeAndReturnsOneResponsePerRequest() {
        // A record-triggered Flow failing across a 200 record batch hits this with 200
        // requests at once. Flow also requires one response per request, in order.
        List<AEIR_CaptureFlowFaultAction.Request> requests = new List<AEIR_CaptureFlowFaultAction.Request>();
        for (Integer i = 0; i < 200; i++) {
            AEIR_CaptureFlowFaultAction.Request r = new AEIR_CaptureFlowFaultAction.Request();
            r.varCorrelationId = 'FAULT-' + i;
            r.varFlowApiName = 'Bulk_Fault_Flow';
            r.varFailedElement = 'Update_Records';
            r.varErrorMessage = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: fault ' + i;
            r.varObjectApiName = 'Account';
            requests.add(r);
        }

        Test.startTest();
        Integer q = Limits.getQueries(), d = Limits.getDmlStatements();
        List<AEIR_CaptureFlowFaultAction.Response> responses =
            AEIR_CaptureFlowFaultAction.captureFlowFault(requests);
        Integer queriesUsed = Limits.getQueries() - q;
        Integer dmlUsed = Limits.getDmlStatements() - d;
        Test.stopTest();

        System.assertEquals(200, responses.size(), 'Flow requires one response per request.');
        System.assert(queriesUsed <= 10, 'Query cost must not scale with request count, used ' + queriesUsed);
        System.assert(dmlUsed <= 10, 'DML cost must not scale with request count, used ' + dmlUsed);
        System.assertEquals('FAULT-0', responses[0].correlationId, 'Responses must stay in request order.');
        System.assertEquals('FAULT-199', responses[199].correlationId);
        System.assertEquals(200, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c LIKE 'FAULT-%']);
    }

    @IsTest
    static void flowFaultActionHandlesEmptyAndNullRequests() {
        Test.startTest();
        System.assertEquals(0, AEIR_CaptureFlowFaultAction.captureFlowFault(null).size());
        System.assertEquals(0, AEIR_CaptureFlowFaultAction.captureFlowFault(
            new List<AEIR_CaptureFlowFaultAction.Request>()).size());
        List<AEIR_CaptureFlowFaultAction.Response> withNull =
            AEIR_CaptureFlowFaultAction.captureFlowFault(
                new List<AEIR_CaptureFlowFaultAction.Request>{ null });
        Test.stopTest();
        System.assertEquals(1, withNull.size(), 'A null request must still get a response slot.');
    }
}