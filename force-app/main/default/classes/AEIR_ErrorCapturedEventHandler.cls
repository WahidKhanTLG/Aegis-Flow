public with sharing class AEIR_ErrorCapturedEventHandler {
    public static void handle(List<Error_Captured__e> events) {
        if (events == null || events.isEmpty()) return;
        List<AEIR_ErrorCaptureService.ErrorInput> inputs = new List<AEIR_ErrorCaptureService.ErrorInput>();
        for (Error_Captured__e evt : events) {
            AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
            input.correlationId = evt.Correlation_Id__c;
            input.sourceType = evt.Source_Type__c;
            input.sourceName = evt.Source_Name__c;
            input.originalMessage = evt.Error_Message__c;
            input.recordId = evt.Record_Id__c;
            input.objectApiName = evt.Object_API_Name__c;
            input.contextJson = evt.Context_JSON__c;
            input.severity = evt.Severity__c;
            input.userId = evt.User_Id__c;
            input.stackTrace = evt.Stack_Trace__c;
            input.actionName = evt.Action_Name__c;
            input.pageUrl = evt.Page_URL__c;
            inputs.add(input);
        }
        AEIR_ErrorCaptureService.captureFromEvents(inputs);
    }
}