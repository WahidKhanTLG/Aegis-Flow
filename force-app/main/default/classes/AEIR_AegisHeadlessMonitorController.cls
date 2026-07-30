public with sharing class AEIR_AegisHeadlessMonitorController {
    /**
     * Surface_Config__mdt gating so an admin can disable the utility, mobile polling, or
     * Experience Cloud surfaces without removing the component (spec section 9).
     */
    @AuraEnabled(cacheable=true)
    public static AEIR_PolicyConfigService.SurfaceSettings getSurfaceSettings() {
        return AEIR_PolicyConfigService.resolveSurface();
    }

    /** Namespace-safe channel for empApi; never hardcode the event name in JavaScript. */
    @AuraEnabled(cacheable=true)
    public static AEIR_NotificationPolicyService.AlertBehavior getAlertBehavior() {
        return AEIR_NotificationPolicyService.getAlertBehavior();
    }

    /**
     * Real-time Flow failure capture.
     *
     * FlowExecutionErrorEvent fires the instant a Flow element fails. It is not
     * triggerable from Apex and not queryable, so the browser subscribes to it and hands
     * the payload here. That removes the polling delay for a user who is watching, and
     * unlike FlowInterview the event carries ContextRecordId, so the escalation gets a
     * record snapshot.
     *
     * The correlation id matches AEIR_FlowInterviewMonitor exactly, so if the scheduled
     * poll later sees the same interview it dedupes on the unique external id instead of
     * creating a second log.
     */
    @AuraEnabled
    public static String captureFlowError(String payloadJson) {
        if (String.isBlank(payloadJson)) return null;
        Map<String, Object> p;
        try {
            p = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
        } catch (Exception parseError) {
            return null;
        }
        String guid = str(p.get('InterviewGuid'));
        String correlationId = String.isBlank(guid)
            ? 'FLOWEVT-' + str(p.get('EventUuid'))
            : 'FLOWINT-' + guid;

        String flowName = str(p.get('FlowApiName'));
        String element = str(p.get('ElementApiName'));

        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.correlationId = correlationId;
        input.sourceType = 'Flow';
        input.sourceName = String.isBlank(element)
            ? blankTo(flowName, 'Unknown Flow')
            : blankTo(flowName, 'Unknown Flow') + ' / ' + element;
        input.originalMessage = str(p.get('ErrorMessage'));
        input.actionName = 'Flow element: ' + blankTo(element, 'Unknown');
        input.recordId = str(p.get('ContextRecordId'));
        input.objectApiName = str(p.get('ContextObject'));
        input.userId = firstNonBlank(str(p.get('UserId')), str(p.get('InterviewStartedById')));
        input.contextJson = JSON.serialize(new Map<String, Object>{
            'flowApiName' => flowName,
            'flowVersion' => p.get('FlowVersionNumber'),
            'failedElement' => element,
            'elementType' => p.get('ElementType'),
            'extendedErrorCode' => p.get('ExtendedErrorCode'),
            'processType' => p.get('ProcessType'),
            'contextRecordId' => p.get('ContextRecordId'),
            'relatedRecordId' => p.get('RelatedRecordId'),
            'capturedBy' => 'FlowExecutionErrorEvent (real time, no fault path required)'
        });
        try {
            return AEIR_ErrorCaptureService.capture(input).correlationId;
        } catch (Exception captureFailure) {
            System.debug(LoggingLevel.WARN,
                'Aegis Flow: real-time Flow capture failed: ' + captureFailure.getMessage());
            return null;
        }
    }

    /** Channel for the real-time Flow error stream. */
    @AuraEnabled(cacheable=true)
    public static String getFlowErrorChannel() {
        return '/event/FlowExecutionErrorEvent';
    }

    private static String str(Object value) { return value == null ? null : String.valueOf(value); }
    private static String blankTo(String v, String f) { return String.isBlank(v) ? f : v; }
    private static String firstNonBlank(String a, String b) { return String.isBlank(a) ? b : a; }

    @AuraEnabled(cacheable=true)
    public static String getAlertChannel() {
        return '/event/' + Aegis_User_Alert__e.SObjectType.getDescribe().getName();
    }

    @AuraEnabled
    public static Id submitFeedback(String feedbackJson) {
        return AEIR_FeedbackService.submitFeedbackJson(feedbackJson);
    }

    @AuraEnabled(cacheable=true)
    public static List<AEIR_UserNotificationService.AlertDTO> getOpenAlerts() {
        return AEIR_UserNotificationService.getOpenAlerts();
    }
    @AuraEnabled
    public static AEIR_UserNotificationService.DetailDTO getAlertDetails(String correlationId) {
        return AEIR_UserNotificationService.getAlertDetails(correlationId);
    }
    @AuraEnabled
    public static void dismissAlert(String correlationId) {
        AEIR_UserNotificationService.dismiss(correlationId);
    }
    @AuraEnabled
    public static AEIR_HelpMeController.HelpMeResponse startHelpFromAlert(String correlationId, String contextJson, String userDescription) {
        AEIR_UserNotificationService.DetailDTO detail = AEIR_UserNotificationService.getAlertDetails(correlationId);
        Map<String,Object> contextMap = new Map<String,Object>();
        if (!String.isBlank(contextJson)) {
            try { contextMap = (Map<String,Object>) JSON.deserializeUntyped(contextJson); } catch (Exception ex) { contextMap = new Map<String,Object>(); }
        }
        contextMap.put('correlationId', correlationId);
        if (detail != null && detail.errorLog != null) {
            contextMap.put('recordId', detail.errorLog.Record_Id__c);
            contextMap.put('objectApiName', detail.errorLog.Object_API_Name__c);
            contextMap.put('pageUrl', detail.errorLog.Page_URL__c);
        }
        return AEIR_HelpMeController.createSession(JSON.serialize(contextMap), String.isBlank(userDescription) ? 'User requested help from an Aegis Flow alert.' : userDescription, 'Process Failed');
    }
    @AuraEnabled
    public static AEIR_EscalationService.EscalationResult escalateAlert(String correlationId) {
        AEIR_UserNotificationService.DetailDTO detail = AEIR_UserNotificationService.getAlertDetails(correlationId);
        if (detail == null || detail.errorLog == null) throw new AuraHandledException('No error log is available for escalation.');
        return AEIR_EscalationService.createForError(detail.errorLog.Id, null, true);
    }
}