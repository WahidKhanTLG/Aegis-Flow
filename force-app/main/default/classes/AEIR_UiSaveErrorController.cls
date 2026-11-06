public with sharing class AEIR_UiSaveErrorController {
    /**
     * Captures a validation or save error that surfaced through a custom Aegis UI form.
     * The transaction is client-side and has already failed, so we write Error_Log__c
     * directly and rely on AEIR_ErrorCaptureService.capture to trigger user notification.
     */
    @AuraEnabled
    public static AEIR_ErrorCaptureService.CaptureResult reportUiSaveError(
        String correlationId,
        String objectApiName,
        String recordId,
        String recordName,
        String userAction,
        String errorMessage,
        String fieldErrorsJson,
        String pageUrl
    ) {
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.correlationId = correlationId;
        input.sourceType = 'LWC';
        input.sourceName = String.isBlank(recordName)
            ? objectApiName
            : objectApiName + ' / ' + recordName;
        input.objectApiName = objectApiName;
        input.recordId = recordId;
        input.actionName = userAction;
        input.originalMessage = errorMessage;
        input.contextJson = fieldErrorsJson;
        input.pageUrl = pageUrl;
        // Bind to the server-side user; never trust the browser for attribution.
        input.userId = UserInfo.getUserId();
        return AEIR_ErrorCaptureService.capture(input);
    }

    /**
     * Manual screen capture for standard Salesforce pages where Aegis cannot intercept
     * the platform save pipeline. The user describes what they saw and Aegis preserves
     * page context, record context, and browser metadata for triage.
     */
    @AuraEnabled
    public static AEIR_ErrorCaptureService.CaptureResult reportScreenIssue(
        String description,
        String pageUrl,
        String recordId,
        String objectApiName,
        String userAgent
    ) {
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.sourceType = 'LWC';
        input.sourceName = 'Manual screen capture';
        input.objectApiName = objectApiName;
        input.recordId = recordId;
        input.actionName = 'User reported screen issue';
        input.originalMessage = String.isBlank(description)
            ? 'User captured screen issue.'
            : description;
        input.contextJson = JSON.serialize(new Map<String, Object>{
            'pageUrl' => pageUrl,
            'userAgent' => userAgent,
            'objectApiName' => objectApiName,
            'recordId' => recordId
        });
        input.pageUrl = pageUrl;
        input.userId = UserInfo.getUserId();
        return AEIR_ErrorCaptureService.capture(input);
    }
}
