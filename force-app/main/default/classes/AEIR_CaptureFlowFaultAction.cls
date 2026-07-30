public with sharing class AEIR_CaptureFlowFaultAction {
    public class Request {
        @InvocableVariable public String varCorrelationId;
        @InvocableVariable public String varFlowApiName;
        @InvocableVariable public String varFlowVersion;
        @InvocableVariable public String varFailedElement;
        @InvocableVariable public String varErrorMessage;
        @InvocableVariable public String varObjectApiName;
        @InvocableVariable public String varRecordId;
        @InvocableVariable public String varUserAction;
        @InvocableVariable public String varPageUrl;
        @InvocableVariable public String varContextJson;
    }
    public class Response {
        @InvocableVariable public Id errorLogId;
        @InvocableVariable public String correlationId;
        @InvocableVariable public String userMessage;
        @InvocableVariable public String severity;
    }
    /**
     * Bulk safe. This is the documented Flow fault-path entry point, so when a
     * record-triggered Flow fails across a 200 record batch this method receives 200
     * requests at once. Calling capture() per request performed several queries, an
     * incident upsert, an insert and an event publish each time, and exceeded the SOQL
     * limit long before 200. All inputs are now built first and captured in one call.
     */
    @InvocableMethod(label='AEIR Capture Flow Fault' description='Creates an AEIR error log from a Flow fault path.')
    public static List<Response> captureFlowFault(List<Request> requests) {
        List<Response> out = new List<Response>();
        if (requests == null || requests.isEmpty()) return out;

        List<AEIR_ErrorCaptureService.ErrorInput> inputs = new List<AEIR_ErrorCaptureService.ErrorInput>();
        for (Request r : requests) {
            AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
            if (r != null) {
                input.correlationId = r.varCorrelationId;
                input.sourceName = r.varFlowApiName;
                input.objectApiName = r.varObjectApiName;
                input.recordId = r.varRecordId;
                input.actionName = r.varUserAction;
                input.pageUrl = r.varPageUrl;
                input.originalMessage = r.varErrorMessage;
                input.contextJson = r.varContextJson;
            }
            input.sourceType = 'Flow';
            inputs.add(input);
        }

        List<AEIR_ErrorCaptureService.CaptureResult> results =
            AEIR_ErrorCaptureService.captureFromEvents(inputs);

        // Flow requires one response per request, in order, even when a capture failed.
        for (Integer i = 0; i < requests.size(); i++) {
            AEIR_ErrorCaptureService.CaptureResult cr = i < results.size() ? results[i] : null;
            Response res = new Response();
            if (cr != null) {
                res.errorLogId = cr.errorLogId;
                res.correlationId = cr.correlationId;
                res.userMessage = cr.normalizedMessage;
                res.severity = cr.severity;
            }
            out.add(res);
        }
        return out;
    }
}