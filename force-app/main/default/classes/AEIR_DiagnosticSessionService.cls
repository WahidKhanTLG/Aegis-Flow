public with sharing class AEIR_DiagnosticSessionService {
    public class SessionInput {
        @AuraEnabled public String correlationId;
        @AuraEnabled public String contextRecordId;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String pageReferenceJson;
        @AuraEnabled public String pageUrl;
        @AuraEnabled public String browserContextJson;
        @AuraEnabled public String userDescription;
        @AuraEnabled public String detectedIssueType;
        @AuraEnabled public String appName;
        @AuraEnabled public String actionName;
        @AuraEnabled public String createdFrom;
        @AuraEnabled public String userId;
    }
    public class SessionResult {
        @AuraEnabled public Id sessionId;
        @AuraEnabled public String correlationId;
        @AuraEnabled public Id recentErrorLogId;
        @AuraEnabled public String status;
    }
    /** Single-record convenience. Delegates to the bulk path. */
    public static SessionResult createSession(SessionInput input) {
        List<SessionResult> results = createSessions(new List<SessionInput>{ input });
        return results.isEmpty() ? null : results[0];
    }

    /**
     * Bulk session creation.
     *
     * Diagnostic_Session_Requested__e is delivered in batches of up to 200, and the
     * single-record path cost one query plus one insert each, so the SOQL limit was reached
     * at 100 events. Recent errors are now resolved for the whole batch in three queries
     * (one per lookup shape) and the sessions inserted once.
     */
    public static List<SessionResult> createSessions(List<SessionInput> inputs) {
        List<SessionResult> out = new List<SessionResult>();
        if (inputs == null || inputs.isEmpty()) return out;

        List<SessionInput> normalized = new List<SessionInput>();
        List<Id> userIds = new List<Id>();
        for (SessionInput raw : inputs) {
            SessionInput input = raw == null ? new SessionInput() : raw;
            normalized.add(input);
            userIds.add(validUserId(input.userId) ? (Id) input.userId : UserInfo.getUserId());
        }
        Map<String, Id> recentByKey = findRecentErrors(normalized, userIds);

        List<Diagnostic_Session__c> sessions = new List<Diagnostic_Session__c>();
        List<String> correlationIds = new List<String>();
        List<Id> recents = new List<Id>();
        for (Integer i = 0; i < normalized.size(); i++) {
            SessionInput input = normalized[i];
            Id effectiveUserId = userIds[i];
            String cid = String.isBlank(input.correlationId) ? AEIR_CorrelationIdService.nextId() : input.correlationId;
            Id recent = recentByKey.get(recentKey(effectiveUserId, input));
            Diagnostic_Session__c s = new Diagnostic_Session__c();
            s.Correlation_Id__c = cid;
            s.User__c = effectiveUserId;
            s.OwnerId = effectiveUserId;
            s.Context_Record_Id__c = input.contextRecordId;
            s.Object_API_Name__c = input.objectApiName;
            s.Page_Reference_JSON__c = AEIR_SecuritySanitizerService.mask(input.pageReferenceJson);
            s.Page_URL__c = AEIR_SecuritySanitizerService.mask(input.pageUrl);
            s.Browser_Context_JSON__c = AEIR_SecuritySanitizerService.mask(input.browserContextJson);
            s.User_Description__c = AEIR_SecuritySanitizerService.mask(input.userDescription);
            s.Detected_Issue_Type__c = String.isBlank(input.detectedIssueType) ? 'Unknown' : input.detectedIssueType;
            s.Recent_Error_Log__c = recent;
            s.Resolution_Status__c = 'Open';
            s.App_Name__c = input.appName;
            s.Action_Name__c = input.actionName;
            s.Created_From__c = String.isBlank(input.createdFrom) ? 'Help Me Utility' : input.createdFrom;
            sessions.add(s);
            correlationIds.add(cid);
            recents.add(recent);
        }

        Database.insert(sessions, true, AccessLevel.SYSTEM_MODE);

        for (Integer i = 0; i < sessions.size(); i++) {
            SessionResult res = new SessionResult();
            res.sessionId = sessions[i].Id;
            res.correlationId = correlationIds[i];
            res.recentErrorLogId = recents[i];
            res.status = sessions[i].Resolution_Status__c;
            out.add(res);
        }
        return out;
    }

    /**
     * Resolves the most recent error per input in three queries rather than one per input.
     * The three lookup shapes are kept distinct because they are ordered by specificity:
     * a record match beats an object match, which beats "anything this user hit today".
     */
    private static Map<String, Id> findRecentErrors(List<SessionInput> inputs, List<Id> userIds) {
        Map<String, Id> out = new Map<String, Id>();
        Set<Id> allUsers = new Set<Id>(userIds);
        Set<String> recordIds = new Set<String>();
        Set<String> objectNames = new Set<String>();
        for (SessionInput input : inputs) {
            if (!String.isBlank(input.contextRecordId)) recordIds.add(input.contextRecordId);
            else if (!String.isBlank(input.objectApiName)) objectNames.add(input.objectApiName);
        }

        // CreatedDate ASC so the newest row overwrites, matching the per-input ORDER BY DESC LIMIT 1.
        if (!recordIds.isEmpty()) {
            for (Error_Log__c log : [
                SELECT Id, User__c, Record_Id__c FROM Error_Log__c
                WHERE User__c IN :allUsers AND Record_Id__c IN :recordIds AND CreatedDate = LAST_N_DAYS:1
                ORDER BY CreatedDate ASC
            ]) {
                out.put('R|' + log.User__c + '|' + log.Record_Id__c, log.Id);
            }
        }
        if (!objectNames.isEmpty()) {
            for (Error_Log__c log : [
                SELECT Id, User__c, Object_API_Name__c FROM Error_Log__c
                WHERE User__c IN :allUsers AND Object_API_Name__c IN :objectNames AND CreatedDate = LAST_N_DAYS:1
                ORDER BY CreatedDate ASC
            ]) {
                out.put('O|' + log.User__c + '|' + log.Object_API_Name__c, log.Id);
            }
        }
        for (Error_Log__c log : [
            SELECT Id, User__c FROM Error_Log__c
            WHERE User__c IN :allUsers AND CreatedDate = LAST_N_DAYS:1
            ORDER BY CreatedDate ASC
        ]) {
            out.put('U|' + log.User__c, log.Id);
        }
        return out;
    }

    private static String recentKey(Id userId, SessionInput input) {
        if (!String.isBlank(input.contextRecordId)) return 'R|' + userId + '|' + input.contextRecordId;
        if (!String.isBlank(input.objectApiName)) return 'O|' + userId + '|' + input.objectApiName;
        return 'U|' + userId;
    }

    private static Boolean validUserId(String userId) {
        return !String.isBlank(userId) && (userId.length() == 15 || userId.length() == 18) && userId.startsWith('005');
    }
    public static Id findRecentError(Id userId, String recordId, String objectApiName) {
        List<Error_Log__c> logs;
        if (!String.isBlank(recordId)) {
            logs = [SELECT Id FROM Error_Log__c WHERE User__c = :userId AND Record_Id__c = :recordId AND CreatedDate = LAST_N_DAYS:1 ORDER BY CreatedDate DESC LIMIT 1];
        } else if (!String.isBlank(objectApiName)) {
            logs = [SELECT Id FROM Error_Log__c WHERE User__c = :userId AND Object_API_Name__c = :objectApiName AND CreatedDate = LAST_N_DAYS:1 ORDER BY CreatedDate DESC LIMIT 1];
        } else {
            logs = [SELECT Id FROM Error_Log__c WHERE User__c = :userId AND CreatedDate = LAST_N_DAYS:1 ORDER BY CreatedDate DESC LIMIT 1];
        }
        return logs.isEmpty() ? null : logs[0].Id;
    }
}
