/**
 * Performs optional Agent API enrichment after deterministic evidence has committed.
 * All HTTP work precedes DML. No remote result is executed as an Apex/Flow action.
 */
public with sharing class AEIR_AgentforceDiagnosisJob implements Queueable, Database.AllowsCallouts {
    public static final Integer MAX_ENRICHMENTS = 3;
    @TestVisible private static Boolean scheduled = false;
    private List<Id> diagnosisIds;

    public AEIR_AgentforceDiagnosisJob(List<Id> ids) {
        diagnosisIds = new List<Id>();
        if (ids == null) return;
        for (Id diagnosisId : ids) {
            if (diagnosisId != null && !diagnosisIds.contains(diagnosisId) && diagnosisIds.size() < MAX_ENRICHMENTS) {
                diagnosisIds.add(diagnosisId);
            }
        }
    }

    /** Optional scheduling failures cannot undo the already-created fallback. */
    public static void schedule(List<AI_Diagnosis__c> diagnoses) {
        if (diagnoses == null || diagnoses.isEmpty()
            || !AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.AI_DIAGNOSIS)) return;
        List<Id> requestedIds = new List<Id>();
        for (AI_Diagnosis__c diagnosis : diagnoses) if (diagnosis.Id != null) requestedIds.add(diagnosis.Id);
        Set<Id> allowedIds = authorizedDiagnosisIds(requestedIds);
        if (allowedIds.isEmpty()) return;
        String status;
        try {
            status = AEIR_AgentforceClient.configuredConnection() == null ? 'CONNECTION_DISABLED' : 'QUEUED';
        } catch (Exception invalidConfiguration) { status = 'INVALID_CONNECTION'; }
        if (status == 'QUEUED' && (scheduled || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs())) {
            status = 'QUEUE_CAPACITY';
        }
        List<Id> selected = new List<Id>();
        if (status == 'QUEUED') {
            for (AI_Diagnosis__c diagnosis : diagnoses) {
                if (allowedIds.contains(diagnosis.Id) && selected.size() < MAX_ENRICHMENTS) selected.add(diagnosis.Id);
            }
            try {
                System.enqueueJob(new AEIR_AgentforceDiagnosisJob(selected));
                scheduled = true;
            } catch (Exception queueFailure) {
                selected.clear();
                status = 'QUEUE_UNAVAILABLE';
            }
        }
        List<AI_Diagnosis__c> patches = new List<AI_Diagnosis__c>();
        for (AI_Diagnosis__c diagnosis : diagnoses) {
            if (!allowedIds.contains(diagnosis.Id)) continue;
            Boolean queued = selected.contains(diagnosis.Id);
            patches.add(new AI_Diagnosis__c(Id = diagnosis.Id,
                Agent_Status__c = queued ? 'Invoked' : 'Deterministic Fallback',
                Output_JSON__c = auditOutput(diagnosis.Output_JSON__c,
                    queued ? 'QUEUED' : (status == 'QUEUED' ? 'BATCH_CAPACITY' : status), 'NOT_STARTED')));
        }
        persist(patches, true);
    }

    public void execute(QueueableContext context) {
        if (diagnosisIds.isEmpty()) return;
        Set<Id> allowedIds = authorizedDiagnosisIds(diagnosisIds);
        if (allowedIds.isEmpty()) return;
        List<AI_Diagnosis__c> diagnoses = Database.queryWithBinds(
            'SELECT Id, Error_Log__c, Diagnostic_Session__c, Correlation_Id__c, Summary__c, Root_Cause__c, '
            + 'Fixability__c, Confidence__c, Recommended_Action__c, Needs_User_Input__c, Escalation_Required__c, '
            + 'Safe_Remediation_Action_Key__c, Agent_Status__c, Input_Payload_JSON__c, Output_JSON__c '
            + 'FROM AI_Diagnosis__c WHERE Id IN :allowedIds AND Agent_Status__c != :completed',
            new Map<String, Object>{'allowedIds' => allowedIds, 'completed' => 'Completed'}, AccessLevel.SYSTEM_MODE);
        if (diagnoses.isEmpty()) return;
        enrich(diagnoses);
        List<Database.SaveResult> saved = persist(diagnoses, false);
        List<Error_Log__c> logUpdates = new List<Error_Log__c>();
        List<Diagnostic_Session__c> sessionUpdates = new List<Diagnostic_Session__c>();
        Map<Id, String> summaries = new Map<Id, String>();
        Map<Id, String> fixabilities = new Map<Id, String>();
        Set<Id> notifyIds = new Set<Id>();
        for (Integer i = 0; i < diagnoses.size() && i < saved.size(); i++) {
            if (!saved[i].isSuccess()) continue;
            AI_Diagnosis__c diagnosis = diagnoses[i];
            if (diagnosis.Error_Log__c != null) {
                logUpdates.add(new Error_Log__c(Id = diagnosis.Error_Log__c,
                    Agentforce_Status__c = diagnosis.Agent_Status__c));
                if (diagnosis.Agent_Status__c == 'Completed') {
                    notifyIds.add(diagnosis.Error_Log__c);
                    summaries.put(diagnosis.Error_Log__c, diagnosis.Summary__c);
                    fixabilities.put(diagnosis.Error_Log__c, diagnosis.Fixability__c);
                }
            } else if (diagnosis.Diagnostic_Session__c != null && diagnosis.Agent_Status__c == 'Completed') {
                sessionUpdates.add(new Diagnostic_Session__c(Id = diagnosis.Diagnostic_Session__c,
                    Agent_Response__c = diagnosis.Summary__c + '\n\nNext action: ' + diagnosis.Recommended_Action__c));
            }
        }
        if (!logUpdates.isEmpty()) reportFailures(new CuratedWriter().updateErrorStates(logUpdates));
        if (!sessionUpdates.isEmpty()) reportFailures(new CuratedWriter().updateSessionResponses(sessionUpdates));
        if (!notifyIds.isEmpty()) {
            List<Error_Log__c> logs = Database.queryWithBinds(
                'SELECT Id, Correlation_Id__c, User__c FROM Error_Log__c WHERE Id IN :notifyIds',
                new Map<String, Object>{'notifyIds' => notifyIds}, AccessLevel.SYSTEM_MODE);
            try { AEIR_UserNotificationService.notifyDiagnosisCompleteAll(logs, fixabilities, summaries); }
            catch (Exception notificationFailure) {
                System.debug(LoggingLevel.WARN, 'Aegis Flow: Agent API enrichment saved; notification refresh failed.');
            }
        }
    }

    /** Sharing is checked on both the stored diagnosis and every referenced parent. */
    private static Set<Id> authorizedDiagnosisIds(List<Id> requestedIds) {
        Set<Id> allowed = new Set<Id>();
        if (requestedIds == null || requestedIds.isEmpty()) return allowed;
        List<AI_Diagnosis__c> candidates = Database.queryWithBinds(
            'SELECT Id, Error_Log__c, Diagnostic_Session__c FROM AI_Diagnosis__c WHERE Id IN :requestedIds',
            new Map<String, Object>{'requestedIds' => requestedIds}, AccessLevel.USER_MODE);
        List<Id> logIds = new List<Id>();
        List<Id> sessionIds = new List<Id>();
        for (AI_Diagnosis__c candidate : candidates) {
            if (candidate.Error_Log__c != null) logIds.add(candidate.Error_Log__c);
            if (candidate.Diagnostic_Session__c != null) sessionIds.add(candidate.Diagnostic_Session__c);
        }
        Set<Id> allowedLogs = AEIR_AgentforceGatewayService.authorizedErrors(logIds);
        Set<Id> allowedSessions = AEIR_AgentforceGatewayService.authorizedSessions(sessionIds);
        Boolean sensitiveRole = FeatureManagement.checkPermission('AEIR_View_Sensitive_Context');
        for (AI_Diagnosis__c candidate : candidates) {
            Boolean hasParent = candidate.Error_Log__c != null || candidate.Diagnostic_Session__c != null;
            if (!hasParent && !sensitiveRole) continue;
            if (candidate.Error_Log__c != null && !allowedLogs.contains(candidate.Error_Log__c)) continue;
            if (candidate.Diagnostic_Session__c != null && !allowedSessions.contains(candidate.Diagnostic_Session__c)) continue;
            allowed.add(candidate.Id);
        }
        return allowed;
    }

    @TestVisible
    private static void enrich(List<AI_Diagnosis__c> diagnoses) {
        for (Integer i = 0; i < diagnoses.size(); i++) {
            AI_Diagnosis__c diagnosis = diagnoses[i];
            if (i >= MAX_ENRICHMENTS) {
                diagnosis.Agent_Status__c = 'Deterministic Fallback';
                diagnosis.Output_JSON__c = auditOutput(diagnosis.Output_JSON__c, 'BATCH_CAPACITY', 'NOT_STARTED');
                continue;
            }
            AEIR_AgentforceClient.Outcome outcome = AEIR_AgentforceClient.diagnose(diagnosis.Input_Payload_JSON__c);
            if (!outcome.success) {
                diagnosis.Agent_Status__c = outcome.status == 'AI_DISABLED' || outcome.status == 'CONNECTION_DISABLED'
                    ? 'Deterministic Fallback' : 'Failed';
                diagnosis.Output_JSON__c = auditOutput(diagnosis.Output_JSON__c, outcome.status, outcome.cleanupStatus);
                continue;
            }
            AEIR_AgentforceGatewayService.DiagnosisResult result = outcome.diagnosis;
            Map<String, Object> output = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(result));
            output.put('deterministicFallback', storedOutput(diagnosis.Output_JSON__c));
            output.put('agentAttemptStatus', outcome.status);
            output.put('sessionCleanupStatus', outcome.cleanupStatus);
            String sanitizedOutput = AEIR_SecuritySanitizerService.mask(JSON.serialize(output));
            if (sanitizedOutput.length() > 32768) {
                diagnosis.Agent_Status__c = 'Failed';
                diagnosis.Output_JSON__c = auditOutput(diagnosis.Output_JSON__c, 'OUTPUT_CAPACITY', outcome.cleanupStatus);
                continue;
            }
            diagnosis.Output_JSON__c = sanitizedOutput;
            diagnosis.Summary__c = result.summary;
            diagnosis.Root_Cause__c = result.rootCause;
            diagnosis.Fixability__c = result.fixability;
            diagnosis.Confidence__c = result.confidence;
            diagnosis.Recommended_Action__c = result.recommendedAction;
            diagnosis.Needs_User_Input__c = result.needsUserInput;
            diagnosis.Escalation_Required__c = result.escalationRequired;
            diagnosis.Safe_Remediation_Action_Key__c = result.safeRemediationActionKey;
            diagnosis.Agent_Status__c = 'Completed';
        }
    }

    private static String auditOutput(String fallback, String status, String cleanup) {
        Map<String, Object> output = storedOutput(fallback);
        output.put('agentAttemptStatus', status);
        output.put('sessionCleanupStatus', cleanup);
        String sanitized = AEIR_SecuritySanitizerService.mask(JSON.serialize(output));
        if (sanitized.length() <= 32768) return sanitized;
        // Keep a valid audit document even for a legacy payload at the storage limit.
        // The deterministic summary/cause/action fields remain untouched.
        return JSON.serialize(new Map<String, Object>{ 'agentAttemptStatus' => status,
            'sessionCleanupStatus' => cleanup, 'fallbackRetainedInDiagnosisFields' => true });
    }

    private static Map<String, Object> storedOutput(String fallback) {
        Map<String, Object> output;
        try { output = (Map<String, Object>) JSON.deserializeUntyped(fallback); }
        catch (Exception invalidStoredOutput) { output = new Map<String, Object>(); }
        if (output == null) output = new Map<String, Object>();
        return output;
    }

    private static List<Database.SaveResult> persist(List<AI_Diagnosis__c> diagnoses, Boolean auditOnly) {
        try {
            List<Database.SaveResult> results = new CuratedWriter().updateDiagnoses(diagnoses, auditOnly);
            reportFailures(results);
            return results;
        } catch (Exception auditFailure) {
            System.debug(LoggingLevel.WARN, 'Aegis Flow: optional Agent API audit update failed; existing diagnosis remains available.');
            return new List<Database.SaveResult>();
        }
    }

    private static void reportFailures(List<Database.SaveResult> results) {
        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) System.debug(LoggingLevel.WARN,
                'Aegis Flow: an optional Agent API result could not be persisted; existing evidence remains available.');
        }
    }

    /** Only called with diagnosis/parent IDs admitted by the user-mode read gates. */
    private without sharing class CuratedWriter {
        public List<Database.SaveResult> updateDiagnoses(List<AI_Diagnosis__c> prepared, Boolean auditOnly) {
            List<AI_Diagnosis__c> patches = new List<AI_Diagnosis__c>();
            for (AI_Diagnosis__c diagnosis : prepared) {
                AI_Diagnosis__c patch = new AI_Diagnosis__c(Id = diagnosis.Id,
                    Agent_Status__c = diagnosis.Agent_Status__c, Output_JSON__c = diagnosis.Output_JSON__c);
                if (!auditOnly) {
                    patch.Summary__c = diagnosis.Summary__c;
                    patch.Root_Cause__c = diagnosis.Root_Cause__c;
                    patch.Fixability__c = diagnosis.Fixability__c;
                    patch.Confidence__c = diagnosis.Confidence__c;
                    patch.Recommended_Action__c = diagnosis.Recommended_Action__c;
                    patch.Needs_User_Input__c = diagnosis.Needs_User_Input__c;
                    patch.Escalation_Required__c = diagnosis.Escalation_Required__c;
                    patch.Safe_Remediation_Action_Key__c = diagnosis.Safe_Remediation_Action_Key__c;
                }
                patches.add(patch);
            }
            return Database.update(patches, false, AccessLevel.SYSTEM_MODE);
        }
        public List<Database.SaveResult> updateErrorStates(List<Error_Log__c> prepared) {
            List<Error_Log__c> patches = new List<Error_Log__c>();
            for (Error_Log__c log : prepared) patches.add(new Error_Log__c(Id = log.Id, Agentforce_Status__c = log.Agentforce_Status__c));
            return Database.update(patches, false, AccessLevel.SYSTEM_MODE);
        }
        public List<Database.SaveResult> updateSessionResponses(List<Diagnostic_Session__c> prepared) {
            List<Diagnostic_Session__c> patches = new List<Diagnostic_Session__c>();
            for (Diagnostic_Session__c session : prepared) patches.add(new Diagnostic_Session__c(Id = session.Id, Agent_Response__c = session.Agent_Response__c));
            return Database.update(patches, false, AccessLevel.SYSTEM_MODE);
        }
    }
}
