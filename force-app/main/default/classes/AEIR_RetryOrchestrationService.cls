public with sharing class AEIR_RetryOrchestrationService {
    /** Legacy handlers execute arbitrary business code; larger batches must be chunked. */
    public static final Integer MAX_SYNCHRONOUS_REQUESTS = 20;

    public class RetryRequest {
        @AuraEnabled @InvocableVariable public String correlationId;
        @AuraEnabled @InvocableVariable public Id targetRecordId;
        @AuraEnabled @InvocableVariable public String payloadJson;
        @AuraEnabled @InvocableVariable public Integer attemptNumber;
        @AuraEnabled @InvocableVariable public String handlerKey;
        public RetryRequest() {}
    }
    public class RetryResult {
        @AuraEnabled @InvocableVariable public Boolean success;
        @AuraEnabled @InvocableVariable public String message;
        @AuraEnabled @InvocableVariable public String externalReference;
        @AuraEnabled @InvocableVariable public String status;
        @AuraEnabled @InvocableVariable public String idempotencyKey;
        @AuraEnabled @InvocableVariable public Id retryAttemptId;
        public RetryResult() {}
    }

    /** Tests provide actual handlers without enabling a sample business action in production. */
    @TestVisible private static Map<String, Retry_Handler__mdt> configurationOverrides;

    private class Work {
        RetryRequest request;
        Retry_Handler__mdt configuration;
        String key;
        Retry_Attempt__c audit;
        List<Integer> positions = new List<Integer>();
    }

    public static RetryResult requestRetry(RetryRequest request) {
        return requestRetries(new List<RetryRequest>{ request })[0];
    }

    /**
     * Prefetches all state and writes audit collections rather than doing SOQL/DML per
     * invocable input. One result is returned per request, in the same order. Registered
     * handlers must enforce business-record access and be idempotent; this service never
     * grants access to a target merely because a caller can request a retry.
     */
    public static List<RetryResult> requestRetries(List<RetryRequest> requests) {
        List<RetryResult> output = new List<RetryResult>();
        if (requests == null || requests.isEmpty()) return output;
        for (Integer i = 0; i < requests.size(); i++) output.add(null);
        if (requests.size() > MAX_SYNCHRONOUS_REQUESTS) {
            return rejectAll(requests.size(), 'A synchronous retry batch supports at most '
                + MAX_SYNCHRONOUS_REQUESTS + ' requests. Split the work into separate transactions.');
        }
        if (!FeatureManagement.checkPermission('AEIR_Execute_Retry')) {
            List<RetryResult> denied = rejectAll(requests.size(), 'You do not have the Aegis Execute Retry permission.');
            for (RetryResult result : denied) result.status = 'Denied';
            return denied;
        }

        Set<String> handlerKeys = new Set<String>();
        for (RetryRequest request : requests) {
            if (request != null && !String.isBlank(request.handlerKey)) handlerKeys.add(request.handlerKey.trim());
        }
        Map<String, Retry_Handler__mdt> configurationsByKey = configurations(handlerKeys);
        Map<String, Work> workByKey = new Map<String, Work>();
        List<Work> workItems = new List<Work>();
        Set<String> idempotencyKeys = new Set<String>();
        Set<String> correlations = new Set<String>();
        Boolean requiresBackoff = false;
        for (Integer i = 0; i < requests.size(); i++) {
            RetryRequest request = requests[i];
            if (request == null || String.isBlank(request.handlerKey)) {
                output[i] = failed('A retry request and handler key are required.', null);
                continue;
            }
            request.handlerKey = request.handlerKey.trim();
            Retry_Handler__mdt configuration = configurationsByKey.get(request.handlerKey.toLowerCase());
            if (configuration == null || configuration.Active__c != true) {
                output[i] = failed('No unique active retry handler is configured for key: ' + request.handlerKey, null);
                continue;
            }
            Integer attempt = request.attemptNumber == null || request.attemptNumber < 1 ? 1 : request.attemptNumber;
            if (configuration.Max_Attempts__c != null && attempt > Integer.valueOf(configuration.Max_Attempts__c)) {
                output[i] = failed('Retry attempt exceeds the configured maximum.', null);
                continue;
            }
            request.attemptNumber = attempt;
            request.correlationId = String.isBlank(request.correlationId)
                ? AEIR_CorrelationIdService.nextId() : request.correlationId.trim();
            if (request.correlationId.length() > 80) {
                output[i] = failed('Correlation id must be at most 80 characters.', null);
                continue;
            }
            String key = buildIdempotencyKey(configuration.Idempotency_Strategy__c, request, attempt);
            String lookupKey = key.toLowerCase();
            if (workByKey.containsKey(lookupKey)) {
                workByKey.get(lookupKey).positions.add(i);
                continue;
            }
            Work item = new Work();
            item.request = request;
            item.configuration = configuration;
            item.key = key;
            item.positions.add(i);
            workByKey.put(lookupKey, item);
            workItems.add(item);
            idempotencyKeys.add(key);
            correlations.add(request.correlationId);
            requiresBackoff = requiresBackoff || (attempt > 1 && configuration.Backoff_Minutes__c != null
                && configuration.Backoff_Minutes__c > 0);
        }
        if (workItems.isEmpty()) return output;

        Map<String, Retry_Attempt__c> existingByKey = new Map<String, Retry_Attempt__c>();
        Map<String, Id> logIds = new Map<String, Id>();
        Map<String, Datetime> latestStartByPair = new Map<String, Datetime>();
        try {
            for (Retry_Attempt__c existing : [
                SELECT Id, Idempotency_Key__c, Status__c, Result_Message__c, External_Reference__c
                FROM Retry_Attempt__c WHERE Idempotency_Key__c IN :idempotencyKeys WITH USER_MODE
            ]) existingByKey.put(existing.Idempotency_Key__c.toLowerCase(), existing);
            for (Error_Log__c log : [
                SELECT Id, Correlation_Id__c FROM Error_Log__c WHERE Correlation_Id__c IN :correlations WITH USER_MODE
            ]) logIds.put(log.Correlation_Id__c.toLowerCase(), log.Id);
            if (requiresBackoff) {
                for (AggregateResult row : [
                    SELECT Correlation_Id__c correlation, Handler_Key__c handler, MAX(Started_At__c) lastStarted
                    FROM Retry_Attempt__c WHERE Correlation_Id__c IN :correlations AND Handler_Key__c IN :handlerKeys
                    WITH USER_MODE GROUP BY Correlation_Id__c, Handler_Key__c
                ]) latestStartByPair.put(pair((String)row.get('correlation'), (String)row.get('handler')),
                    (Datetime)row.get('lastStarted'));
            }
        } catch (Exception accessFailure) {
            return rejectAll(requests.size(), 'Retry state could not be read with your permissions. '
                + AEIR_SecuritySanitizerService.mask(accessFailure.getMessage()));
        }

        List<Work> ready = new List<Work>();
        List<Retry_Attempt__c> audits = new List<Retry_Attempt__c>();
        Datetime startedAt = Datetime.now();
        for (Work item : workItems) {
            Retry_Attempt__c existing = existingByKey.get(item.key.toLowerCase());
            if (existing != null) {
                RetryResult prior = new RetryResult();
                prior.retryAttemptId = existing.Id;
                prior.idempotencyKey = item.key;
                prior.status = existing.Status__c;
                prior.success = existing.Status__c == 'Succeeded';
                prior.message = 'Duplicate retry request ignored. '
                    + AEIR_SecuritySanitizerService.mask(existing.Result_Message__c);
                prior.externalReference = existing.External_Reference__c;
                assign(output, item, prior);
                continue;
            }
            Datetime latest = latestStartByPair.get(pair(item.request.correlationId, item.request.handlerKey));
            if (item.request.attemptNumber > 1 && item.configuration.Backoff_Minutes__c != null
                && item.configuration.Backoff_Minutes__c > 0 && latest != null
                && latest >= startedAt.addMinutes(-Integer.valueOf(item.configuration.Backoff_Minutes__c))) {
                assign(output, item, failed('Retry is in backoff. Wait '
                    + item.configuration.Backoff_Minutes__c + ' minute(s) between attempts.', item.key));
                continue;
            }
            item.audit = new Retry_Attempt__c(
                Correlation_Id__c = item.request.correlationId,
                Error_Log__c = logIds.get(item.request.correlationId.toLowerCase()),
                Handler_Key__c = item.request.handlerKey,
                Target_Record_Id__c = item.request.targetRecordId == null ? null : String.valueOf(item.request.targetRecordId),
                Payload_JSON__c = AEIR_SecuritySanitizerService.mask(item.request.payloadJson),
                Attempt_Number__c = item.request.attemptNumber,
                Idempotency_Key__c = item.key,
                Status__c = 'Running', Started_At__c = startedAt
            );
            ready.add(item);
            audits.add(item.audit);
        }
        if (audits.isEmpty()) return output;
        // Reserve orchestration rollback/finalization and a small bounded amount of
        // business DML per legacy handler. Chunk earlier rather than enter near limits.
        Integer requiredDml = 10 + (ready.size() * 5);
        if (Limits.getLimitDmlStatements() - Limits.getDmlStatements() < requiredDml) {
            for (Work item : ready) assign(output, item,
                failed('Insufficient remaining transaction budget. Retry this batch in a new transaction.', item.key));
            return output;
        }

        // A final audit-write failure must not commit successful business mutations.
        Savepoint batchSavepoint = Database.setSavepoint();
        List<Database.SaveResult> insertResults;
        try {
            insertResults = Database.insert(audits, false, AccessLevel.USER_MODE);
        } catch (Exception auditFailure) {
            Database.rollback(batchSavepoint);
            Database.releaseSavepoint(batchSavepoint);
            for (Work item : ready) assign(output, item,
                failed('Retry audit could not be created. ' + auditFailure.getMessage(), item.key));
            return output;
        }
        List<Retry_Attempt__c> auditsToComplete = new List<Retry_Attempt__c>();
        for (Integer i = 0; i < ready.size(); i++) {
            Work item = ready[i];
            if (!insertResults[i].isSuccess()) {
                assign(output, item, failed('Retry was not executed because its audit could not be created. '
                    + insertResults[i].getErrors()[0].getMessage(), item.key));
                continue;
            }
            item.audit.Id = insertResults[i].getId();
            RetryResult result;
            // One active per-handler savepoint at a time preserves unrelated successes
            // when an implementation mutates a record and then reports/throws failure.
            Savepoint handlerSavepoint = Database.setSavepoint();
            try {
                Type handlerType = Type.forName(item.configuration.Apex_Class__c);
                if (handlerType == null) throw new RetryException('Registered retry handler class was not found.');
                Object instance = handlerType.newInstance();
                if (!(instance instanceof AEIR_RetryHandler)) throw new RetryException('Registered handler must implement AEIR_RetryHandler.');
                result = ((AEIR_RetryHandler)instance).retry(item.request);
                if (result == null) result = failed('Registered retry handler returned no result.', item.key);
                result.success = result.success == true;
                if (!result.success) Database.rollback(handlerSavepoint);
            } catch (Exception handlerFailure) {
                Database.rollback(handlerSavepoint);
                result = failed(handlerFailure.getMessage(), item.key);
            } finally {
                Database.releaseSavepoint(handlerSavepoint);
            }
            result.status = result.success ? 'Succeeded' : 'Failed';
            result.message = AEIR_SecuritySanitizerService.mask(result.message);
            result.externalReference = AEIR_SecuritySanitizerService.mask(result.externalReference);
            result.idempotencyKey = item.key;
            result.retryAttemptId = item.audit.Id;
            item.audit.Status__c = result.status;
            item.audit.Result_Message__c = result.message;
            item.audit.External_Reference__c = result.externalReference;
            item.audit.Completed_At__c = Datetime.now();
            auditsToComplete.add(item.audit);
            assign(output, item, result);
        }
        try {
            // All-or-none audit completion: without the audit, none of the business
            // writes in this batch is allowed to survive the current transaction.
            Database.update(auditsToComplete, true, AccessLevel.USER_MODE);
        } catch (Exception completionFailure) {
            Database.rollback(batchSavepoint);
            for (Work item : ready) {
                if (item.audit.Id == null) continue;
                assign(output, item, failed('Retry changes were rolled back because the audit could not be finalized. '
                    + completionFailure.getMessage(), item.key));
            }
        } finally {
            Database.releaseSavepoint(batchSavepoint);
        }
        return output;
    }

    private static Map<String, Retry_Handler__mdt> configurations(Set<String> handlerKeys) {
        Map<String, Retry_Handler__mdt> output = new Map<String, Retry_Handler__mdt>();
        List<Retry_Handler__mdt> rows = configurationOverrides == null
            ? [SELECT Handler_Key__c, Apex_Class__c, Max_Attempts__c, Backoff_Minutes__c,
                Idempotency_Strategy__c, Active__c FROM Retry_Handler__mdt
                WHERE Handler_Key__c IN :handlerKeys AND Active__c = true]
            : configurationOverrides.values();
        Set<String> ambiguous = new Set<String>();
        for (Retry_Handler__mdt row : rows) {
            if (row == null || String.isBlank(row.Handler_Key__c)) continue;
            String key = row.Handler_Key__c.toLowerCase();
            if (output.containsKey(key)) ambiguous.add(key);
            output.put(key, row);
        }
        for (String key : ambiguous) output.remove(key);
        return output;
    }

    private static void assign(List<RetryResult> output, Work item, RetryResult result) {
        for (Integer position : item.positions) output[position] = result;
    }
    private static RetryResult failed(String message, String key) {
        RetryResult result = new RetryResult();
        result.success = false;
        result.status = 'Failed';
        result.message = AEIR_SecuritySanitizerService.mask(message);
        result.idempotencyKey = key;
        return result;
    }
    private static List<RetryResult> rejectAll(Integer size, String message) {
        List<RetryResult> output = new List<RetryResult>();
        for (Integer i = 0; i < size; i++) output.add(failed(message, null));
        return output;
    }
    private static String pair(String correlation, String handler) {
        return correlation.toLowerCase() + '|' + handler.toLowerCase();
    }
    private static String buildIdempotencyKey(String strategy, RetryRequest request, Integer attempt) {
        String target = String.valueOf(request.targetRecordId);
        String seed;
        if (strategy == 'TARGET_ONLY') seed = request.handlerKey + '|' + target;
        else if (strategy == 'CORRELATION_ONLY') seed = request.handlerKey + '|' + request.correlationId;
        else seed = request.handlerKey + '|' + target + '|' + request.correlationId + '|' + attempt;
        return seed.length() <= 255 ? seed : 'sha256:'
            + EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(seed)));
    }
    public class RetryException extends Exception {}
}
