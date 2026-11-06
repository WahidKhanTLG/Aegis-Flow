public with sharing class AEIR_DiagnosticSessionService {
    private static final Integer MAX_BATCH = 2000;
    private static final Integer MAX_RECENT_CANDIDATES = 5000;
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
        @AuraEnabled public String message;
    }
    public static SessionResult createSession(SessionInput input) {
        List<SessionResult> results = createSessions(new List<SessionInput>{ input });
        return results.isEmpty() ? null : results[0];
    }

    /** Trusted server adapters may supply the affected user; browser controllers bind it. */
    public static List<SessionResult> createSessions(List<SessionInput> inputs) {
        List<SessionResult> out = new List<SessionResult>();
        if (inputs == null || inputs.isEmpty()) return out;
        List<SessionInput> valid = new List<SessionInput>();
        List<Integer> positions = new List<Integer>();
        List<Id> userIds = new List<Id>();
        Map<String, Schema.SObjectType> objectTypes = Schema.getGlobalDescribe();
        for (Integer i = 0; i < inputs.size(); i++) {
            SessionResult result = new SessionResult();
            result.status = 'Failed';
            out.add(result);
            SessionInput input = inputs[i];
            String invalid = i >= MAX_BATCH ? 'A session batch supports at most 2000 entries.' : validateInput(input, objectTypes);
            if (invalid != null) { result.message = invalid; continue; }
            Id affectedUser = String.isBlank(input.userId) ? UserInfo.getUserId() : (Id) input.userId;
            valid.add(input);
            positions.add(i);
            userIds.add(affectedUser);
        }
        if (valid.isEmpty()) return out;
        Set<Id> requestedUsers = new Set<Id>(userIds);
        Map<Id, User> activeUsers = new Map<Id, User>([SELECT Id FROM User WHERE Id IN :requestedUsers AND IsActive = true]);
        Map<String, Id> recentByKey = findRecentErrors(valid, userIds);
        List<Diagnostic_Session__c> sessions = new List<Diagnostic_Session__c>();
        List<Integer> sessionPositions = new List<Integer>();
        for (Integer i = 0; i < valid.size(); i++) {
            SessionInput input = valid[i];
            SessionResult result = out[positions[i]];
            if (!activeUsers.containsKey(userIds[i])) {
                result.message = 'The affected user is invalid or inactive.';
                continue;
            }
            String correlation = String.isBlank(input.correlationId) ? AEIR_CorrelationIdService.nextId() : input.correlationId.trim();
            result.correlationId = correlation;
            Id recent = recentByKey.get(recentKey(userIds[i], input));
            sessions.add(new Diagnostic_Session__c(
                Correlation_Id__c = correlation, User__c = userIds[i], OwnerId = userIds[i],
                Context_Record_Id__c = input.contextRecordId, Object_API_Name__c = input.objectApiName,
                Page_Reference_JSON__c = AEIR_SecuritySanitizerService.mask(input.pageReferenceJson),
                Page_URL__c = AEIR_SecuritySanitizerService.mask(input.pageUrl),
                Browser_Context_JSON__c = AEIR_SecuritySanitizerService.mask(input.browserContextJson),
                User_Description__c = AEIR_SecuritySanitizerService.mask(input.userDescription),
                Detected_Issue_Type__c = String.isBlank(input.detectedIssueType) ? 'Unknown' : input.detectedIssueType,
                Recent_Error_Log__c = recent, Resolution_Status__c = 'Open',
                App_Name__c = input.appName, Action_Name__c = input.actionName,
                Created_From__c = String.isBlank(input.createdFrom) ? 'Help Me Utility' : input.createdFrom));
            sessionPositions.add(positions[i]);
        }
        if (sessions.isEmpty()) return out;
        // One invalid picklist, oversized masked value, or rejected owner must not undo
        // unrelated valid requests. Preserve the original input order in every result.
        List<Database.SaveResult> saved = Database.insert(sessions, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < sessions.size(); i++) {
            SessionResult result = out[sessionPositions[i]];
            if (!saved[i].isSuccess()) {
                result.message = 'The diagnostic session could not be created. Review its input and configuration.';
                continue;
            }
            result.sessionId = saved[i].getId();
            result.recentErrorLogId = sessions[i].Recent_Error_Log__c;
            result.status = 'Open';
            result.message = 'Diagnostic session created.';
        }
        return out;
    }

    private static String validateInput(SessionInput input, Map<String, Schema.SObjectType> objectTypes) {
        if (input == null) return 'Diagnostic session input is required.';
        List<String> values = new List<String>{ input.correlationId, input.contextRecordId, input.objectApiName,
            input.pageReferenceJson, input.pageUrl, input.browserContextJson, input.userDescription,
            input.appName, input.actionName, input.createdFrom, input.detectedIssueType };
        List<Integer> limits = new List<Integer>{ 80, 18, 100, 32768, 32768, 32768, 32768, 120, 255, 120, 120 };
        for (Integer i = 0; i < values.size(); i++) {
            if (values[i] != null && values[i].length() > limits[i]) return 'A diagnostic input exceeds its supported field length.';
        }
        if (!String.isBlank(input.userId)) {
            if (input.userId.length() != 15 && input.userId.length() != 18) return 'A valid affected user id is required.';
            try {
                if (((Id) input.userId).getSObjectType() != User.SObjectType) return 'A valid affected user id is required.';
            } catch (Exception invalidUser) { return 'A valid affected user id is required.'; }
        }
        if (!String.isBlank(input.objectApiName) && !objectTypes.containsKey(input.objectApiName)) {
            return 'A valid object API name is required.';
        }
        if (!String.isBlank(input.contextRecordId)) {
            try {
                Id recordId = (Id) input.contextRecordId;
                if (!String.isBlank(input.objectApiName) && recordId.getSObjectType() != objectTypes.get(input.objectApiName)) {
                    return 'The context record does not belong to the supplied object.';
                }
                if (String.isBlank(input.objectApiName)) input.objectApiName = recordId.getSObjectType().getDescribe().getName();
                input.contextRecordId = String.valueOf(recordId);
            } catch (Exception invalidRecord) { return 'A valid context record id is required.'; }
        }
        return null;
    }

    /** A bounded recent window prevents a noisy source from consuming all query rows. */
    private static Map<String, Id> findRecentErrors(List<SessionInput> inputs, List<Id> userIds) {
        Map<String, Id> out = new Map<String, Id>();
        Set<Id> allUsers = new Set<Id>(userIds);
        Set<Id> unscopedUsers = new Set<Id>();
        Set<String> recordIds = new Set<String>();
        Set<String> objectNames = new Set<String>();
        for (Integer i = 0; i < inputs.size(); i++) {
            SessionInput input = inputs[i];
            if (!String.isBlank(input.contextRecordId)) recordIds.add(input.contextRecordId);
            else if (!String.isBlank(input.objectApiName)) objectNames.add(input.objectApiName);
            else unscopedUsers.add(userIds[i]);
        }
        if (!recordIds.isEmpty()) {
            for (Error_Log__c log : [SELECT Id, User__c, Record_Id__c FROM Error_Log__c
                    WHERE User__c IN :allUsers AND Record_Id__c IN :recordIds AND CreatedDate = LAST_N_DAYS:1
                    ORDER BY CreatedDate DESC, Id DESC LIMIT :MAX_RECENT_CANDIDATES]) {
                String key = 'R|' + log.User__c + '|' + log.Record_Id__c;
                if (!out.containsKey(key)) out.put(key, log.Id);
            }
        }
        if (!objectNames.isEmpty()) {
            for (Error_Log__c log : [SELECT Id, User__c, Object_API_Name__c FROM Error_Log__c
                    WHERE User__c IN :allUsers AND Object_API_Name__c IN :objectNames AND CreatedDate = LAST_N_DAYS:1
                    ORDER BY CreatedDate DESC, Id DESC LIMIT :MAX_RECENT_CANDIDATES]) {
                String key = 'O|' + log.User__c + '|' + log.Object_API_Name__c;
                if (!out.containsKey(key)) out.put(key, log.Id);
            }
        }
        if (!unscopedUsers.isEmpty()) {
            for (Error_Log__c log : [SELECT Id, User__c FROM Error_Log__c
                    WHERE User__c IN :unscopedUsers AND CreatedDate = LAST_N_DAYS:1
                    ORDER BY CreatedDate DESC, Id DESC LIMIT :MAX_RECENT_CANDIDATES]) {
                String key = 'U|' + log.User__c;
                if (!out.containsKey(key)) out.put(key, log.Id);
            }
        }
        return out;
    }

    private static String recentKey(Id userId, SessionInput input) {
        if (!String.isBlank(input.contextRecordId)) return 'R|' + userId + '|' + input.contextRecordId;
        if (!String.isBlank(input.objectApiName)) return 'O|' + userId + '|' + input.objectApiName;
        return 'U|' + userId;
    }

    public static Id findRecentError(Id userId, String recordId, String objectApiName) {
        List<Error_Log__c> logs;
        if (!String.isBlank(recordId)) {
            logs = [SELECT Id FROM Error_Log__c WHERE User__c = :userId AND Record_Id__c = :recordId AND CreatedDate = LAST_N_DAYS:1 ORDER BY CreatedDate DESC, Id DESC LIMIT 1];
        } else if (!String.isBlank(objectApiName)) {
            logs = [SELECT Id FROM Error_Log__c WHERE User__c = :userId AND Object_API_Name__c = :objectApiName AND CreatedDate = LAST_N_DAYS:1 ORDER BY CreatedDate DESC, Id DESC LIMIT 1];
        } else {
            logs = [SELECT Id FROM Error_Log__c WHERE User__c = :userId AND CreatedDate = LAST_N_DAYS:1 ORDER BY CreatedDate DESC, Id DESC LIMIT 1];
        }
        return logs.isEmpty() ? null : logs[0].Id;
    }
}
