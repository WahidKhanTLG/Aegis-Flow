public with sharing class AEIR_AgentforceGatewayService {
    // Keep the optional transport's evidence ceiling as well as storage limits.
    private static final Integer AGENT_EVIDENCE_LIMIT = 12000;
    private static final String TRUNCATION_MARKER = '... [TRUNCATED]';
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

        Set<Id> authorizedIds = authorizedErrors(errorLogIds);
        if (authorizedIds.isEmpty()) return out;
        // Technical evidence is read only after the user-mode sharing/ownership gate.
        // It is never returned directly to a browser caller.
        List<Error_Log__c> logs = Database.queryWithBinds(
            'SELECT Id, Correlation_Id__c, Error_Category__c, Severity__c, Source_Type__c, Source_Name__c, '
            + 'Original_Error_Message__c, Normalized_Message__c, Object_API_Name__c, Record_Id__c, '
            + 'Page_URL__c, Context_JSON__c, Retry_Eligible__c, User__c, OwnerId FROM Error_Log__c WHERE Id IN :authorizedIds',
            new Map<String, Object>{'authorizedIds' => authorizedIds}, AccessLevel.SYSTEM_MODE);
        if (logs.isEmpty()) return out;

        // A background processor's business access is not the affected user's
        // authority. Only collect fresh data in that affected user's own context.
        // Snapshots remain batched by object for eligible records.
        Map<String, Set<String>> idsByObject = new Map<String, Set<String>>();
        for (Error_Log__c log : logs) {
            if (!mayCollectSnapshot(log)) continue;
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
            boundResult(r);

            AI_Diagnosis__c d = new AI_Diagnosis__c();
            d.OwnerId = log.OwnerId;
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
            d.Output_JSON__c = buildOutput(r, log.Correlation_Id__c);

            diagnoses.add(d);
            ordered.add(log);
            out.put(log.Id, r);
            fixabilityByLog.put(log.Id, r.fixability);
            summaryByLog.put(log.Id, r.summary);

            log.Agentforce_Status__c = 'Completed';
            log.Status__c = 'Diagnosed';
        }

        // Curated writes are authorized by the gate; end users do not gain arbitrary
        // AI_Diagnosis__c create/edit or Error_Log__c edit permissions.
        new CuratedWriter().insertDiagnoses(diagnoses);
        for (Integer i = 0; i < ordered.size(); i++) {
            out.get(ordered[i].Id).diagnosisId = diagnoses[i].Id;
        }
        new CuratedWriter().completeErrors(new Map<Id, Error_Log__c>(logs).keySet());

        // Closes the async round trip so the utility bar replaces its spinner with the outcome.
        AEIR_UserNotificationService.notifyDiagnosisCompleteAll(logs, fixabilityByLog, summaryByLog);
        // The deterministic record is already durable in this transaction. Remote
        // enrichment is optional and runs only in a separate callout-capable job.
        AEIR_AgentforceDiagnosisJob.schedule(diagnoses);
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

        Set<Id> authorizedIds = authorizedSessions(sessionIds);
        if (authorizedIds.isEmpty()) return out;
        List<Diagnostic_Session__c> sessions = Database.queryWithBinds(
            'SELECT Id, Correlation_Id__c, User_Description__c, Object_API_Name__c, '
            + 'Context_Record_Id__c, Page_URL__c, Recent_Error_Log__c, OwnerId FROM Diagnostic_Session__c WHERE Id IN :authorizedIds',
            new Map<String, Object>{'authorizedIds' => authorizedIds}, AccessLevel.SYSTEM_MODE);
        if (sessions.isEmpty()) return out;

        List<Id> linkedLogIds = new List<Id>();
        Map<Id, List<Id>> sessionsByLog = new Map<Id, List<Id>>();
        List<Diagnostic_Session__c> unlinked = new List<Diagnostic_Session__c>();
        for (Diagnostic_Session__c s : sessions) {
            if (s.Recent_Error_Log__c != null) {
                linkedLogIds.add(s.Recent_Error_Log__c);
                if (!sessionsByLog.containsKey(s.Recent_Error_Log__c)) sessionsByLog.put(s.Recent_Error_Log__c, new List<Id>());
                sessionsByLog.get(s.Recent_Error_Log__c).add(s.Id);
            } else {
                unlinked.add(s);
            }
        }

        if (!linkedLogIds.isEmpty()) {
            Map<Id, DiagnosisResult> byLog = diagnoseErrors(linkedLogIds);
            for (Id logId : byLog.keySet()) {
                for (Id sessionId : sessionsByLog.get(logId)) out.put(sessionId, byLog.get(logId));
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
            boundResult(r);

            diagnoses.add(new AI_Diagnosis__c(
                OwnerId = s.OwnerId, Diagnostic_Session__c = s.Id, Correlation_Id__c = s.Correlation_Id__c,
                Summary__c = r.summary, Root_Cause__c = r.rootCause, Fixability__c = r.fixability,
                Confidence__c = r.confidence, Recommended_Action__c = r.recommendedAction,
                Needs_User_Input__c = true, Escalation_Required__c = false,
                Agent_Status__c = 'Deterministic Fallback',
                Input_Payload_JSON__c = buildPayload(null, s, null),
                Output_JSON__c = buildOutput(r, s.Correlation_Id__c)));
            ordered.add(s);
            out.put(s.Id, r);

            s.Agent_Response__c = fitText(r.summary + '\n\nNext action: ' + r.recommendedAction,
                Diagnostic_Session__c.Agent_Response__c.getDescribe().getLength(), null, null, null);
            s.Resolution_Status__c = 'Pending User';
        }

        new CuratedWriter().insertDiagnoses(diagnoses);
        for (Integer i = 0; i < ordered.size(); i++) {
            out.get(ordered[i].Id).diagnosisId = diagnoses[i].Id;
        }
        new CuratedWriter().completeSessions(unlinked);
        AEIR_AgentforceDiagnosisJob.schedule(diagnoses);
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
        return buildPayload(log, s, !mayCollectSnapshot(log) ? null
            : AEIR_ContextSnapshotService.getSnapshot(log.Object_API_Name__c, log.Record_Id__c, false));
    }

    private static Boolean mayCollectSnapshot(Error_Log__c log) {
        return log != null && (log.User__c == null ? log.OwnerId : log.User__c) == UserInfo.getUserId();
    }

    /**
     * @param prefetchedSnapshot supplied by the bulk caller. The single-argument form issues
     *        one snapshot query per log, which is what still blew the SOQL limit at 100 logs
     *        after the rest of diagnosis had been batched.
     */
    private static String buildPayload(Error_Log__c log, Diagnostic_Session__c s, String prefetchedSnapshot) {
        Map<String, Object> payload = new Map<String, Object>();
        Set<String> shortened = new Set<String>();
        Set<String> omitted = new Set<String>();
        if (log != null) {
            payload.put('errorLogId', log.Id);
            payload.put('correlationId', fitText(log.Correlation_Id__c, 80, 512, shortened, 'correlationId'));
            payload.put('sourceType', fitText(log.Source_Type__c, 255, 128, shortened, 'sourceType'));
            payload.put('sourceName', fitText(log.Source_Name__c, 255, 1000, shortened, 'sourceName'));
            payload.put('objectApiName', fitText(log.Object_API_Name__c, 100, 512, shortened, 'objectApiName'));
            payload.put('recordId', log.Record_Id__c);
            payload.put('pageUrl', fitText(log.Page_URL__c, 255, 1000, shortened, 'pageUrl'));
            payload.put('errorCategory', fitText(log.Error_Category__c, 255, 256, shortened, 'errorCategory'));
            payload.put('normalizedMessage', fitText(log.Normalized_Message__c, 32768, 1500, shortened, 'normalizedMessage'));
            payload.put('originalMessage', fitText(log.Original_Error_Message__c, 32768, 3000, shortened, 'originalMessage'));
            payload.put('retryEligible', log.Retry_Eligible__c);
            // Enforce this again when building each payload: an eligible same-user
            // log in this batch can refer to the same record as a foreign-user log.
            if (mayCollectSnapshot(log)) addEvidence(payload, 'recordSnapshot', prefetchedSnapshot, 2000, omitted);
            else {
                payload.put('recordSnapshotStatus', 'OMITTED_DIFFERENT_AFFECTED_USER');
                omitted.add('recordSnapshot');
            }
            addEvidence(payload, 'context', log.Context_JSON__c, 2000, omitted);
        }
        if (s != null) {
            payload.put('diagnosticSessionId', s.Id);
            payload.put('correlationId', fitText(s.Correlation_Id__c, 80, 512, shortened, 'correlationId'));
            payload.put('pageUrl', fitText(s.Page_URL__c, 255, 1000, shortened, 'pageUrl'));
            payload.put('objectApiName', fitText(s.Object_API_Name__c, 100, 512, shortened, 'objectApiName'));
            payload.put('recordId', s.Context_Record_Id__c);
            payload.put('userDescription', fitText(s.User_Description__c, 32768, 6000, shortened, 'userDescription'));
        }
        payload.put('evidenceRetainedInSourceRecords', true);
        payload.put('truncatedEvidenceFields', shortened);
        payload.put('omittedEvidenceFields', omitted);
        Integer maximum = Math.min(AGENT_EVIDENCE_LIMIT, AI_Diagnosis__c.Input_Payload_JSON__c.getDescribe().getLength());
        String serialized = JSON.serialize(payload);
        // Omit complete optional values, never cut a serialized JSON document.
        for (String optionalField : new List<String>{'context', 'recordSnapshot'}) {
            if (serialized.length() <= maximum) break;
            if (payload.containsKey(optionalField)) {
                payload.remove(optionalField);
                omitted.add(optionalField);
                serialized = JSON.serialize(payload);
            }
        }
        if (serialized.length() > maximum) {
            // A compact, valid reference remains useful even if future metadata adds
            // unexpected overhead. Full evidence stays on the authorized source.
            return JSON.serialize(new Map<String, Object>{
                'correlationId' => payload.get('correlationId'),
                'errorLogId' => payload.get('errorLogId'),
                'diagnosticSessionId' => payload.get('diagnosticSessionId'),
                'errorCategory' => payload.get('errorCategory'),
                'recordSnapshotStatus' => payload.get('recordSnapshotStatus'),
                'omittedEvidenceFields' => omitted,
                'evidenceOmitted' => true, 'evidenceRetainedInSourceRecords' => true
            });
        }
        return serialized;
    }

    private static void addEvidence(Map<String, Object> payload, String key, String rawValue, Integer encodedBudget, Set<String> omitted) {
        if (String.isBlank(rawValue)) return;
        String sanitized = AEIR_SecuritySanitizerService.mask(rawValue);
        if (JSON.serialize(sanitized).length() > encodedBudget) omitted.add(key);
        else payload.put(key, sanitized);
    }

    /** Field storage and serialized-output budgets are deliberately separate. */
    private static void boundResult(DiagnosisResult result) {
        result.summary = fitText(result.summary, AI_Diagnosis__c.Summary__c.getDescribe().getLength(), null, null, null);
        result.rootCause = fitText(result.rootCause, AI_Diagnosis__c.Root_Cause__c.getDescribe().getLength(), null, null, null);
        result.recommendedAction = fitText(result.recommendedAction, AI_Diagnosis__c.Recommended_Action__c.getDescribe().getLength(), null, null, null);
        if (result.safeRemediationActionKey != null
            && result.safeRemediationActionKey.length() > AI_Diagnosis__c.Safe_Remediation_Action_Key__c.getDescribe().getLength()) {
            // Never turn an invalid action key into a different, truncated action.
            result.safeRemediationActionKey = null;
        }
    }

    private static String buildOutput(DiagnosisResult result, String correlationId) {
        Integer maximum = AI_Diagnosis__c.Output_JSON__c.getDescribe().getLength();
        Integer textBudget = Math.max(128, (maximum - 2048) / 3);
        Set<String> shortened = new Set<String>();
        Map<String, Object> output = new Map<String, Object>{
            'diagnosisId' => result.diagnosisId, 'correlationId' => fitText(correlationId, 80, 512, shortened, 'correlationId'),
            'fixability' => result.fixability, 'confidence' => result.confidence,
            'needsUserInput' => result.needsUserInput, 'escalationRequired' => result.escalationRequired,
            'safeRemediationActionKey' => result.safeRemediationActionKey,
            'fullValuesRetainedInDiagnosisFields' => true, 'truncatedFields' => shortened
        };
        String serialized;
        do {
            output.put('summary', fitText(result.summary, AI_Diagnosis__c.Summary__c.getDescribe().getLength(), textBudget, shortened, 'summary'));
            output.put('rootCause', fitText(result.rootCause, AI_Diagnosis__c.Root_Cause__c.getDescribe().getLength(), textBudget, shortened, 'rootCause'));
            output.put('recommendedAction', fitText(result.recommendedAction, AI_Diagnosis__c.Recommended_Action__c.getDescribe().getLength(), textBudget, shortened, 'recommendedAction'));
            serialized = JSON.serialize(output);
            textBudget = Math.max(128, textBudget / 2);
        } while (serialized.length() > maximum && textBudget > 128);
        return serialized;
    }

    /**
     * Budget the serialized string, including escapes. Prefixes end on a complete
     * UTF-16 code point; JSON itself is always produced by the serializer.
     */
    private static String fitText(String value, Integer fieldMaximum, Integer encodedBudget, Set<String> shortened, String key) {
        if (value == null) return null;
        String sanitized = AEIR_SecuritySanitizerService.mask(value);
        Integer keep = Math.min(sanitized.length(), fieldMaximum);
        Boolean clipped = keep < sanitized.length();
        String candidate = clipped ? textPrefix(sanitized, Math.max(0, keep - TRUNCATION_MARKER.length())) + TRUNCATION_MARKER : sanitized;
        while (encodedBudget != null && JSON.serialize(candidate).length() > encodedBudget) {
            keep = keep / 2;
            clipped = true;
            candidate = textPrefix(sanitized, Math.max(0, keep - TRUNCATION_MARKER.length())) + TRUNCATION_MARKER;
        }
        if (clipped && shortened != null && key != null) shortened.add(key);
        return candidate;
    }
    private static String textPrefix(String value, Integer length) {
        Integer keep = Math.min(value.length(), length);
        if (keep > 0 && keep < value.length()) {
            Integer lastCodeUnit = value.charAt(keep - 1);
            if (lastCodeUnit >= 55296 && lastCodeUnit <= 56319) keep--;
        }
        return value.substring(0, keep);
    }

    /** Internal server contract shared with the optional enrichment job. */
    public static Set<Id> authorizedErrors(List<Id> requestedIds) {
        Set<Id> allowed = new Set<Id>();
        if (requestedIds == null || requestedIds.isEmpty()) return allowed;
        Id caller = UserInfo.getUserId();
        Boolean processor = FeatureManagement.checkPermission('AEIR_View_Sensitive_Context')
            || FeatureManagement.checkPermission('AEIR_Process_Diagnostics');
        for (Error_Log__c row : (List<Error_Log__c>) Database.queryWithBinds(
            'SELECT Id, User__c, OwnerId FROM Error_Log__c WHERE Id IN :requestedIds',
            new Map<String, Object>{'requestedIds' => requestedIds}, AccessLevel.USER_MODE)) {
            if (processor || row.User__c == caller || (row.User__c == null && row.OwnerId == caller)) allowed.add(row.Id);
        }
        return allowed;
    }
    public static Set<Id> authorizedSessions(List<Id> requestedIds) {
        Set<Id> allowed = new Set<Id>();
        if (requestedIds == null || requestedIds.isEmpty()) return allowed;
        Id caller = UserInfo.getUserId();
        Boolean processor = FeatureManagement.checkPermission('AEIR_View_Sensitive_Context')
            || FeatureManagement.checkPermission('AEIR_Process_Diagnostics');
        List<Diagnostic_Session__c> owned = new List<Diagnostic_Session__c>();
        List<Id> linkedIds = new List<Id>();
        for (Diagnostic_Session__c row : (List<Diagnostic_Session__c>) Database.queryWithBinds(
            'SELECT Id, User__c, OwnerId, Recent_Error_Log__c FROM Diagnostic_Session__c WHERE Id IN :requestedIds',
            new Map<String, Object>{'requestedIds' => requestedIds}, AccessLevel.USER_MODE)) {
            if (processor || row.User__c == caller || (row.User__c == null && row.OwnerId == caller)) {
                owned.add(row);
                if (row.Recent_Error_Log__c != null) linkedIds.add(row.Recent_Error_Log__c);
            }
        }
        Set<Id> allowedLinks = authorizedErrors(linkedIds);
        for (Diagnostic_Session__c row : owned) if (row.Recent_Error_Log__c == null || allowedLinks.contains(row.Recent_Error_Log__c)) allowed.add(row.Id);
        return allowed;
    }

    /**
     * Application-owned diagnostic persistence after the user-mode parent gates.
     * A processor's Read All visibility does not grant arbitrary record editing.
     * This private boundary accepts only prepared diagnoses and fixed lifecycle
     * patches; it cannot update customer business objects or source evidence.
     */
    private without sharing class CuratedWriter {
        public void insertDiagnoses(List<AI_Diagnosis__c> prepared) {
            Database.insert(prepared, true, AccessLevel.SYSTEM_MODE);
        }
        public void completeErrors(Set<Id> authorizedIds) {
            List<Error_Log__c> patches = new List<Error_Log__c>();
            for (Id recordId : authorizedIds) {
                patches.add(new Error_Log__c(Id = recordId, Status__c = 'Diagnosed', Agentforce_Status__c = 'Completed'));
            }
            if (!patches.isEmpty()) Database.update(patches, true, AccessLevel.SYSTEM_MODE);
        }
        public void completeSessions(List<Diagnostic_Session__c> prepared) {
            List<Diagnostic_Session__c> patches = new List<Diagnostic_Session__c>();
            for (Diagnostic_Session__c session : prepared) {
                patches.add(new Diagnostic_Session__c(Id = session.Id,
                    Agent_Response__c = session.Agent_Response__c, Resolution_Status__c = 'Pending User'));
            }
            if (!patches.isEmpty()) Database.update(patches, true, AccessLevel.SYSTEM_MODE);
        }
    }
}
