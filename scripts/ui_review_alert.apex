AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
input.correlationId = 'UI-REVIEW-' + String.valueOf(Datetime.now().getTime());
input.sourceType = 'Flow';
input.sourceName = 'Aegis UI Review Probe / Validation Rule';
input.objectApiName = 'Order';
input.actionName = 'Review utility alert signal';
input.severity = 'Critical';
input.originalMessage = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: Aegis review probe blocked the Order Flow.';
input.contextJson = JSON.serialize(new Map<String, Object>{
    'scenario' => 'ui-review-alert',
    'capturedBy' => 'scripts/ui_review_alert.apex',
    'note' => 'Creates one alert for authenticated utility-bar validation. Dismiss from the utility after review.'
});

AEIR_ErrorCaptureService.CaptureResult result = AEIR_ErrorCaptureService.capture(input);
System.debug('AEIR_UI_REVIEW_ALERT correlationId=' + result.correlationId + ' errorLogId=' + result.errorLogId);
