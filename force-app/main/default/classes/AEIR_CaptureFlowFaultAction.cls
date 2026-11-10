global with sharing class AEIR_CaptureFlowFaultAction {
    global class Request {
        global Request() {}
        @InvocableVariable global String varCorrelationId;
        @InvocableVariable global String varFlowApiName;
        @InvocableVariable global String varFlowVersion;
        @InvocableVariable global String varFailedElement;
        @InvocableVariable global String varErrorMessage;
        @InvocableVariable global String varObjectApiName;
        @InvocableVariable global String varRecordId;
        @InvocableVariable global String varUserAction;
        @InvocableVariable global String varPageUrl;
        @InvocableVariable global String varContextJson;
        @InvocableVariable(label='Rollback-safe asynchronous capture' description='Publishes capture immediately so it survives transaction rollback. The diagnostic record Id is available asynchronously by correlation id.')
        global Boolean varRollbackSafe;
    }
    global class Response {
        global Response() {}
        @InvocableVariable global Id errorLogId;
        @InvocableVariable global String correlationId;
        @InvocableVariable global String userMessage;
        @InvocableVariable global String severity;
        @InvocableVariable global Boolean success;
        @InvocableVariable global String status;
    }
    /**
     * Preserves the original synchronous diagnostic-Id contract. Rollback-prone fault
     * paths must set varRollbackSafe or use Aegis_Error_Capture_Fault_Subflow instead.
     * Both paths batch their work and preserve one response per request in input order.
     */
    @InvocableMethod(category='Aegis Flow' label='AEIR Capture Flow Fault' description='Captures a Flow fault synchronously, or publishes rollback-safe capture when explicitly requested.')
    global static List<Response> captureFlowFault(List<Request> requests) {
        List<Response> out = new List<Response>();
        if (requests == null || requests.isEmpty()) return out;

        List<AEIR_ErrorCaptureService.ErrorInput> directInputs = new List<AEIR_ErrorCaptureService.ErrorInput>();
        List<AEIR_ErrorCaptureService.ErrorInput> publishedInputs = new List<AEIR_ErrorCaptureService.ErrorInput>();
        List<Integer> directPositions = new List<Integer>();
        List<Integer> publishedPositions = new List<Integer>();
        for (Integer i = 0; i < requests.size(); i++) {
            Request r = requests[i];
            Response response = new Response();
            response.success = false;
            response.status = 'Failed';
            out.add(response);
            if (r == null) {
                response.userMessage = 'A Flow fault request is required.';
                continue;
            }
            AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
            input.correlationId = r.varCorrelationId;
            input.sourceName = r.varFlowApiName;
            input.objectApiName = r.varObjectApiName;
            input.recordId = r.varRecordId;
            input.actionName = r.varUserAction;
            input.pageUrl = r.varPageUrl;
            input.originalMessage = r.varErrorMessage;
            input.contextJson = JSON.serialize(new Map<String, Object>{
                'flowVersion' => r.varFlowVersion,
                'failedElementApiName' => r.varFailedElement,
                'context' => r.varContextJson
            });
            input.sourceType = 'Flow';
            if (r.varRollbackSafe == true) {
                publishedInputs.add(input);
                publishedPositions.add(i);
            } else {
                directInputs.add(input);
                directPositions.add(i);
            }
        }
        List<AEIR_ErrorCaptureService.CaptureResult> directResults =
            AEIR_ErrorCaptureService.captureFromEvents(directInputs);
        for (Integer i = 0; i < directResults.size(); i++) {
            AEIR_ErrorCaptureService.CaptureResult result = directResults[i];
            Response response = out[directPositions[i]];
            response.errorLogId = result.errorLogId;
            response.correlationId = result.correlationId;
            response.userMessage = result.success ? result.normalizedMessage : result.message;
            response.severity = result.severity;
            response.success = result.success;
            response.status = result.status;
        }
        List<AEIR_ErrorCaptureService.PublishResult> publishedResults =
            AEIR_ErrorCaptureService.publishAll(publishedInputs);
        for (Integer i = 0; i < publishedResults.size(); i++) {
            AEIR_ErrorCaptureService.PublishResult result = publishedResults[i];
            Response response = out[publishedPositions[i]];
            response.correlationId = result.correlationId;
            response.userMessage = result.message;
            response.success = result.success;
            response.status = result.success ? 'Published' : 'Failed';
        }
        return out;
    }
}
