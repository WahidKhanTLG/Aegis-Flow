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
        public Boolean retryable = false;
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

    /** Server-only controls for probes/imports that must not publish follow-up work. */
    public class CaptureOptions {
        public Boolean notifyUser = true;
        public Boolean requestDiagnosis = true;
    }

    /**
     * Persists an error in the current transaction. Use this when the caller can
     * safely commit the diagnostic record. This method intentionally does not
     * publish Error_Captured__e, which prevents duplicate/racing persistence.
     */
    public static CaptureResult capture(ErrorInput input) {
        return capture(input, null);
    }

    public static CaptureResult capture(ErrorInput input, CaptureOptions options) {
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
        if (options == null || options.notifyUser != false) {
            AEIR_UserNotificationService.notifyForErrorLogs(new List<Error_Log__c>{ log });
        }
        if (options == null || options.requestDiagnosis != false) requestDiagnosis(new List<Error_Log__c>{ log });
        return resultFromLog(log, true, 'Diagnostic captured.');
    }

    /**
     * Publishes rollback-resilient capture work for contexts where direct DML
     * may not survive (for example, a transaction that will be rolled back).
     */
    public static PublishResult publish(ErrorInput input) {
        return publishAll(new List<ErrorInput>{ input })[0];
    }

    /** One publish statement for the batch; one ordered acknowledgement per input. */
    public static List<PublishResult> publishAll(List<ErrorInput> inputs) {
        List<PublishResult> output = new List<PublishResult>();
        if (inputs == null || inputs.isEmpty()) return output;
        List<Error_Captured__e> events = new List<Error_Captured__e>();
        Map<String, String> correlationsByUuid = new Map<String, String>();
        List<Integer> positions = new List<Integer>();
        for (Integer i = 0; i < inputs.size(); i++) {
            ErrorInput input = inputs[i] == null ? new ErrorInput() : inputs[i];
            PublishResult result = new PublishResult();
            result.success = false;
            output.add(result);
            try {
                String cid = normalizeCorrelationId(input.correlationId);
                input.correlationId = cid;
                result.correlationId = cid;
                Error_Captured__e event = (Error_Captured__e)Error_Captured__e.SObjectType.newSObject(null, true);
                event.Correlation_Id__c = cid;
                event.Source_Type__c = String.isBlank(input.sourceType) ? 'Unknown' : input.sourceType;
                event.Source_Name__c = input.sourceName;
                event.Error_Message__c = AEIR_SecuritySanitizerService.safeTruncate(AEIR_SecuritySanitizerService.mask(input.originalMessage), 32000);
                event.Record_Id__c = input.recordId;
                event.Object_API_Name__c = input.objectApiName;
                event.User_Id__c = validUserId(input.userId) ? input.userId : UserInfo.getUserId();
                event.Context_JSON__c = AEIR_SecuritySanitizerService.safeTruncate(AEIR_SecuritySanitizerService.mask(input.contextJson), 32000);
                event.Severity__c = input.severity;
                event.Stack_Trace__c = AEIR_SecuritySanitizerService.safeTruncate(AEIR_SecuritySanitizerService.mask(input.stackTrace), 32000);
                event.Action_Name__c = input.actionName;
                event.Page_URL__c = AEIR_SecuritySanitizerService.mask(input.pageUrl);
                events.add(event);
                correlationsByUuid.put(event.EventUuid, cid);
                positions.add(i);
            } catch (Exception invalidInput) {
                result.message = AEIR_SecuritySanitizerService.mask(invalidInput.getMessage());
            }
        }
        if (!events.isEmpty()) {
            List<Database.SaveResult> saveResults = EventBus.publish(events, new AEIR_CapturePublishCallback(correlationsByUuid));
            for (Integer i = 0; i < saveResults.size(); i++) {
                PublishResult result = output[positions[i]];
                result.success = saveResults[i].isSuccess();
                result.message = result.success ? 'Diagnostic capture event accepted for asynchronous persistence.'
                    : firstError(saveResults[i].getErrors());
            }
        }
        return output;
    }

    /**
     * Bulk persistence for trusted server adapters and event subscribers. Result slots
     * stay aligned with inputs even when existing and new correlations are mixed.
     * Correlation keys are case-insensitive, matching the unique external-id field.
     */
    public static List<CaptureResult> captureFromEvents(List<ErrorInput> inputs) {
        return captureFromEvents(inputs, null);
    }

    public static List<CaptureResult> captureFromEvents(List<ErrorInput> inputs, CaptureOptions options) {
        List<CaptureResult> output = new List<CaptureResult>();
        if (inputs == null || inputs.isEmpty()) return output;

        List<ErrorInput> normalizedInputs = new List<ErrorInput>();
        Set<String> correlationIds = new Set<String>();
        for (ErrorInput item : inputs) {
            ErrorInput input = item == null ? new ErrorInput() : item;
            normalizedInputs.add(input);
            output.add(null);
            try {
                input.correlationId = normalizeCorrelationId(input.correlationId);
                correlationIds.add(input.correlationId);
            } catch (Exception invalidInput) {
                output[output.size() - 1] = failedCapture(input.correlationId, invalidInput.getMessage());
            }
        }
        Map<String, Error_Log__c> existingByCorrelation = new Map<String, Error_Log__c>();
        if (!correlationIds.isEmpty()) {
            for (Error_Log__c existing : [
                SELECT Id, User__c, Correlation_Id__c, Status__c, Error_Category__c, Severity__c,
                       Normalized_Message__c, Retry_Eligible__c
                FROM Error_Log__c WHERE Correlation_Id__c IN :correlationIds
            ]) existingByCorrelation.put(existing.Correlation_Id__c.toLowerCase(), existing);
        }

        List<Error_Log__c> logsToInsert = new List<Error_Log__c>();
        List<ErrorInput> inputsToInsert = new List<ErrorInput>();
        Map<String, ErrorInput> firstInputByCorrelation = new Map<String, ErrorInput>();
        Map<String, CaptureResult> resultByCorrelation = new Map<String, CaptureResult>();
        for (Integer i = 0; i < normalizedInputs.size(); i++) {
            if (output[i] != null) continue;
            ErrorInput input = normalizedInputs[i];
            String key = input.correlationId.toLowerCase();
            Id affectedUserId = effectiveUserId(input);
            if (existingByCorrelation.containsKey(key)) {
                Error_Log__c existing = existingByCorrelation.get(key);
                output[i] = existing.User__c == affectedUserId
                    ? resultFromLog(existing, true, 'Duplicate capture event ignored.')
                    : failedCapture(input.correlationId, 'That diagnostic correlation is not available to this user.');
            } else if (firstInputByCorrelation.containsKey(key)) {
                if (effectiveUserId(firstInputByCorrelation.get(key)) != affectedUserId) {
                    output[i] = failedCapture(input.correlationId, 'A correlation cannot identify different affected users.');
                }
            } else {
                firstInputByCorrelation.put(key, input);
                try {
                    logsToInsert.add(buildLog(input, input.correlationId));
                    inputsToInsert.add(input);
                } catch (Exception invalidInput) {
                    resultByCorrelation.put(key, failedCapture(input.correlationId, invalidInput.getMessage()));
                }
            }
        }

        if (!logsToInsert.isEmpty()) {
            AEIR_IncidentAggregationService.assign(logsToInsert);
            List<Database.SaveResult> saveResults = Database.insert(logsToInsert, false, AccessLevel.SYSTEM_MODE);
            List<Error_Context__c> contextRows = new List<Error_Context__c>();
            List<Error_Log__c> insertedLogs = new List<Error_Log__c>();
            for (Integer i = 0; i < saveResults.size(); i++) {
                Database.SaveResult sr = saveResults[i];
                Error_Log__c log = logsToInsert[i];
                ErrorInput input = inputsToInsert[i];
                CaptureResult result;
                if (sr.isSuccess()) {
                    log.Id = sr.getId();
                    contextRows.addAll(buildContextRows(log.Id, input.correlationId, input));
                    insertedLogs.add(log);
                    result = resultFromLog(log, true, 'Diagnostic captured from platform event.');
                } else {
                    result = failedCapture(input.correlationId, firstError(sr.getErrors()));
                    for (Database.Error error : sr.getErrors()) {
                        String code = String.valueOf(error.getStatusCode());
                        if (code == 'UNABLE_TO_LOCK_ROW' || code == 'SERVER_UNAVAILABLE') result.retryable = true;
                    }
                }
                resultByCorrelation.put(input.correlationId.toLowerCase(), result);
            }
            if (!contextRows.isEmpty()) {
                reportPartialFailures(Database.insert(contextRows, false, AccessLevel.SYSTEM_MODE), 'diagnostic context');
            }
            if (options == null || options.notifyUser != false) AEIR_UserNotificationService.notifyForErrorLogs(insertedLogs);
            if (options == null || options.requestDiagnosis != false) requestDiagnosis(insertedLogs);
        }
        for (Integer i = 0; i < normalizedInputs.size(); i++) {
            if (output[i] == null) output[i] = resultByCorrelation.get(normalizedInputs[i].correlationId.toLowerCase());
        }
        return output;
    }

    private static CaptureResult failedCapture(String cid, String message) {
        CaptureResult result = new CaptureResult();
        result.success = false;
        result.correlationId = cid;
        result.status = 'Failed';
        result.message = AEIR_SecuritySanitizerService.mask(message);
        return result;
    }

    private static Id effectiveUserId(ErrorInput input) {
        return validUserId(input.userId) ? (Id)input.userId : UserInfo.getUserId();
    }

    private static void reportPartialFailures(List<Database.SaveResult> results, String operation) {
        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.WARN, 'Aegis Flow: ' + operation + ' persistence failed: '
                    + AEIR_SecuritySanitizerService.mask(firstError(result.getErrors())));
            }
        }
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
     * bar show a spinner immediately. Deterministic automatic diagnosis is separate
     * from remote AI enrichment; the legacy AI flag still opts into both paths.
     */
    private static void requestDiagnosis(List<Error_Log__c> logs) {
        if (logs == null || logs.isEmpty()) return;
        if (!AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.AUTO_DIAGNOSIS)
            && !AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.AI_DIAGNOSIS)) return;
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
        String correlationId = String.isBlank(value) ? AEIR_CorrelationIdService.nextId() : value.trim();
        if (correlationId.length() > 80) throw new CaptureException('Correlation id must be at most 80 characters.');
        return correlationId;
    }
    private static Boolean validUserId(String userId) {
        if (String.isBlank(userId)) return false;
        try { return ((Id)userId).getSObjectType() == User.SObjectType; }
        catch (Exception invalidId) { return false; }
    }
    private static String firstError(Database.Error[] errors) {
        return errors == null || errors.isEmpty() ? 'Unknown platform error.' : AEIR_SecuritySanitizerService.mask(errors[0].getMessage());
    }
    public class CaptureException extends Exception {}
}
