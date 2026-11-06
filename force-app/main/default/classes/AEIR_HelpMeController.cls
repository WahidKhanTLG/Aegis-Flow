public with sharing class AEIR_HelpMeController {
    private static final Integer MAX_CONTEXT = 32768;
    public class HelpMeResponse {
        @AuraEnabled public Id sessionId;
        @AuraEnabled public String correlationId;
        @AuraEnabled public Id recentErrorLogId;
        @AuraEnabled public String message;
    }
    @AuraEnabled
    public static HelpMeResponse createSession(String contextJson, String userDescription, String detectedIssueType) {
        Map<String, Object> context = parse(contextJson);
        if (userDescription != null && userDescription.length() > MAX_CONTEXT) {
            throw safeError('The help description exceeds the supported length.');
        }
        Object pageReference = context.get('pageReference');
        if (pageReference != null && !(pageReference instanceof Map<String, Object>)) {
            throw safeError('The page reference must be a JSON object.');
        }
        AEIR_DiagnosticSessionService.SessionInput input = new AEIR_DiagnosticSessionService.SessionInput();
        input.correlationId = stringField(context, 'correlationId');
        input.contextRecordId = stringField(context, 'recordId');
        input.objectApiName = stringField(context, 'objectApiName');
        input.pageUrl = stringField(context, 'pageUrl');
        input.pageReferenceJson = pageReference == null ? null : JSON.serialize(pageReference);
        input.browserContextJson = contextJson;
        input.userDescription = userDescription;
        input.detectedIssueType = String.isBlank(detectedIssueType) ? 'Unknown' : detectedIssueType;
        input.createdFrom = 'Help Me Utility';
        // Browser/headless Help Me payloads cannot impersonate another affected user.
        // Trusted server adapters call SessionService directly when attribution differs.
        input.userId = String.valueOf(UserInfo.getUserId());
        AEIR_DiagnosticSessionService.SessionResult session = AEIR_DiagnosticSessionService.createSession(input);
        if (session == null || session.sessionId == null) {
            throw safeError(session == null || String.isBlank(session.message)
                ? 'The diagnostic session could not be created.' : session.message);
        }
        HelpMeResponse response = new HelpMeResponse();
        response.sessionId = session.sessionId;
        response.correlationId = session.correlationId;
        response.recentErrorLogId = session.recentErrorLogId;
        response.message = session.recentErrorLogId == null
            ? 'Diagnostic session created. No recent technical error was detected.'
            : 'Diagnostic session created and linked to a recent error.';
        return response;
    }

    @AuraEnabled
    public static AEIR_AgentforceGatewayService.DiagnosisResult diagnoseSession(Id sessionId) {
        authorizeSession(sessionId);
        return AEIR_AgentforceGatewayService.diagnoseSession(sessionId);
    }

    @AuraEnabled
    public static AEIR_EscalationService.EscalationResult escalateSession(Id sessionId, String userDescription) {
        Diagnostic_Session__c session = authorizeSession(sessionId);
        if (userDescription != null && userDescription.length() > MAX_CONTEXT) {
            throw safeError('The help description exceeds the supported length.');
        }
        if (!String.isBlank(userDescription)) {
            session.User_Description__c = AEIR_SecuritySanitizerService.mask(userDescription);
            update session;
        }
        return AEIR_EscalationService.createForSession(sessionId, null, true);
    }

    private static Diagnostic_Session__c authorizeSession(Id sessionId) {
        if (sessionId == null || sessionId.getSObjectType() != Diagnostic_Session__c.SObjectType) {
            throw safeError('A valid diagnostic session id is required.');
        }
        List<Diagnostic_Session__c> sessions = [SELECT Id, User__c, OwnerId, Recent_Error_Log__c, User_Description__c
            FROM Diagnostic_Session__c WHERE Id = :sessionId LIMIT 1];
        Boolean sensitiveRole = FeatureManagement.checkPermission('AEIR_View_Sensitive_Context');
        Id caller = UserInfo.getUserId();
        if (sessions.isEmpty() || (!sensitiveRole && sessions[0].User__c != caller
            && !(sessions[0].User__c == null && sessions[0].OwnerId == caller))) {
            throw safeError('The diagnostic session is unavailable or not authorized.');
        }
        Diagnostic_Session__c session = sessions[0];
        if (session.Recent_Error_Log__c != null) {
            List<Error_Log__c> logs = [SELECT Id, User__c FROM Error_Log__c WHERE Id = :session.Recent_Error_Log__c LIMIT 1];
            if (logs.isEmpty() || (!sensitiveRole && logs[0].User__c != caller)) {
                throw safeError('The linked diagnostic is unavailable or not authorized.');
            }
        }
        return session;
    }

    @AuraEnabled(cacheable=true)
    public static List<Error_Log__c> getRecentErrors(String recordId, String objectApiName) {
        Map<String, Schema.SObjectType> objectTypes = Schema.getGlobalDescribe();
        if (!String.isBlank(objectApiName) && (objectApiName.length() > 100 || !objectTypes.containsKey(objectApiName))) {
            throw safeError('A valid object API name is required.');
        }
        if (!String.isBlank(recordId)) {
            if (recordId.length() != 15 && recordId.length() != 18) throw safeError('A valid context record id is required.');
            try {
                Id contextId = (Id) recordId;
                if (!String.isBlank(objectApiName) && contextId.getSObjectType() != objectTypes.get(objectApiName)) {
                    throw safeError('The context record does not belong to the supplied object.');
                }
                recordId = String.valueOf(contextId);
            } catch (AuraHandledException rejected) { throw rejected; }
            catch (Exception invalidId) { throw safeError('A valid context record id is required.'); }
        }
        Id currentUserId = UserInfo.getUserId();
        Boolean sensitiveRole = FeatureManagement.checkPermission('AEIR_View_Sensitive_Context');
        String query = 'SELECT Id, Name, Correlation_Id__c, Error_Category__c, Severity__c, Source_Type__c, '
            + 'Normalized_Message__c, Status__c, CreatedDate FROM Error_Log__c WHERE ';
        if (!String.isBlank(recordId)) query += 'Record_Id__c = :recordId';
        else if (!String.isBlank(objectApiName)) query += 'Object_API_Name__c = :objectApiName';
        else query += 'User__c = :currentUserId';
        if (!sensitiveRole) query += ' AND User__c = :currentUserId';
        query += ' ORDER BY CreatedDate DESC, Id DESC LIMIT 5';
        return Database.query(query);
    }

    private static String stringField(Map<String, Object> context, String key) {
        Object value = context.get(key);
        if (value == null) return null;
        if (!(value instanceof String)) throw safeError('Diagnostic context fields must have the expected text type.');
        return (String) value;
    }

    private static Map<String, Object> parse(String contextJson) {
        if (String.isBlank(contextJson)) return new Map<String, Object>();
        if (contextJson.length() > MAX_CONTEXT) throw safeError('The diagnostic context exceeds the supported length.');
        try {
            Object parsed = JSON.deserializeUntyped(contextJson);
            if (!(parsed instanceof Map<String, Object>)) throw safeError('Diagnostic context must be a JSON object.');
            return (Map<String, Object>) parsed;
        } catch (AuraHandledException rejected) { throw rejected; }
        catch (Exception invalidJson) { throw safeError('Diagnostic context must be a valid JSON object.'); }
    }

    private static AuraHandledException safeError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
