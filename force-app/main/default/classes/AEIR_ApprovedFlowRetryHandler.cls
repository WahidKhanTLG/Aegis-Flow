/**
 * Runs an explicitly registered synchronous recovery Flow. Invoke through the retry
 * orchestrator so its audit/savepoint protects every Flow mutation and failed result.
 * Registrations are business authority: review the Flow's own field access, related
 * records and idempotency before enabling it. Screens, waits, callouts, immediate
 * events, email and other irreversible/asynchronous effects are unsupported here.
 */
public with sharing class AEIR_ApprovedFlowRetryHandler implements AEIR_RetryHandler {
    private enum RecoveryPhase { Configuration, TargetAccess, FlowExecution, ResultValidation }
    @TestVisible private static List<Retry_Handler__mdt> configurationOverrides;
    @TestVisible private static FlowRunner flowRunner = new FlowRunner();

    @TestVisible
    private virtual class FlowRunner {
        public virtual Map<String, Object> run(String flowApiName, Map<String, Object> inputs) {
            Flow.Interview interview = Flow.Interview.createInterview(flowApiName, inputs);
            interview.start();
            return new Map<String, Object>{
                'success' => interview.getVariableValue('varRecoverySucceeded'),
                'recordId' => interview.getVariableValue('varRecoveredRecordId'),
                'message' => interview.getVariableValue('varResultMessage')
            };
        }
    }

    public AEIR_RetryOrchestrationService.RetryResult retry(AEIR_RetryOrchestrationService.RetryRequest request) {
        if (!FeatureManagement.checkPermission('AEIR_Execute_Retry')) {
            return failure('The Aegis Execute Retry permission is required.');
        }
        if (request == null || String.isBlank(request.handlerKey) || request.targetRecordId == null
            || String.isBlank(request.correlationId) || request.correlationId.length() > 80
            || request.attemptNumber == null || request.attemptNumber < 1) {
            return failure('A handler, target record, correlation and positive attempt number are required.');
        }
        if (!String.isBlank(request.payloadJson)) {
            return failure('Approved recovery Flows accept only their fixed server-built inputs; payloadJson is unsupported.');
        }

        RecoveryPhase phase = RecoveryPhase.Configuration;
        try {
            String handlerKey = request.handlerKey.trim();
            List<Retry_Handler__mdt> candidates = configurationOverrides == null
                ? [SELECT Handler_Key__c, Active__c, Apex_Class__c, Flow_API_Name__c,
                    Target_Object__c, Required_Permission__c, Max_Attempts__c
                    FROM Retry_Handler__mdt WHERE Handler_Key__c = :handlerKey AND Active__c = true LIMIT 2]
                : configurationOverrides;
            List<Retry_Handler__mdt> matching = new List<Retry_Handler__mdt>();
            for (Retry_Handler__mdt candidate : candidates) {
                if (candidate != null && candidate.Active__c == true && candidate.Handler_Key__c == handlerKey) {
                    matching.add(candidate);
                }
            }
            if (matching.size() != 1) return failure('Exactly one active approved Flow retry registration is required.');
            Retry_Handler__mdt registration = matching[0];
            if (registration.Apex_Class__c != 'AEIR_ApprovedFlowRetryHandler'
                || !validIdentifier(registration.Flow_API_Name__c)
                || !validIdentifier(registration.Target_Object__c)
                || !validIdentifier(registration.Required_Permission__c)) {
                return failure('The approved Flow retry registration is incomplete or invalid.');
            }
            if (!FeatureManagement.checkPermission(registration.Required_Permission__c)) {
                return failure('The registered recovery permission is required.');
            }
            if (registration.Max_Attempts__c != null && request.attemptNumber > registration.Max_Attempts__c) {
                return failure('Retry attempt exceeds the configured maximum.');
            }

            Schema.DescribeSObjectResult targetType = request.targetRecordId.getSObjectType().getDescribe();
            if (targetType.getName() != registration.Target_Object__c
                || !targetType.isAccessible() || !targetType.isUpdateable()) {
                return failure('The target must match the registered object and be readable and editable by this user.');
            }
            phase = RecoveryPhase.TargetAccess;
            List<SObject> visible = Database.queryWithBinds(
                'SELECT Id FROM ' + targetType.getName() + ' WHERE Id = :targetId LIMIT 1',
                new Map<String, Object>{ 'targetId' => request.targetRecordId }, AccessLevel.USER_MODE);
            if (visible.isEmpty()) return failure('The recovery target is not available to this user.');
            // Access metadata is restricted to the caller and the already-visible target.
            // This does not read business content or grant edit access to that record.
            List<UserRecordAccess> accessRows = Database.queryWithBinds(
                'SELECT RecordId, HasEditAccess FROM UserRecordAccess WHERE UserId = :actorId AND RecordId = :targetId',
                new Map<String, Object>{ 'actorId' => UserInfo.getUserId(), 'targetId' => request.targetRecordId },
                AccessLevel.SYSTEM_MODE);
            if (accessRows.isEmpty() || accessRows[0].HasEditAccess != true) {
                return failure('Edit access to the recovery target is required.');
            }

            // Stable across attempt numbers so the approved Flow can prevent duplicate
            // business effects even when a failed operation is explicitly attempted again.
            String recoveryKey = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(
                handlerKey.toLowerCase() + '|' + String.valueOf(request.targetRecordId)
                + '|' + request.correlationId.trim().toLowerCase())));
            phase = RecoveryPhase.FlowExecution;
            Map<String, Object> outcome = flowRunner.run(registration.Flow_API_Name__c, new Map<String, Object>{
                'varTargetRecordId' => String.valueOf(request.targetRecordId),
                'varCorrelationId' => request.correlationId.trim(),
                'varAttemptNumber' => request.attemptNumber,
                'varRecoveryKey' => recoveryKey
            });
            phase = RecoveryPhase.ResultValidation;
            if (outcome == null || !(outcome.get('success') instanceof Boolean)
                || (Boolean) outcome.get('success') != true || !(outcome.get('recordId') instanceof String)) {
                return failure('The recovery Flow did not return an explicit successful, target-bound result.');
            }
            Id recoveredId;
            try { recoveredId = (Id) (String) outcome.get('recordId'); }
            catch (Exception invalidTarget) { return failure('The recovery Flow returned an invalid target record id.'); }
            if (recoveredId != request.targetRecordId) return failure('The recovery Flow returned a different target record.');
            if (outcome.get('message') != null && !(outcome.get('message') instanceof String)) {
                return failure('The recovery Flow returned an invalid result message.');
            }
            AEIR_RetryOrchestrationService.RetryResult result = new AEIR_RetryOrchestrationService.RetryResult();
            result.success = true;
            result.status = 'Succeeded';
            result.externalReference = String.valueOf(request.targetRecordId);
            String message = (String) outcome.get('message');
            result.message = AEIR_SecuritySanitizerService.safeTruncate(AEIR_SecuritySanitizerService.mask(
                String.isBlank(message) ? 'The approved recovery Flow completed for the authorized target.' : message), 4000);
            return result;
        } catch (Exception recoveryFailure) {
            // Flow/provider exceptions can contain arbitrary sensitive values that no
            // configured regex can reliably discover. Return only a fixed phase and
            // guidance; the orchestrator associates it with the configured retry audit.
            return failure('The approved recovery Flow failed during ' + String.valueOf(phase)
                + '. Ask a recovery administrator to review the configured Flow and retry audit.');
        }
    }

    private static Boolean validIdentifier(String value) {
        return !String.isBlank(value) && Pattern.matches('^[A-Za-z][A-Za-z0-9_]{0,254}$', value);
    }
    private static AEIR_RetryOrchestrationService.RetryResult failure(String message) {
        AEIR_RetryOrchestrationService.RetryResult result = new AEIR_RetryOrchestrationService.RetryResult();
        result.success = false;
        result.status = 'Failed';
        // Only fixed server-owned text and the RecoveryPhase enum reach this helper.
        // Never pass Flow output, exception text or request data here. Authorization
        // guidance must remain usable even if masking metadata is unavailable.
        result.message = message;
        return result;
    }
}
