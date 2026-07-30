public with sharing class AEIR_FindRecentErrorsAction {
    private static final Integer RESULTS_PER_REQUEST = 10;

    public class Request {
        @InvocableVariable public String recordId;
        @InvocableVariable public String objectApiName;
        public Request() {}
    }
    public class Response {
        @InvocableVariable public String resultsJson;
        @InvocableVariable public String message;
        public Response() {}
    }

    /**
     * Invocable methods receive bulk request lists, so this issues at most three
     * queries for the whole invocation rather than one per request. Results are
     * bucketed by record id and object api name, then mapped back to each request.
     */
    @InvocableMethod(label='Aegis Flow: Find Recent Errors' description='Finds recent visible errors for the current user and supplied record context.')
    public static List<Response> run(List<Request> requests) {
        List<Response> output = new List<Response>();
        if (requests == null || requests.isEmpty()) return output;

        Id currentUserId = UserInfo.getUserId();
        Set<String> recordIds = new Set<String>();
        Set<String> objectNames = new Set<String>();
        Boolean needsUserScope = false;

        for (Request request : requests) {
            if (request == null) { needsUserScope = true; continue; }
            if (!String.isBlank(request.recordId)) recordIds.add(request.recordId);
            else if (!String.isBlank(request.objectApiName)) objectNames.add(request.objectApiName);
            else needsUserScope = true;
        }

        Map<String, List<Error_Log__c>> byRecordId = new Map<String, List<Error_Log__c>>();
        Map<String, List<Error_Log__c>> byObjectName = new Map<String, List<Error_Log__c>>();
        List<Error_Log__c> userScoped = new List<Error_Log__c>();

        if (!recordIds.isEmpty()) {
            for (Error_Log__c row : [
                SELECT Id, Name, Correlation_Id__c, Severity__c, Error_Category__c, Status__c, Record_Id__c, CreatedDate
                FROM Error_Log__c
                WHERE User__c = :currentUserId AND Record_Id__c IN :recordIds AND CreatedDate = LAST_N_DAYS:1
                ORDER BY CreatedDate DESC
            ]) {
                if (!byRecordId.containsKey(row.Record_Id__c)) byRecordId.put(row.Record_Id__c, new List<Error_Log__c>());
                List<Error_Log__c> bucket = byRecordId.get(row.Record_Id__c);
                if (bucket.size() < RESULTS_PER_REQUEST) bucket.add(row);
            }
        }

        if (!objectNames.isEmpty()) {
            for (Error_Log__c row : [
                SELECT Id, Name, Correlation_Id__c, Severity__c, Error_Category__c, Status__c, Object_API_Name__c, CreatedDate
                FROM Error_Log__c
                WHERE User__c = :currentUserId AND Object_API_Name__c IN :objectNames AND CreatedDate = LAST_N_DAYS:1
                ORDER BY CreatedDate DESC
            ]) {
                if (!byObjectName.containsKey(row.Object_API_Name__c)) byObjectName.put(row.Object_API_Name__c, new List<Error_Log__c>());
                List<Error_Log__c> bucket = byObjectName.get(row.Object_API_Name__c);
                if (bucket.size() < RESULTS_PER_REQUEST) bucket.add(row);
            }
        }

        if (needsUserScope) {
            userScoped = [
                SELECT Id, Name, Correlation_Id__c, Severity__c, Error_Category__c, Status__c, CreatedDate
                FROM Error_Log__c
                WHERE User__c = :currentUserId AND CreatedDate = LAST_N_DAYS:1
                ORDER BY CreatedDate DESC LIMIT :RESULTS_PER_REQUEST
            ];
        }

        for (Request request : requests) {
            Response response = new Response();
            List<Error_Log__c> rows;
            if (request != null && !String.isBlank(request.recordId)) {
                rows = byRecordId.get(request.recordId);
            } else if (request != null && !String.isBlank(request.objectApiName)) {
                rows = byObjectName.get(request.objectApiName);
            } else {
                rows = userScoped;
            }
            if (rows == null) rows = new List<Error_Log__c>();
            response.resultsJson = JSON.serialize(rows);
            response.message = rows.size() + ' recent error(s) returned.';
            output.add(response);
        }
        return output;
    }
}