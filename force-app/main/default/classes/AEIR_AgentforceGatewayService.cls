public with sharing class AEIR_AgentforceGatewayService {
    public class DiagnosisResult {
        @AuraEnabled public Id diagnosisId;
        @AuraEnabled public String summary;
        @AuraEnabled public String rootCause;
        @AuraEnabled public String fixability;
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public String recommendedAction;
        @AuraEnabled public Boolean needsUserInput;
        @AuraEnabled public Boolean escalationRequired;
        @AuraEnabled public String safeRemediationActionKey;
    }

    /** Single-record convenience. Delegates to the bulk path. */
    public static DiagnosisResult diagnoseError(Id errorLogId) {
        Map<Id, DiagnosisResult> results = diagnoseErrors(new List<Id>{ errorLogId });
        return results.get(errorLogId);
    }

    /**
     * Bulk diagnosis.
     *
     * Diagnosis is requested by a platform event, and the platform delivers up to 200 events
     * per batch. The single-record path cost one query, one insert, one update and a
     * notification (itself a query, an update and an insert) per log - roughly six operations.
     * An error storm therefore blew the limit at about thirty logs and the batch was retried
     * and discarded, leaving every affected user staring at an unresolved spinner.
     *
     * @return diagnosis results keyed by error log id
     */
    public static Map<Id, DiagnosisResult> diagnoseErrors(List<Id> errorLogIds) {
        Map<Id, DiagnosisResult> out = new Map<Id, DiagnosisResult>();
        if (errorLogIds == null || errorLogIds.isEmpty()) return out;

        List<Error_Log__c> logs = [
            SELECT Id, Correlation_Id__c, Error_Category__c, Severity__c, Source_Type__c, Source_Name__c,
                   Original_Error_Message__c, Normalized_Message__c, Object_API_Name__c, Record_Id__c,
                   Page_URL__c, Context_JSON__c, Retry_Eligible__c, User__c
            FROM Error_Log__c WHERE Id IN :errorLogIds
        ];
        if (logs.isEmpty()) return out;

        // Snapshots batched by object, so cost scales with distinct objects not records.
        Map<String, Set<String>> idsByObject = new Map<String, Set<String>>();
        for (Error_Log__c log : logs) {
            if (String.isBlank(log.Object_API_Name__c) || String.isBlank(log.Record_Id__c)) continue;
            if (!idsByObject.containsKey(log.Object_API_Name__c)) {
                idsByObject.put(log.Object_API_Name__c, new Set<String>());
            }
            idsByObject.get(log.Object_API_Name__c).add(log.Record_Id__c);
        }
        Map<String, String> snapshots = AEIR_ContextSnapshotService.getSnapshots(idsByObject, false);

        List<AI_Diagnosis__c> diagnoses = new List<AI_Diagnosis__c>();
        List<Error_Log__c> ordered = new List<Error_Log__c>();
        Map<Id, String> fixabilityByLog = new Map<Id, String>();
        Map<Id, String> summaryByLog = new Map<Id, String>();

        for (Error_Log__c log : logs) {
            AEIR_ErrorNormalizationService.Classification c =
                AEIR_ErrorNormalizationService.classify(log.Original_Error_Message__c);
            DiagnosisResult r = buildResult(log.Error_Category__c, log.Normalized_Message__c, c, log.Retry_Eligible__c);

            AI_Diagnosis__c d = new AI_Diagnosis__c();
            d.Error_Log__c = log.Id;
            d.Correlation_Id__c = log.Correlation_Id__c;
            d.Summary__c = r.summary;
            d.Root_Cause__c = r.rootCause;
            d.Fixability__c = r.fixability;
            d.Confidence__c = r.confidence;
            d.Recommended_Action__c = r.recommendedAction;
            d.Needs_User_Input__c = r.needsUserInput;
            d.Escalation_Required__c = r.escalationRequired;
            d.Safe_Remediation_Action_Key__c = r.safeRemediationActionKey;
            d.Agent_Status__c = 'Deterministic Fallback';
            d.Input_Payload_JSON__c = buildPayload(log, null, snapshots.get(log.Record_Id__c));
            d.Output_JSON__c = JSON.serialize(r);

            diagnoses.add(d);
            ordered.add(log);
            out.put(log.Id, r);
            fixabilityByLog.put(log.Id, r.fixability);
            summaryByLog.put(log.Id, r.summary);

            log.Agentforce_Status__c = 'Completed';
            log.Status__c = 'Diagnosed';
        }

        insert diagnoses;
        for (Integer i = 0; i < ordered.size(); i++) {
            out.get(ordered[i].Id).diagnosisId = diagnoses[i].Id;
        }
        update logs;

        // Closes the async round trip so the utility bar replaces its spinner with the outcome.
        AEIR_UserNotificationService.notifyDiagnosisCompleteAll(logs, fixabilityByLog, summaryByLog);
        return out;
    }

    /** Single-record convenience. Delegates to the bulk path. */
    public static DiagnosisResult diagnoseSession(Id sessionId) {
        Map<Id, DiagnosisResult> results = diagnoseSessions(new List<Id>{ sessionId });
        return results.get(sessionId);
    }

    /**
     * Bulk session diagnosis. A session that already points at a captured error is diagnosed
     * through the error path instead, so a "get help" click on a real failure produces the
     * real diagnosis rather than the no-error-found fallback.
     *
     * @return diagnosis results keyed by the id that was passed in
     */
    public static Map<Id, DiagnosisResult> diagnoseSessions(List<Id> sessionIds) {
        Map<Id, DiagnosisResult> out = new Map<Id, DiagnosisResult>();
        if (sessionIds == null || sessionIds.isEmpty()) return out;

        List<Diagnostic_Session__c> sessions = [
            SELECT Id, Correlation_Id__c, User_Description__c, Object_API_Name__c,
                   Context_Record_Id__c, Page_URL__c, Recent_Error_Log__c
            FROM Diagnostic_Session__c WHERE Id IN :sessionIds
        ];
        if (sessions.isEmpty()) return out;

        List<Id> linkedLogIds = new List<Id>();
        Map<Id, Id> sessionByLog = new Map<Id, Id>();
        List<Diagnostic_Session__c> unlinked = new List<Diagnostic_Session__c>();
        for (Diagnostic_Session__c s : sessions) {
            if (s.Recent_Error_Log__c != null) {
                linkedLogIds.add(s.Recent_Error_Log__c);
                sessionByLog.put(s.Recent_Error_Log__c, s.Id);
            } else {
                unlinked.add(s);
            }
        }

        if (!linkedLogIds.isEmpty()) {
            Map<Id, DiagnosisResult> byLog = diagnoseErrors(linkedLogIds);
            for (Id logId : byLog.keySet()) {
                out.put(sessionByLog.get(logId), byLog.get(logId));
            }
        }
        if (unlinked.isEmpty()) return out;

        List<AI_Diagnosis__c> diagnoses = new List<AI_Diagnosis__c>();
        List<Diagnostic_Session__c> ordered = new List<Diagnostic_Session__c>();
        for (Diagnostic_Session__c s : unlinked) {
            DiagnosisResult r = new DiagnosisResult();
            r.summary = 'No recent technical error was found. The diagnostic session captured user context and is ready for guidance or escalation.';
            r.rootCause = 'Unknown until the user provides more context or a related system error is captured.';
            r.fixability = 'UNKNOWN';
            r.confidence = 35;
            r.recommendedAction = 'Ask the user what they were trying to do. If they cannot proceed, create a developer/support escalation with the captured page context.';
            r.needsUserInput = true;
            r.escalationRequired = false;
            r.safeRemediationActionKey = null;

            diagnoses.add(new AI_Diagnosis__c(
                Diagnostic_Session__c = s.Id, Correlation_Id__c = s.Correlation_Id__c,
                Summary__c = r.summary, Root_Cause__c = r.rootCause, Fixability__c = r.fixability,
                Confidence__c = r.confidence, Recommended_Action__c = r.recommendedAction,
                Needs_User_Input__c = true, Escalation_Required__c = false,
                Agent_Status__c = 'Deterministic Fallback',
                Input_Payload_JSON__c = buildPayload(null, s, null),
                Output_JSON__c = JSON.serialize(r)));
            ordered.add(s);
            out.put(s.Id, r);

            s.Agent_Response__c = r.summary + '\n\nNext action: ' + r.recommendedAction;
            s.Resolution_Status__c = 'Pending User';
        }

        insert diagnoses;
        for (Integer i = 0; i < ordered.size(); i++) {
            out.get(ordered[i].Id).diagnosisId = diagnoses[i].Id;
        }
        update unlinked;
        return out;
    }

    private static DiagnosisResult buildResult(String category, String normalized, AEIR_ErrorNormalizationService.Classification c, Boolean retryEligible) {
        DiagnosisResult r = new DiagnosisResult();
        r.summary = String.isBlank(normalized) ? c.userMessage : normalized;
        r.rootCause = 'Matched category: ' + (String.isBlank(category) ? c.category : category) + (String.isBlank(c.matchedPattern) ? '' : ' / pattern: ' + c.matchedPattern);
        r.fixability = c.fixability;
        r.confidence = String.isBlank(c.matchedPattern) ? 55 : 85;
        r.recommendedAction = c.recommendedAction;
        r.needsUserInput = c.fixability == 'USER_FIXABLE';
        r.escalationRequired = c.fixability == 'DEVELOPER_ONLY' || c.fixability == 'ADMIN_FIXABLE' || c.fixability == 'UNKNOWN';
        if (retryEligible == true || c.fixability == 'RETRYABLE') { r.fixability = 'RETRYABLE'; r.escalationRequired = false; }
        // Spec section 23 forbids hardcoding action keys. The key comes from the matched
        // Error_Rule__mdt, and stays null when no safe correction is configured, which is
        // the correct default: proposing the packaged Account tax sample for every
        // user-fixable error was both wrong and confusing.
        if (c.fixability == 'USER_FIXABLE' && String.isNotBlank(c.remediationActionKey)) {
            r.safeRemediationActionKey = c.remediationActionKey;
        }
        return r;
    }
    private static String buildPayload(Error_Log__c log, Diagnostic_Session__c s) {
        return buildPayload(log, s, log == null ? null
            : AEIR_ContextSnapshotService.getSnapshot(log.Object_API_Name__c, log.Record_Id__c, false));
    }

    /**
     * @param prefetchedSnapshot supplied by the bulk caller. The single-argument form issues
     *        one snapshot query per log, which is what still blew the SOQL limit at 100 logs
     *        after the rest of diagnosis had been batched.
     */
    private static String buildPayload(Error_Log__c log, Diagnostic_Session__c s, String prefetchedSnapshot) {
        Map<String, Object> payload = new Map<String, Object>();
        if (log != null) {
            payload.put('correlationId', log.Correlation_Id__c);
            payload.put('sourceType', log.Source_Type__c);
            payload.put('sourceName', log.Source_Name__c);
            payload.put('objectApiName', log.Object_API_Name__c);
            payload.put('recordId', log.Record_Id__c);
            payload.put('pageUrl', log.Page_URL__c);
            payload.put('errorCategory', log.Error_Category__c);
            payload.put('originalMessage', log.Original_Error_Message__c);
            payload.put('retryEligible', log.Retry_Eligible__c);
            payload.put('recordSnapshot', prefetchedSnapshot);
        }
        if (s != null) {
            payload.put('correlationId', s.Correlation_Id__c);
            payload.put('pageUrl', s.Page_URL__c);
            payload.put('objectApiName', s.Object_API_Name__c);
            payload.put('recordId', s.Context_Record_Id__c);
            payload.put('userDescription', s.User_Description__c);
        }
        return AEIR_SecuritySanitizerService.mask(JSON.serialize(payload));
    }
}