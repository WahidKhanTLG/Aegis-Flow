/** Scoped diagnostic API for support consoles, integration clients, and agent tools. */
@RestResource(urlMapping='/aegis-flow/v1/operations/*')
global with sharing class AEIR_HeadlessRestService {
    private static final Integer MAX_BODY = 20000;
    private static final Integer CURSOR_TTL_MINUTES = 60;
    private static final Set<String> NOTICE_FIELDS = new Set<String>{
        'Id', 'Error_Log__c', 'Correlation_Id__c', 'Headline__c', 'Short_Message__c', 'Severity__c',
        'Notification_Type__c', 'Action_Available__c', 'Status__c', 'Expires_At__c', 'CreatedDate', 'Target_User__c'
    };
    private static final Set<String> SAFE_ERROR_FIELDS = new Set<String>{
        'Id', 'Correlation_Id__c', 'Source_Type__c', 'Source_Name__c', 'Error_Category__c', 'Severity__c',
        'Status__c', 'Object_API_Name__c', 'Record_Id__c', 'Action_Name__c', 'Page_URL__c',
        'Normalized_Message__c', 'Retry_Eligible__c', 'User__c'
    };
    private static final Set<String> DIAGNOSIS_FIELDS = new Set<String>{
        'Id', 'Error_Log__c', 'Summary__c', 'Root_Cause__c', 'Fixability__c', 'Confidence__c',
        'Recommended_Action__c', 'Needs_User_Input__c', 'Escalation_Required__c'
    };

    @HttpGet
    global static void getOperation() {
        if (!authorize()) return;
        try {
            String resource = route();
            if (resource == 'capabilities') {
                respond(200, new Map<String, Object>{
                    'apiVersion' => '1',
                    'resources' => new List<String>{'errors', 'incidents', 'notifications', 'context'},
                    'actions' => new List<String>{'help', 'dismiss', 'escalate'},
                    'scope' => 'Current user; visible scope requires sensitive-context permission and record access.',
                    'maximumPageSize' => 100,
                    'cursorTtlMinutes' => CURSOR_TTL_MINUTES,
                    'aiDiagnosisEnabled' => AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.AI_DIAGNOSIS),
                    'automaticDiagnosisEnabled' => AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.AUTO_DIAGNOSIS),
                    'governedRemediationEnabled' => AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.GOVERNED_REMEDIATION)
                });
            } else if (resource == 'errors') {
                listErrors();
            } else if (resource == 'incidents') {
                listIncidents();
            } else if (resource == 'notifications') {
                allowedParameters(new Set<String>());
                requireAccess(User_Notification__c.SObjectType, 'read', NOTICE_FIELDS);
                respond(200, new Map<String, Object>{'items' => AEIR_UserNotificationService.getOpenAlerts()});
            } else if (resource == 'context') {
                getContext();
            } else {
                respond(404, failure('Unknown diagnostic resource.'));
            }
        } catch (HeadlessAccessException denied) {
            respond(403, failure('The diagnostic role, object access, or field access required for this operation is missing.'));
        } catch (QueryException denied) {
            respond(403, failure('Diagnostic object, field, or record access is required.'));
        } catch (Exception invalid) {
            respond(400, failure('Invalid diagnostic request. Check filters and pagination cursor.'));
        }
    }

    @HttpPost
    global static void postOperation() {
        if (!authorize()) return;
        try {
            String action = route();
            if (!new Set<String>{'help', 'dismiss', 'escalate'}.contains(action)) {
                respond(404, failure('Unknown diagnostic action.'));
                return;
            }
            String body = RestContext.request.requestBody == null ? null : RestContext.request.requestBody.toString();
            if (String.isBlank(body) || body.length() > MAX_BODY) {
                respond(400, failure('A JSON action payload of at most 20000 characters is required.'));
                return;
            }
            Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(body);
            if (input == null) throw new HeadlessException('A JSON object is required.');
            if (action == 'help') {
                allowedKeys(input.keySet(), new Set<String>{'description', 'recordId', 'objectApiName', 'pageUrl'});
                String description = textValue(input, 'description', 4000);
                if (String.isBlank(description) || description.length() > 4000) {
                    respond(400, failure('Describe the issue using 1 to 4000 characters.'));
                    return;
                }
                String recordId = textValue(input, 'recordId', 18);
                String objectName = textValue(input, 'objectApiName', Diagnostic_Session__c.Object_API_Name__c.getDescribe().getLength());
                String pageUrl = textValue(input, 'pageUrl', Diagnostic_Session__c.Page_URL__c.getDescribe().getLength());
                if (!String.isBlank(recordId)) {
                    Id contextId = (Id) recordId;
                    String actualObject = contextId.getSObjectType().getDescribe().getName();
                    if (!String.isBlank(objectName) && objectName != actualObject) throw new HeadlessException('Record and object do not match.');
                    objectName = actualObject;
                }
                if (!String.isBlank(objectName) && !Schema.getGlobalDescribe().containsKey(objectName)) throw new HeadlessException('Unknown context object.');
                Set<String> inputFields = new Set<String>{'User_Description__c', 'Browser_Context_JSON__c'};
                if (!String.isBlank(recordId)) inputFields.add('Context_Record_Id__c');
                if (!String.isBlank(objectName)) inputFields.add('Object_API_Name__c');
                if (!String.isBlank(pageUrl)) inputFields.add('Page_URL__c');
                requireAccess(Diagnostic_Session__c.SObjectType, 'create', inputFields);
                requireAccess(Diagnostic_Session__c.SObjectType, 'read', new Set<String>{'Id', 'Correlation_Id__c', 'Recent_Error_Log__c'});
                requireAccess(Error_Log__c.SObjectType, 'read', new Set<String>{'Id', 'User__c', 'Record_Id__c', 'Object_API_Name__c', 'CreatedDate'});
                Map<String, Object> context = new Map<String, Object>{'recordId' => recordId, 'objectApiName' => objectName, 'pageUrl' => pageUrl};
                respond(201, AEIR_HelpMeController.createSession(JSON.serialize(context), description, 'Report Issue'));
                return;
            }
            allowedKeys(input.keySet(), new Set<String>{'correlationId'});
            String correlationId = textValue(input, 'correlationId', User_Notification__c.Correlation_Id__c.getDescribe().getLength());
            requireAccess(User_Notification__c.SObjectType, 'read', NOTICE_FIELDS);
            if (action == 'dismiss') {
                requireAccess(User_Notification__c.SObjectType, 'update', new Set<String>{'Status__c', 'Dismissed_At__c'});
            } else {
                requireAccess(User_Notification__c.SObjectType, 'update', new Set<String>{'Status__c', 'Viewed_At__c'});
                requireAccess(Error_Log__c.SObjectType, 'read', SAFE_ERROR_FIELDS);
                requireAccess(Error_Log__c.SObjectType, 'read', new Set<String>{'Original_Error_Message__c', 'Stack_Trace__c', 'Debug_Log_Link__c', 'CreatedDate'});
                requireAccess(Error_Log__c.SObjectType, 'update', new Set<String>{'Status__c'});
                requireAccess(AI_Diagnosis__c.SObjectType, 'read', DIAGNOSIS_FIELDS);
                requireAccess(AI_Diagnosis__c.SObjectType, 'read', new Set<String>{'Safe_Remediation_Action_Key__c', 'Agent_Status__c'});
                requireAccess(Developer_Escalation__c.SObjectType, 'create', new Set<String>());
                requireAccess(Developer_Escalation__c.SObjectType, 'read', new Set<String>{'Id', 'Status__c', 'Subject__c', 'Recipient__c', 'Channel__c', 'Error_Log__c', 'Diagnostic_Session__c'});
            }
            // A headless caller may act only on its own canonical, active notice.
            if (String.isBlank(correlationId) || AEIR_UserNotificationService.resolveAlert(correlationId) == null) {
                respond(404, failure('An active notification was not found.'));
                return;
            }
            if (action == 'dismiss') {
                AEIR_UserNotificationService.dismiss(correlationId);
                respond(200, new Map<String, Object>{'success' => true, 'correlationId' => correlationId});
            } else {
                respond(201, AEIR_AegisHeadlessMonitorController.escalateAlert(correlationId));
            }
        } catch (HeadlessAccessException denied) {
            respond(403, failure('The diagnostic role, object access, or field access required for this action is missing.'));
        } catch (DmlException denied) {
            respond(403, failure('The requested diagnostic action could not be authorized or saved.'));
        } catch (Exception invalid) {
            respond(400, failure('Invalid diagnostic action payload.'));
        }
    }

    private static void listErrors() {
        Map<String, String> params = RestContext.request.params;
        allowedParameters(new Set<String>{'limit', 'days', 'scope', 'objectApiName', 'recordId', 'severity', 'status', 'cursor'});
        Integer pageSize = bounded(params.get('limit'), 25, 1, 100);
        Integer days = bounded(params.get('days'), 7, 1, 30);
        Id userId = UserInfo.getUserId();
        Boolean visible = visibleScope(params.get('scope'));
        String objectName = params.get('objectApiName');
        String recordId = params.get('recordId');
        String severity = params.get('severity');
        String status = params.get('status');
        String queryKey = digest(new List<String>{String.valueOf(visible), String.valueOf(pageSize), String.valueOf(days), objectName, recordId, severity, status});
        CursorState cursor = readCursor(params.get('cursor'), 'errors', queryKey, Error_Log__c.SObjectType, days);
        Datetime untilAt = cursor == null ? Datetime.now() : cursor.untilAt;
        Datetime since = cursor == null ? untilAt.addDays(-days) : cursor.since;
        Datetime cursorAt = cursor == null ? null : cursor.at;
        Id cursorId = cursor == null ? null : cursor.lastId;
        List<String> filters = new List<String>{'CreatedDate >= :since', 'CreatedDate <= :untilAt'};
        if (!visible) filters.add('User__c = :userId');
        if (!String.isBlank(objectName)) filters.add('Object_API_Name__c = :objectName');
        if (!String.isBlank(recordId)) filters.add('Record_Id__c = :recordId');
        if (!String.isBlank(severity)) filters.add('Severity__c = :severity');
        if (!String.isBlank(status)) filters.add('Status__c = :status');
        if (cursor != null) {
            filters.add('(CreatedDate < :cursorAt OR (CreatedDate = :cursorAt AND Id < :cursorId))');
        }
        Integer queryLimit = pageSize + 1;
        String queryText = 'SELECT Id, Correlation_Id__c, Source_Type__c, Source_Name__c, '
            + 'Object_API_Name__c, Record_Id__c, Error_Category__c, Severity__c, Status__c, '
            + 'Normalized_Message__c, CreatedDate FROM Error_Log__c WHERE '
            + String.join(filters, ' AND ') + ' ORDER BY CreatedDate DESC, Id DESC LIMIT :queryLimit';
        List<Error_Log__c> rows = Database.queryWithBinds(queryText, new Map<String, Object>{
            'since' => since, 'untilAt' => untilAt, 'userId' => userId, 'objectName' => objectName, 'recordId' => recordId,
            'severity' => severity, 'status' => status, 'cursorAt' => cursorAt, 'cursorId' => cursorId,
            'queryLimit' => queryLimit
        }, AccessLevel.USER_MODE);
        Boolean hasMore = rows.size() > pageSize;
        if (hasMore) rows.remove(rows.size() - 1);
        List<Object> items = new List<Object>();
        for (Error_Log__c row : rows) {
            items.add(new Map<String, Object>{
                'id' => row.Id, 'correlationId' => row.Correlation_Id__c,
                'sourceType' => row.Source_Type__c, 'sourceName' => row.Source_Name__c,
                'objectApiName' => row.Object_API_Name__c, 'recordId' => row.Record_Id__c,
                'category' => row.Error_Category__c, 'severity' => row.Severity__c,
                'status' => row.Status__c, 'message' => AEIR_SecuritySanitizerService.mask(row.Normalized_Message__c),
                'createdAt' => row.CreatedDate
            });
        }
        String nextCursor;
        if (hasMore) {
            Error_Log__c last = rows[rows.size() - 1];
            nextCursor = writeCursor('errors', queryKey, since, untilAt, last.CreatedDate, last.Id);
        }
        respond(200, new Map<String, Object>{'items' => items, 'nextCursor' => nextCursor});
    }

    private static void listIncidents() {
        Map<String, String> params = RestContext.request.params;
        allowedParameters(new Set<String>{'limit', 'scope', 'cursor'});
        Integer pageSize = bounded(params.get('limit'), 25, 1, 100);
        Id userId = UserInfo.getUserId();
        Boolean visible = visibleScope(params.get('scope'));
        String queryKey = digest(new List<String>{String.valueOf(visible), String.valueOf(pageSize)});
        CursorState cursor = readCursor(params.get('cursor'), 'incidents', queryKey, Incident__c.SObjectType, null);
        Datetime untilAt = cursor == null ? Datetime.now() : cursor.untilAt;
        Datetime cursorAt = cursor == null ? null : cursor.at;
        Id cursorId = cursor == null ? null : cursor.lastId;
        List<String> filters = new List<String>{'CreatedDate <= :untilAt', '(Last_Seen_At__c <= :untilAt OR Last_Seen_At__c = null)'};
        if (!visible) filters.add('Id IN (SELECT Incident__c FROM Error_Log__c WHERE User__c = :userId)');
        if (cursor != null) {
            filters.add(cursorAt == null
                ? '(Last_Seen_At__c = null AND Id < :cursorId)'
                : '(Last_Seen_At__c < :cursorAt OR (Last_Seen_At__c = :cursorAt AND Id < :cursorId) OR Last_Seen_At__c = null)');
        }
        Integer queryLimit = pageSize + 1;
        List<Incident__c> rows = Database.queryWithBinds(
            'SELECT Id, Name, Incident_Key__c, Highest_Severity__c, Occurrence_Count__c, Status__c, '
            + 'First_Seen_At__c, Last_Seen_At__c FROM Incident__c WHERE ' + String.join(filters, ' AND ')
            + ' ORDER BY Last_Seen_At__c DESC NULLS LAST, Id DESC LIMIT :queryLimit',
            new Map<String, Object>{'untilAt' => untilAt, 'userId' => userId, 'cursorAt' => cursorAt,
                'cursorId' => cursorId, 'queryLimit' => queryLimit}, AccessLevel.USER_MODE);
        Boolean hasMore = rows.size() > pageSize;
        if (hasMore) rows.remove(rows.size() - 1);
        List<Object> items = new List<Object>();
        for (Incident__c row : rows) {
            items.add(new Map<String, Object>{'id' => row.Id, 'reference' => row.Name,
                'key' => row.Incident_Key__c, 'severity' => row.Highest_Severity__c,
                'occurrences' => row.Occurrence_Count__c, 'status' => row.Status__c,
                'firstAt' => row.First_Seen_At__c, 'lastAt' => row.Last_Seen_At__c});
        }
        String nextCursor;
        if (hasMore) {
            Incident__c last = rows[rows.size() - 1];
            nextCursor = writeCursor('incidents', queryKey, null, untilAt, last.Last_Seen_At__c, last.Id);
        }
        respond(200, new Map<String, Object>{'items' => items, 'nextCursor' => nextCursor});
    }

    private static void getContext() {
        allowedParameters(new Set<String>{'errorLogId', 'scope'});
        Boolean visible = visibleScope(RestContext.request.params.get('scope'));
        Id logId = (Id) RestContext.request.params.get('errorLogId');
        if (logId == null || logId.getSObjectType() != Error_Log__c.SObjectType) throw new HeadlessException('A diagnostic record Id is required.');
        Boolean sensitive = FeatureManagement.checkPermission('AEIR_View_Sensitive_Context');
        Set<String> fields = new Set<String>();
        fields.addAll(SAFE_ERROR_FIELDS);
        if (sensitive) {
            fields.addAll(new Set<String>{'Original_Error_Message__c', 'Stack_Trace__c'});
            requireAccess(Error_Context__c.SObjectType, 'read', new Set<String>{'Error_Log__c', 'Context_Type__c', 'Source__c', 'Sequence__c', 'Payload_JSON__c', 'Masked__c'});
        }
        requireAccess(Error_Log__c.SObjectType, 'read', fields);
        requireAccess(AI_Diagnosis__c.SObjectType, 'read', DIAGNOSIS_FIELDS);
        Id currentUserId = UserInfo.getUserId();
        String queryText = 'SELECT Id FROM Error_Log__c WHERE Id = :logId';
        if (!visible) queryText += ' AND User__c = :currentUserId';
        List<Error_Log__c> authorized = Database.queryWithBinds(queryText,
            new Map<String, Object>{'logId' => logId, 'currentUserId' => currentUserId}, AccessLevel.USER_MODE);
        if (authorized.isEmpty()) {
            respond(404, failure('The diagnostic was not found in the authorized scope.'));
            return;
        }
        AEIR_GetErrorContextAction.Request contextRequest = new AEIR_GetErrorContextAction.Request();
        contextRequest.errorLogId = String.valueOf(logId);
        List<AEIR_GetErrorContextAction.Response> results = AEIR_GetErrorContextAction.run(new List<AEIR_GetErrorContextAction.Request>{contextRequest});
        if (results.isEmpty() || String.isBlank(results[0].contextJson)) {
            respond(404, failure('The diagnostic context is unavailable.'));
            return;
        }
        respond(200, new Map<String, Object>{'correlationId' => results[0].correlationId,
            'context' => JSON.deserializeUntyped(results[0].contextJson), 'message' => results[0].message});
    }

    private static Boolean visibleScope(String scope) {
        if (String.isBlank(scope) || scope == 'mine') return false;
        if (scope != 'visible') throw new HeadlessException('Unknown diagnostic scope.');
        if (!FeatureManagement.checkPermission('AEIR_View_Sensitive_Context')) throw new HeadlessAccessException('Forbidden scope.');
        return true;
    }

    private static Boolean authorize() {
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.addHeader('Cache-Control', 'no-store');
        if (FeatureManagement.checkPermission('AEIR_Headless_Access')) return true;
        respond(403, failure('The Aegis Headless Access permission is required.'));
        return false;
    }

    /** Privileged adapters may derive audit fields, but cannot grant caller data access. */
    private static void requireAccess(Schema.SObjectType objectType, String operation, Set<String> fieldNames) {
        Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
        Boolean allowed = operation == 'read' ? objectDescribe.isAccessible()
            : operation == 'create' ? objectDescribe.isCreateable() : objectDescribe.isUpdateable();
        if (!allowed) throw new HeadlessAccessException('Diagnostic object access is required.');
        Map<String, Schema.SObjectField> fields = objectDescribe.fields.getMap();
        for (String fieldName : fieldNames) {
            if (!fields.containsKey(fieldName)) throw new HeadlessAccessException('Diagnostic field access is required.');
            Schema.DescribeFieldResult fieldDescribe = fields.get(fieldName).getDescribe();
            Boolean fieldAllowed = operation == 'read' ? fieldDescribe.isAccessible()
                : operation == 'create' ? fieldDescribe.isCreateable() : fieldDescribe.isUpdateable();
            if (!fieldAllowed) throw new HeadlessAccessException('Diagnostic field access is required.');
        }
    }

    private static void allowedParameters(Set<String> allowed) {
        allowedKeys(RestContext.request.params.keySet(), allowed);
    }
    private static void allowedKeys(Set<String> actual, Set<String> allowed) {
        Set<String> unexpected = new Set<String>(actual);
        unexpected.removeAll(allowed);
        if (!unexpected.isEmpty()) throw new HeadlessException('Unknown request parameter.');
    }
    private static String textValue(Map<String, Object> input, String key, Integer maximum) {
        Object value = input.get(key);
        if (value == null) return null;
        if (!(value instanceof String)) throw new HeadlessException('Text is required.');
        String result = (String) value;
        if (result.length() > maximum) throw new HeadlessException('Text exceeds the supported length.');
        return result;
    }

    private class CursorState {
        public Integer v;
        public String resource;
        public Id userId;
        public String queryKey;
        public Datetime since;
        public Datetime untilAt;
        public Datetime at;
        public Id lastId;
    }
    private static String digest(List<String> values) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(JSON.serialize(values))));
    }
    private static CursorState readCursor(String encoded, String resource, String queryKey, Schema.SObjectType objectType, Integer days) {
        if (encoded == null) return null;
        if (String.isBlank(encoded) || encoded.length() > 2048) throw new HeadlessException('Invalid cursor.');
        CursorState state = (CursorState) JSON.deserializeStrict(EncodingUtil.base64Decode(encoded).toString(), CursorState.class);
        Datetime nowValue = Datetime.now();
        if (state == null || state.v != 1 || state.resource != resource || state.userId != UserInfo.getUserId()
            || state.queryKey != queryKey || state.lastId == null || state.lastId.getSObjectType() != objectType
            || state.untilAt == null || state.untilAt > nowValue || state.untilAt < nowValue.addMinutes(-CURSOR_TTL_MINUTES)) {
            throw new HeadlessException('Invalid or expired cursor.');
        }
        if (resource == 'errors') {
            if (state.since == null || state.at == null || state.since != state.untilAt.addDays(-days)
                || state.at < state.since || state.at > state.untilAt) throw new HeadlessException('Invalid error cursor.');
        } else if (state.since != null || (state.at != null && state.at > state.untilAt)) {
            throw new HeadlessException('Invalid incident cursor.');
        }
        return state;
    }
    private static String writeCursor(String resource, String queryKey, Datetime since, Datetime untilAt, Datetime at, Id lastId) {
        CursorState state = new CursorState();
        state.v = 1;
        state.resource = resource;
        state.userId = UserInfo.getUserId();
        state.queryKey = queryKey;
        state.since = since;
        state.untilAt = untilAt;
        state.at = at;
        state.lastId = lastId;
        return EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(state)));
    }
    private static Integer bounded(String value, Integer fallback, Integer minimum, Integer maximum) {
        if (value == null) return fallback;
        if (value.length() > 9 || !Pattern.matches('[0-9]+', value)) throw new HeadlessException('Invalid numeric filter.');
        Integer parsed = Integer.valueOf(value);
        if (parsed < minimum || parsed > maximum) throw new HeadlessException('Filter outside supported bounds.');
        return parsed;
    }
    private static String route() {
        String uri = RestContext.request.requestURI;
        String marker = '/operations/';
        Integer start = uri == null ? -1 : uri.indexOf(marker);
        return start < 0 ? '' : uri.substring(start + marker.length()).removeEnd('/');
    }
    private static Map<String, Object> failure(String message) {
        return new Map<String, Object>{'success' => false, 'message' => message};
    }
    private static void respond(Integer statusCode, Object value) {
        RestContext.response.statusCode = statusCode;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(value));
    }
    private class HeadlessException extends Exception {}
    private class HeadlessAccessException extends Exception {}
}
