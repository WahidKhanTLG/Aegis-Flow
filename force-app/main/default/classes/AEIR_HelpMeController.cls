public with sharing class AEIR_HelpMeController {
    public class HelpMeResponse {
        @AuraEnabled public Id sessionId;
        @AuraEnabled public String correlationId;
        @AuraEnabled public Id recentErrorLogId;
        @AuraEnabled public String message;
    }
    @AuraEnabled
    public static HelpMeResponse createSession(String contextJson, String userDescription, String detectedIssueType) {
        Map<String,Object> ctx = parse(contextJson);
        AEIR_DiagnosticSessionService.SessionInput input = new AEIR_DiagnosticSessionService.SessionInput();
        input.correlationId = (String) ctx.get('correlationId');
        input.contextRecordId = (String) ctx.get('recordId');
        input.objectApiName = (String) ctx.get('objectApiName');
        input.pageUrl = (String) ctx.get('pageUrl');
        input.pageReferenceJson = JSON.serialize(ctx.get('pageReference'));
        input.browserContextJson = contextJson;
        input.userDescription = userDescription;
        input.detectedIssueType = String.isBlank(detectedIssueType) ? 'Unknown' : detectedIssueType;
        input.createdFrom = 'Help Me Utility';
        AEIR_DiagnosticSessionService.SessionResult sr = AEIR_DiagnosticSessionService.createSession(input);
        HelpMeResponse r = new HelpMeResponse();
        r.sessionId = sr.sessionId; r.correlationId = sr.correlationId; r.recentErrorLogId = sr.recentErrorLogId; r.message = sr.recentErrorLogId == null ? 'Diagnostic session created. No recent technical error was detected.' : 'Diagnostic session created and linked to a recent error.'; return r;
    }
    @AuraEnabled
    public static AEIR_AgentforceGatewayService.DiagnosisResult diagnoseSession(Id sessionId) {
        return AEIR_AgentforceGatewayService.diagnoseSession(sessionId);
    }
    @AuraEnabled
    public static AEIR_EscalationService.EscalationResult escalateSession(Id sessionId, String userDescription) {
        if (!String.isBlank(userDescription)) {
            Diagnostic_Session__c s = [SELECT Id, User_Description__c FROM Diagnostic_Session__c WHERE Id = :sessionId LIMIT 1];
            s.User_Description__c = AEIR_SecuritySanitizerService.mask(userDescription);
            update s;
        }
        return AEIR_EscalationService.createForSession(sessionId, null, true);
    }
    @AuraEnabled(cacheable=true)
    public static List<Error_Log__c> getRecentErrors(String recordId, String objectApiName) {
        if (!String.isBlank(recordId)) return [SELECT Id, Name, Correlation_Id__c, Error_Category__c, Severity__c, Source_Type__c, Normalized_Message__c, Status__c, CreatedDate FROM Error_Log__c WHERE Record_Id__c = :recordId ORDER BY CreatedDate DESC LIMIT 5];
        if (!String.isBlank(objectApiName)) return [SELECT Id, Name, Correlation_Id__c, Error_Category__c, Severity__c, Source_Type__c, Normalized_Message__c, Status__c, CreatedDate FROM Error_Log__c WHERE Object_API_Name__c = :objectApiName ORDER BY CreatedDate DESC LIMIT 5];
        Id uid = UserInfo.getUserId();
        return [SELECT Id, Name, Correlation_Id__c, Error_Category__c, Severity__c, Source_Type__c, Normalized_Message__c, Status__c, CreatedDate FROM Error_Log__c WHERE User__c = :uid ORDER BY CreatedDate DESC LIMIT 5];
    }
    private static Map<String,Object> parse(String contextJson) {
        if (String.isBlank(contextJson)) return new Map<String,Object>();
        try {
            return (Map<String,Object>) JSON.deserializeUntyped(contextJson);
        } catch (Exception ex) {
            return new Map<String,Object>();
        }
    }
}