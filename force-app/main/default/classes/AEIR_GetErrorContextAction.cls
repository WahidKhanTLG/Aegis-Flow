/**
 * Flow-invocable sanitized error context, used as an approved Agentforce action.
 *
 * This issued four queries per request - the log, its latest diagnosis, its context rows and
 * a record snapshot - so it hit the SOQL limit at 25 requests in a single Flow batch. All
 * four are now resolved for the whole batch up front.
 */
global with sharing class AEIR_GetErrorContextAction {
    private static final Integer MAX_REQUESTS = 200;
    private static final Integer MAX_SNAPSHOT_OBJECTS = 20;

    global class Request {
        global Request() {}
        @InvocableVariable(required=true) global String errorLogId;

    }

    global class Response {
        global Response() {}
        @InvocableVariable global String correlationId;
        @InvocableVariable global String contextJson;
        @InvocableVariable global String message;

    }

    @InvocableMethod(category='Aegis Flow' label='Aegis Flow: Get Error Context'
        description='Returns a sanitized diagnostic payload for an approved Agentforce action.')
    global static List<Response> run(List<Request> requests) {
        List<Response> output = new List<Response>();
        if (requests == null || requests.isEmpty()) return output;

        Set<Id> logIds = new Set<Id>();
        Map<Integer, Id> requestedIdByIndex = new Map<Integer, Id>();
        Map<Integer, String> parseErrorByIndex = new Map<Integer, String>();
        for (Integer i = 0; i < requests.size(); i++) {
            try {
                if (i >= MAX_REQUESTS || requests[i] == null || String.isBlank(requests[i].errorLogId)
                    || (requests[i].errorLogId.length() != 15 && requests[i].errorLogId.length() != 18)) {
                    parseErrorByIndex.put(i, i >= MAX_REQUESTS ? 'This context batch supports at most 200 requests.'
                        : 'Not a valid record id: an Error Log id is required.');
                    continue;
                }
                Id logId = (Id) requests[i].errorLogId;
                if (logId.getSObjectType() != Error_Log__c.SObjectType) {
                    parseErrorByIndex.put(i, 'Not a valid record id: an Error Log id is required.');
                    continue;
                }
                requestedIdByIndex.put(i, logId);
                logIds.add(logId);
            } catch (Exception badId) {
                // A malformed id must not cost the rest of the batch its context.
                parseErrorByIndex.put(i, 'Not a valid record id: an Error Log id is required.');
            }
        }

        Boolean canViewSensitiveContext =
            FeatureManagement.checkPermission('AEIR_View_Sensitive_Context');
        Id currentUserId = UserInfo.getUserId();
        List<Error_Log__c> visibleLogs = canViewSensitiveContext
            ? [SELECT Id, Name, Correlation_Id__c, Source_Type__c, Source_Name__c,
                      Error_Category__c, Severity__c, Status__c, Object_API_Name__c,
                      Record_Id__c, Action_Name__c, Page_URL__c,
                      Normalized_Message__c, Retry_Eligible__c
               FROM Error_Log__c WHERE Id IN :logIds]
            : [SELECT Id, Name, Correlation_Id__c, Source_Type__c, Source_Name__c,
                      Error_Category__c, Severity__c, Status__c, Object_API_Name__c,
                      Record_Id__c, Action_Name__c, Page_URL__c,
                      Normalized_Message__c, Retry_Eligible__c
               FROM Error_Log__c WHERE Id IN :logIds AND User__c = :currentUserId];
        Map<Id, Error_Log__c> logsById = new Map<Id, Error_Log__c>(visibleLogs);

        Set<Id> visibleLogIds = new Set<Id>(logsById.keySet());
        // Limit children per authorized parent in SOQL; a global scan of every historic
        // diagnosis/context can exceed row and heap limits before in-memory caps apply.
        Map<Id, AI_Diagnosis__c> latestDiagnosisByLog = new Map<Id, AI_Diagnosis__c>();
        List<Error_Log__c> diagnosisParents = [
            SELECT Id, (SELECT Id, Error_Log__c, Summary__c, Root_Cause__c, Fixability__c, Confidence__c,
                Recommended_Action__c, Needs_User_Input__c, Escalation_Required__c
                FROM AI_Diagnoses__r ORDER BY CreatedDate DESC, Id DESC LIMIT 1)
            FROM Error_Log__c WHERE Id IN :visibleLogIds
        ];
        for (Error_Log__c parent : diagnosisParents) {
            if (!parent.AI_Diagnoses__r.isEmpty()) latestDiagnosisByLog.put(parent.Id, parent.AI_Diagnoses__r[0]);
        }

        Map<Id, Error_Log__c> technicalLogsById = new Map<Id, Error_Log__c>();
        Map<Id, List<Error_Context__c>> contextsByLog = new Map<Id, List<Error_Context__c>>();
        if (canViewSensitiveContext) {
            for (Error_Log__c parent : technicalParents(visibleLogIds)) {
                technicalLogsById.put(parent.Id, parent);
                contextsByLog.put(parent.Id, parent.Contexts__r);
            }
        }

        Map<String, Set<String>> idsByObject = new Map<String, Set<String>>();
        for (Error_Log__c log : logsById.values()) {
            if (String.isBlank(log.Object_API_Name__c) || String.isBlank(log.Record_Id__c)) continue;
            if (!idsByObject.containsKey(log.Object_API_Name__c)) {
                if (idsByObject.size() >= MAX_SNAPSHOT_OBJECTS) continue;
                idsByObject.put(log.Object_API_Name__c, new Set<String>());
            }
            idsByObject.get(log.Object_API_Name__c).add(log.Record_Id__c);
        }
        Map<String, String> snapshots = AEIR_ContextSnapshotService.getSnapshots(idsByObject, false);

        for (Integer i = 0; i < requests.size(); i++) {
            Response response = new Response();
            if (parseErrorByIndex.containsKey(i)) {
                response.message = parseErrorByIndex.get(i);
                output.add(response);
                continue;
            }
            Error_Log__c log = logsById.get(requestedIdByIndex.get(i));
            if (log == null) {
                response.message = 'Error log not found, or not visible to the current user.';
                output.add(response);
                continue;
            }
            Map<String, Object> payload = new Map<String, Object>{ 'errorLog' => safeErrorLog(log) };
            if (latestDiagnosisByLog.containsKey(log.Id)) {
                payload.put('latestDiagnosis', latestDiagnosisByLog.get(log.Id));
            }
            payload.put('recordSnapshot', snapshots.get(log.Record_Id__c));
            if (!String.isBlank(log.Object_API_Name__c) && !idsByObject.containsKey(log.Object_API_Name__c)) {
                payload.put('snapshotStatus', 'Snapshot omitted because this batch spans too many object types.');
            }
            if (canViewSensitiveContext) {
                Error_Log__c technical = technicalLogsById.get(log.Id);
                payload.put('technicalError', technical == null ? null : technical.Original_Error_Message__c);
                payload.put('stackTrace', technical == null ? null : technical.Stack_Trace__c);
                payload.put('contexts', contextsByLog.containsKey(log.Id)
                    ? contextsByLog.get(log.Id) : new List<Error_Context__c>());
            }
            response.correlationId = log.Correlation_Id__c;
            response.contextJson = AEIR_SecuritySanitizerService.mask(JSON.serialize(payload));
            response.message = canViewSensitiveContext
                ? 'Sanitized error context returned.'
                : 'Limited diagnostic context returned.';
            output.add(response);
        }
        return output;
    }

    private static List<Error_Log__c> technicalParents(Set<Id> authorizedLogIds) {
        if (authorizedLogIds.isEmpty()) return new List<Error_Log__c>();
        // Explicit bindings avoid compiler-generated cursor variable scope, while
        // USER_MODE retains both record sharing and technical-field permissions.
        List<Error_Log__c> parents = Database.queryWithBinds(
            'SELECT Id, Original_Error_Message__c, Stack_Trace__c, '
            + '(SELECT Error_Log__c, Context_Type__c, Source__c, Sequence__c, Payload_JSON__c, Masked__c '
            + 'FROM Contexts__r ORDER BY Sequence__c ASC, Id ASC LIMIT 20) '
            + 'FROM Error_Log__c WHERE Id IN :visibleIds',
            new Map<String, Object>{ 'visibleIds' => new Set<Id>(authorizedLogIds) }, AccessLevel.USER_MODE);
        return parents;
    }

    private static Map<String, Object> safeErrorLog(Error_Log__c log) {
        return new Map<String, Object>{
            'id' => log.Id,
            'correlationId' => log.Correlation_Id__c,
            'sourceType' => log.Source_Type__c,
            'sourceName' => log.Source_Name__c,
            'category' => log.Error_Category__c,
            'severity' => log.Severity__c,
            'status' => log.Status__c,
            'objectApiName' => log.Object_API_Name__c,
            'recordId' => log.Record_Id__c,
            'actionName' => log.Action_Name__c,
            'pageUrl' => log.Page_URL__c,
            'message' => log.Normalized_Message__c,
            'retryEligible' => log.Retry_Eligible__c
        };
    }
}
