/**
 * Flow-invocable sanitized error context, used as an approved Agentforce action.
 *
 * This issued four queries per request - the log, its latest diagnosis, its context rows and
 * a record snapshot - so it hit the SOQL limit at 25 requests in a single Flow batch. All
 * four are now resolved for the whole batch up front.
 */
public without sharing class AEIR_GetErrorContextAction {

    public class Request {
        @InvocableVariable(required=true) public String errorLogId;
        public Request() {}
    }

    public class Response {
        @InvocableVariable public String correlationId;
        @InvocableVariable public String contextJson;
        @InvocableVariable public String message;
        public Response() {}
    }

    @InvocableMethod(label='Aegis Flow: Get Error Context'
        description='Returns a sanitized diagnostic payload for an approved Agentforce action.')
    public static List<Response> run(List<Request> requests) {
        List<Response> output = new List<Response>();
        if (requests == null || requests.isEmpty()) return output;

        Set<Id> logIds = new Set<Id>();
        Map<Integer, Id> requestedIdByIndex = new Map<Integer, Id>();
        Map<Integer, String> parseErrorByIndex = new Map<Integer, String>();
        for (Integer i = 0; i < requests.size(); i++) {
            try {
                Id logId = (Id) requests[i].errorLogId;
                requestedIdByIndex.put(i, logId);
                logIds.add(logId);
            } catch (Exception badId) {
                // A malformed id must not cost the rest of the batch its context.
                parseErrorByIndex.put(i, 'Not a valid record id: ' + requests[i].errorLogId);
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

        // CreatedDate ASC so the newest row wins on overwrite, matching the per-request
        // ORDER BY CreatedDate DESC LIMIT 1 this replaced.
        Map<Id, AI_Diagnosis__c> latestDiagnosisByLog = new Map<Id, AI_Diagnosis__c>();
        for (AI_Diagnosis__c d : [
            SELECT Id, Error_Log__c, Summary__c, Root_Cause__c, Fixability__c, Confidence__c,
                   Recommended_Action__c, Needs_User_Input__c, Escalation_Required__c
            FROM AI_Diagnosis__c WHERE Error_Log__c IN :logIds
            ORDER BY CreatedDate ASC
        ]) {
            latestDiagnosisByLog.put(d.Error_Log__c, d);
        }

        Map<Id, Error_Log__c> technicalLogsById = new Map<Id, Error_Log__c>();
        Map<Id, List<Error_Context__c>> contextsByLog = new Map<Id, List<Error_Context__c>>();
        if (canViewSensitiveContext) {
            technicalLogsById = new Map<Id, Error_Log__c>([
                SELECT Id, Original_Error_Message__c, Stack_Trace__c
                FROM Error_Log__c WHERE Id IN :logIds
            ]);
            for (Error_Context__c ctx : [
                SELECT Error_Log__c, Context_Type__c, Source__c, Sequence__c, Payload_JSON__c, Masked__c
                FROM Error_Context__c WHERE Error_Log__c IN :logIds
                ORDER BY Sequence__c ASC
            ]) {
                if (!contextsByLog.containsKey(ctx.Error_Log__c)) {
                    contextsByLog.put(ctx.Error_Log__c, new List<Error_Context__c>());
                }
                // Same per-log cap as the original query, applied after grouping.
                if (contextsByLog.get(ctx.Error_Log__c).size() < 20) {
                    contextsByLog.get(ctx.Error_Log__c).add(ctx);
                }
            }
        }

        Map<String, Set<String>> idsByObject = new Map<String, Set<String>>();
        for (Error_Log__c log : logsById.values()) {
            if (String.isBlank(log.Object_API_Name__c) || String.isBlank(log.Record_Id__c)) continue;
            if (!idsByObject.containsKey(log.Object_API_Name__c)) {
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
