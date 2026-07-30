public with sharing class AEIR_ClientErrorController {
    @AuraEnabled
    public static AEIR_ErrorCaptureService.CaptureResult reportClientError(String correlationId, String componentName, String message, String stackTrace, String pageUrl, String userAgent) {
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.correlationId = correlationId;
        input.sourceType = 'LWC';
        input.sourceName = componentName;
        input.pageUrl = pageUrl;
        input.originalMessage = message;
        input.stackTrace = stackTrace;
        input.contextJson = JSON.serialize(new Map<String,Object>{ 'userAgent' => userAgent, 'componentName' => componentName });
        return AEIR_ErrorCaptureService.capture(input);
    }
}