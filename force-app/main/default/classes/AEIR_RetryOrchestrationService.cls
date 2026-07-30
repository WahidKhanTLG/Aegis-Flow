public with sharing class AEIR_RetryOrchestrationService {
    public class RetryRequest {
        @AuraEnabled
        @InvocableVariable
        public String correlationId;
        @AuraEnabled
        @InvocableVariable
        public Id targetRecordId;
        @AuraEnabled
        @InvocableVariable
        public String payloadJson;
        @AuraEnabled
        @InvocableVariable
        public Integer attemptNumber;
        @AuraEnabled
        @InvocableVariable
        public String handlerKey;
        public RetryRequest() {}
    }
    public class RetryResult {
        @AuraEnabled
        @InvocableVariable
        public Boolean success;
        @AuraEnabled
        @InvocableVariable
        public String message;
        @AuraEnabled
        @InvocableVariable
        public String externalReference;
        @AuraEnabled
        @InvocableVariable
        public String status;
        @AuraEnabled
        @InvocableVariable
        public String idempotencyKey;
        @AuraEnabled
        @InvocableVariable
        public Id retryAttemptId;
        public RetryResult() {}
    }

    public static RetryResult requestRetry(RetryRequest request) {
        if (request == null) throw new RetryException('Retry request is required.');
        if (String.isBlank(request.handlerKey)) throw new RetryException('A retry handler key is required.');
        List<Retry_Handler__mdt> configurations = [
            SELECT Handler_Key__c, Apex_Class__c, Max_Attempts__c, Backoff_Minutes__c, Idempotency_Strategy__c, Active__c
            FROM Retry_Handler__mdt WHERE Handler_Key__c = :request.handlerKey AND Active__c = true LIMIT 1
        ];
        if (configurations.isEmpty()) throw new RetryException('No active retry handler configured for key: ' + request.handlerKey);
        Retry_Handler__mdt configuration = configurations[0];
        Integer attempt = request.attemptNumber == null || request.attemptNumber < 1 ? 1 : request.attemptNumber;
        if (configuration.Max_Attempts__c != null && attempt > Integer.valueOf(configuration.Max_Attempts__c)) {
            throw new RetryException('Retry attempt exceeds the configured maximum.');
        }
        String correlationId = String.isBlank(request.correlationId) ? AEIR_CorrelationIdService.nextId() : request.correlationId;
        request.correlationId = correlationId;
        String idempotencyKey = buildIdempotencyKey(configuration.Idempotency_Strategy__c, request, attempt);

        // Spec 11.2 requires maximum attempts AND backoff. Without a wait between
        // attempts, a caller retrying in a loop hammers the same failing dependency and
        // turns a transient fault into an outage.
        if (configuration.Backoff_Minutes__c != null && configuration.Backoff_Minutes__c > 0 && attempt > 1) {
            Datetime earliest = Datetime.now().addMinutes(-Integer.valueOf(configuration.Backoff_Minutes__c));
            List<Retry_Attempt__c> recent = [
                SELECT Id, Started_At__c FROM Retry_Attempt__c
                WHERE Correlation_Id__c = :correlationId AND Handler_Key__c = :request.handlerKey
                  AND Started_At__c >= :earliest
                ORDER BY Started_At__c DESC LIMIT 1
            ];
            if (!recent.isEmpty()) {
                throw new RetryException('Retry is in backoff. Wait ' + configuration.Backoff_Minutes__c
                    + ' minute(s) between attempts for handler ' + request.handlerKey + '.');
            }
        }

        List<Retry_Attempt__c> existing = [
            SELECT Id, Status__c, Result_Message__c, External_Reference__c
            FROM Retry_Attempt__c WHERE Idempotency_Key__c = :idempotencyKey LIMIT 1
        ];
        if (!existing.isEmpty()) {
            RetryResult prior = new RetryResult();
            prior.retryAttemptId = existing[0].Id;
            prior.idempotencyKey = idempotencyKey;
            prior.status = existing[0].Status__c;
            prior.success = existing[0].Status__c == 'Succeeded';
            prior.message = 'Duplicate retry request ignored. ' + existing[0].Result_Message__c;
            prior.externalReference = existing[0].External_Reference__c;
            return prior;
        }

        Id errorLogId;
        List<Error_Log__c> logs = [SELECT Id FROM Error_Log__c WHERE Correlation_Id__c = :correlationId LIMIT 1];
        if (!logs.isEmpty()) errorLogId = logs[0].Id;
        Retry_Attempt__c audit = new Retry_Attempt__c(
            Correlation_Id__c = correlationId,
            Error_Log__c = errorLogId,
            Handler_Key__c = request.handlerKey,
            Target_Record_Id__c = String.valueOf(request.targetRecordId),
            Payload_JSON__c = AEIR_SecuritySanitizerService.mask(request.payloadJson),
            Attempt_Number__c = attempt,
            Idempotency_Key__c = idempotencyKey,
            Status__c = 'Running',
            Started_At__c = Datetime.now()
        );
        insert audit;

        RetryResult result;
        try {
            Type handlerType = Type.forName(configuration.Apex_Class__c);
            if (handlerType == null) throw new RetryException('Retry handler class not found: ' + configuration.Apex_Class__c);
            Object instance = handlerType.newInstance();
            if (!(instance instanceof AEIR_RetryHandler)) throw new RetryException('Retry handler must implement AEIR_RetryHandler.');
            result = ((AEIR_RetryHandler)instance).retry(request);
            if (result == null) result = new RetryResult();
            result.success = result.success == true;
            result.status = result.success ? 'Succeeded' : 'Failed';
            result.idempotencyKey = idempotencyKey;
            result.retryAttemptId = audit.Id;
            audit.Status__c = result.status;
            audit.Result_Message__c = AEIR_SecuritySanitizerService.mask(result.message);
            audit.External_Reference__c = result.externalReference;
            audit.Completed_At__c = Datetime.now();
            update audit;
            return result;
        } catch (Exception exceptionValue) {
            audit.Status__c = 'Failed';
            audit.Result_Message__c = AEIR_SecuritySanitizerService.mask(exceptionValue.getMessage());
            audit.Completed_At__c = Datetime.now();
            update audit;
            RetryResult failed = new RetryResult();
            failed.success = false;
            failed.status = 'Failed';
            failed.message = exceptionValue.getMessage();
            failed.idempotencyKey = idempotencyKey;
            failed.retryAttemptId = audit.Id;
            return failed;
        }
    }

    private static String buildIdempotencyKey(String strategy, RetryRequest request, Integer attempt) {
        String target = String.valueOf(request.targetRecordId);
        String seed;
        if (strategy == 'TARGET_ONLY') seed = request.handlerKey + '|' + target;
        else if (strategy == 'CORRELATION_ONLY') seed = request.handlerKey + '|' + request.correlationId;
        else seed = request.handlerKey + '|' + target + '|' + request.correlationId + '|' + attempt;
        return seed.length() > 255 ? seed.substring(0, 255) : seed;
    }
    public class RetryException extends Exception {}
}