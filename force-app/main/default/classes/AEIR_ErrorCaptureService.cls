public without sharing class AEIR_ErrorCaptureService {
    public class ErrorInput {
        @AuraEnabled public String correlationId;
        @AuraEnabled public String sourceType;
        @AuraEnabled public String sourceName;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String recordId;
        @AuraEnabled public String actionName;
        @AuraEnabled public String pageUrl;
        @AuraEnabled public String pageReferenceJson;
        @AuraEnabled public String changedFieldsJson;
        @AuraEnabled public String originalMessage;
        @AuraEnabled public String stackTrace;
        @AuraEnabled public String contextJson;
        @AuraEnabled public String severity;
        @AuraEnabled public String userId;
    }
    public class CaptureResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Id errorLogId;
        @AuraEnabled public String correlationId;
        @AuraEnabled public String status;
        @AuraEnabled public String category;
        @AuraEnabled public String severity;
        @AuraEnabled public String normalizedMessage;
        @AuraEnabled public Boolean retryEligible;
        @AuraEnabled public String message;
    }
    public class PublishResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String correlationId;
        @AuraEnabled public String message;
    }

    /**
     * Persists an error in the current transaction. Use this when the caller can
     * safely commit the diagnostic record. This method intentionally does not
     * publish Error_Captured__e, which prevents duplicate/racing persistence.
     */
    public static CaptureResult capture(ErrorInput input) {
        if (input == null) input = new ErrorInput();
        String cid = normalizeCorrelationId(input.correlationId);
        Id affectedUserId = validUserId(input.userId) ? (Id)input.userId : UserInfo.getUserId();
        List<Error_Log__c> existing = [
            SELECT Id, User__c, Correlation_Id__c, Status__c, Error_Category__c, Severity__c,
                   Normalized_Message__c, Retry_Eligible__c
            FROM Error_Log__c WHERE Correlation_Id__c = :cid LIMIT 1
        ];
        if (!existing.isEmpty()) {
            if (existing[0].User__c != affectedUserId) {
                throw new AuraHandledException('That diagnostic correlation is not available to this user.');
            }
            return resultFromLog(existing[0], true, 'Existing diagnostic returned for this correlation id.');
        }

        Error_Log__c log = buildLog(input, cid);
        AEIR_IncidentAggregationService.assign(new List<Error_Log__c>{ log });
        Database.insert(new List<Error_Log__c>{ log }, true, AccessLevel.SYSTEM_MODE);
        insertContextRows(log.Id, cid, input);
        AEIR_UserNotificationService.notifyForErrorLogs(new List<Error_Log__c>{ log });
        requestDiagnosis(new List<Error_Log__c>{ log });
        return resultFromLog(log, true, 'Diagnostic captured.');
    }

    /**
     * Publishes rollback-resilient capture work for contexts where direct DML
     * may not survive (for example, a transaction that will be rolled back).
     */
    public static PublishResult publish(ErrorInput input) {
        if (input == null) input = new ErrorInput();
        String cid = normalizeCorrelationId(input.correlationId);
        input.correlationId = cid;
        Error_Captured__e evt = new Error_Captured__e(
            Correlation_Id__c = cid,
            Source_Type__c = String.isBlank(input.sourceType) ? 'Unknown' : input.sourceType,
            Source_Name__c = input.sourceName,
            Error_Message__c = AEIR_SecuritySanitizerService.safeTruncate(AEIR_SecuritySanitizerService.mask(input.originalMessage), 32000),
            Record_Id__c = input.recordId,
            Object_API_Name__c = input.objectApiName,
            User_Id__c = validUserId(input.userId) ? input.userId : UserInfo.getUserId(),
            Context_JSON__c = AEIR_SecuritySanitizerService.safeTruncate(AEIR_SecuritySanitizerService.mask(input.contextJson), 32000),
            Severity__c = input.severity,
            Stack_Trace__c = AEIR_SecuritySanitizerService.safeTruncate(AEIR_SecuritySanitizerService.mask(input.stackTrace), 32000),
            Action_Name__c = input.actionName,
            Page_URL__c = AEIR_SecuritySanitizerService.mask(input.pageUrl)
        );
        Database.SaveResult saveResult = EventBus.publish(evt);
        PublishResult result = new PublishResult();
        result.success = saveResult.isSuccess();
        result.correlationId = cid;
        result.message = saveResult.isSuccess() ? 'Diagnostic capture event published.' : firstError(saveResult.getErrors());
        return result;
    }

    /** Bulk persistence entry point used only by the platform-event subscriber. */
    public static List<CaptureResult> captureFromEvents(List<ErrorInput> inputs) {
        List<CaptureResult> output = new List<CaptureResult>();
        if (inputs == null || inputs.isEmpty()) return output;

        Set<String> correlationIds = new Set<String>();
        for (ErrorInput input : inputs) {
            if (input == null) input = new ErrorInput();
            input.correlationId = normalizeCorrelationId(input.correlationId);
            correlationIds.add(input.correlationId);
        }
        Map<String, Error_Log__c> existingByCorrelation = new Map<String, Error_Log__c>();
        for (Error_Log__c existing : [
            SELECT Id, Correlation_Id__c, Status__c, Error_Category__c, Severity__c,
                   Normalized_Message__c, Retry_Eligible__c
            FROM Error_Log__c WHERE Correlation_Id__c IN :correlationIds
        ]) existingByCorrelation.put(existing.Correlation_Id__c, existing);

        List<Error_Log__c> logsToInsert = new List<Error_Log__c>();
        List<ErrorInput> inputsToInsert = new List<ErrorInput>();
        for (ErrorInput input : inputs) {
            if (existingByCorrelation.containsKey(input.correlationId)) {
                output.add(resultFromLog(existingByCorrelation.get(input.correlationId), true, 'Duplicate capture event ignored.'));
            } else {
                logsToInsert.add(buildLog(input, input.correlationId));
                inputsToInsert.add(input);
            }
        }

        if (!logsToInsert.isEmpty()) {
            AEIR_IncidentAggregationService.assign(logsToInsert);
            Database.SaveResult[] saveResults = Database.insert(logsToInsert, false, AccessLevel.SYSTEM_MODE);
            List<Error_Context__c> contextRows = new List<Error_Context__c>();
            for (Integer i = 0; i < saveResults.size(); i++) {
                Database.SaveResult sr = saveResults[i];
                Error_Log__c log = logsToInsert[i];
                ErrorInput input = inputsToInsert[i];
                if (sr.isSuccess()) {
                    log.Id = sr.getId();
                    contextRows.addAll(buildContextRows(log.Id, input.correlationId, input));
                    output.add(resultFromLog(log, true, 'Diagnostic captured from platform event.'));
                } else {
                    CaptureResult failure = new CaptureResult();
                    failure.success = false;
                    failure.correlationId = input.correlationId;
                    failure.status = 'Failed';
                    failure.message = firstError(sr.getErrors());
                    output.add(failure);
                }
            }
            if (!contextRows.isEmpty()) Database.insert(contextRows, false, AccessLevel.SYSTEM_MODE);
            List<Error_Log__c> insertedLogs = new List<Error_Log__c>();
            for (Error_Log__c log : logsToInsert) if (log.Id != null) insertedLogs.add(log);
            AEIR_UserNotificationService.notifyForErrorLogs(insertedLogs);
            requestDiagnosis(insertedLogs);
        }
        return output;
    }

    @AuraEnabled
    public static CaptureResult captureFromJson(String inputJson) {
        ErrorInput input = (ErrorInput) JSON.deserialize(inputJson, ErrorInput.class);
        // Browser callers must never be able to attribute a diagnostic to another user.
        // Server-side monitors and the explicitly permission-gated REST endpoint use the
        // non-Aura capture method when they need to record a trusted affected user.
        if (input == null) input = new ErrorInput();
        input.userId = UserInfo.getUserId();
        return capture(input);
    }

    private static Error_Log__c buildLog(ErrorInput input, String cid) {
        Error_Log__c log = new Error_Log__c();
        log.Correlation_Id__c = cid;
        log.Source_Type__c = String.isBlank(input.sourceType) ? 'Unknown' : input.sourceType;
        log.Source_Name__c = input.sourceName;
        log.Object_API_Name__c = input.objectApiName;
        log.Record_Id__c = input.recordId;
        log.Action_Name__c = input.actionName;
        log.Page_URL__c = AEIR_SecuritySanitizerService.mask(input.pageUrl);
        log.Page_Reference_JSON__c = AEIR_SecuritySanitizerService.mask(input.pageReferenceJson);
        log.Changed_Fields_JSON__c = AEIR_SecuritySanitizerService.mask(input.changedFieldsJson);
        log.Context_JSON__c = AEIR_SecuritySanitizerService.mask(input.contextJson);
        log.Original_Error_Message__c = AEIR_SecuritySanitizerService.mask(input.originalMessage);
        log.Stack_Trace__c = AEIR_SecuritySanitizerService.mask(input.stackTrace);
        Id effectiveUserId = validUserId(input.userId) ? (Id)input.userId : UserInfo.getUserId();
        log.User__c = effectiveUserId;
        log.OwnerId = effectiveUserId;
        log.Status__c = 'New';
        if (!String.isBlank(input.severity)) log.Severity__c = input.severity;
        AEIR_ErrorNormalizationService.applyClassification(log);
        // Metadata-driven severity overrides the deterministic default when a rule matches,
        // unless the caller supplied an explicit severity.
        if (String.isBlank(input.severity)) {
            String ruleSeverity = AEIR_PolicyConfigService.resolveSeverity(log.Source_Type__c, log.Original_Error_Message__c);
            if (!String.isBlank(ruleSeverity)) log.Severity__c = ruleSeverity;
        }
        return log;
    }

    private static CaptureResult resultFromLog(Error_Log__c log, Boolean success, String message) {
        CaptureResult res = new CaptureResult();
        res.success = success;
        res.errorLogId = log.Id;
        res.correlationId = log.Correlation_Id__c;
        res.status = log.Status__c;
        res.category = log.Error_Category__c;
        res.severity = log.Severity__c;
        res.normalizedMessage = log.Normalized_Message__c;
        res.retryEligible = log.Retry_Eligible__c;
        res.message = message;
        return res;
    }

    private static void insertContextRows(Id logId, String cid, ErrorInput input) {
        List<Error_Context__c> rows = buildContextRows(logId, cid, input);
        if (!rows.isEmpty()) Database.insert(rows, true, AccessLevel.SYSTEM_MODE);
    }
    private static List<Error_Context__c> buildContextRows(Id logId, String cid, ErrorInput input) {
        List<Error_Context__c> rows = new List<Error_Context__c>();
        Integer seq = 1;
        if (!String.isBlank(input.pageReferenceJson)) rows.add(contextRow(logId, cid, 'Page', input.pageReferenceJson, 'LWC/PageReference', seq++));
        if (!String.isBlank(input.changedFieldsJson)) rows.add(contextRow(logId, cid, 'Changed Fields', input.changedFieldsJson, 'Client/Server Delta', seq++));
        if (!String.isBlank(input.contextJson)) rows.add(contextRow(logId, cid, 'Payload', input.contextJson, 'Context Payload', seq++));
        return rows;
    }
    private static Error_Context__c contextRow(Id logId, String cid, String type, String payload, String source, Integer seq) {
        return new Error_Context__c(
            Error_Log__c = logId,
            Correlation_Id__c = cid,
            Context_Type__c = type,
            Payload_JSON__c = AEIR_SecuritySanitizerService.mask(payload),
            Source__c = source,
            Sequence__c = seq,
            Masked__c = true
        );
    }
    /**
     * Kicks off asynchronous diagnosis. Publishing rather than calling the gateway inline
     * keeps AI work out of the failing transaction (spec section 23) and lets the utility
     * bar show a spinner immediately. Gated on the AI_DIAGNOSIS flag, which ships off.
     */
    private static void requestDiagnosis(List<Error_Log__c> logs) {
        if (logs == null || logs.isEmpty()) return;
        if (!AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.AI_DIAGNOSIS)) return;
        List<Agent_Diagnosis_Requested__e> events = new List<Agent_Diagnosis_Requested__e>();
        for (Error_Log__c log : logs) {
            if (log == null || log.Id == null || String.isBlank(log.Correlation_Id__c)) continue;
            events.add(new Agent_Diagnosis_Requested__e(
                Correlation_Id__c = log.Correlation_Id__c,
                Error_Log_Id__c = String.valueOf(log.Id),
                Target_User_Id__c = log.User__c == null ? null : String.valueOf(log.User__c)
            ));
        }
        if (!events.isEmpty()) EventBus.publish(events);
    }

    private static String normalizeCorrelationId(String value) {
        return String.isBlank(value) ? AEIR_CorrelationIdService.nextId() : value.trim();
    }
    private static Boolean validUserId(String userId) {
        return !String.isBlank(userId) && (userId.length() == 15 || userId.length() == 18) && userId.startsWith('005');
    }
    private static String firstError(Database.Error[] errors) {
        return errors == null || errors.isEmpty() ? 'Unknown platform error.' : errors[0].getMessage();
    }
}
