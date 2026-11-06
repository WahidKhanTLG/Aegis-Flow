/**
 * Flow-invocable record snapshot.
 *
 * Flow passes the whole batch in one call, and this issued one query per request. Snapshots
 * are now resolved through the batched API, so cost scales with the number of distinct
 * objects rather than the number of records.
 *
 * forEscalation is per-request and changes which fields are whitelisted, so the batch is
 * split on it: collapsing the flag would leak escalation-only fields into an agent snapshot.
 */
public with sharing class AEIR_GetRecordSnapshotAction {
    private static final Integer MAX_REQUESTS = 200;
    private static final Integer MAX_OBJECTS = 20;

    public class Request {
        @InvocableVariable(required=true) public String objectApiName;
        @InvocableVariable(required=true) public String recordId;
        @InvocableVariable public Boolean forEscalation;
        public Request() {}
    }

    public class Response {
        @InvocableVariable public String snapshotJson;
        @InvocableVariable public String message;
        public Response() {}
    }

    @InvocableMethod(label='Aegis Flow: Get Record Snapshot'
        description='Returns fields explicitly whitelisted in Context_Field_Setting__mdt.')
    public static List<Response> run(List<Request> requests) {
        List<Response> output = new List<Response>();
        if (requests == null || requests.isEmpty()) return output;

        Map<String, Set<String>> escalationIdsByObject = new Map<String, Set<String>>();
        Map<String, Set<String>> agentIdsByObject = new Map<String, Set<String>>();
        Map<Integer, String> errors = new Map<Integer, String>();
        Map<Integer, String> normalizedIds = new Map<Integer, String>();
        Map<String, Schema.SObjectType> objectTypes = Schema.getGlobalDescribe();
        Set<String> objectNames = new Set<String>();
        for (Integer i = 0; i < requests.size(); i++) {
            Request request = requests[i];
            if (i >= MAX_REQUESTS) { errors.put(i, 'This snapshot batch supports at most 200 requests.'); continue; }
            if (request == null || String.isBlank(request.objectApiName) || String.isBlank(request.recordId)) {
                errors.put(i, 'An object API name and a record id are both required.'); continue;
            }
            if (request.objectApiName.length() > 100 || !objectTypes.containsKey(request.objectApiName)
                || !objectTypes.get(request.objectApiName).getDescribe().isAccessible()) {
                errors.put(i, 'The requested object is invalid or inaccessible.'); continue;
            }
            Id recordId;
            try {
                if (request.recordId.length() != 15 && request.recordId.length() != 18) {
                    errors.put(i, 'A valid record id is required.'); continue;
                }
                recordId = (Id) request.recordId;
                if (recordId.getSObjectType() != objectTypes.get(request.objectApiName)) {
                    errors.put(i, 'The record id does not match the requested object.'); continue;
                }
            } catch (Exception invalidId) { errors.put(i, 'A valid record id is required.'); continue; }
            if (!objectNames.contains(request.objectApiName) && objectNames.size() >= MAX_OBJECTS) {
                errors.put(i, 'This snapshot batch supports at most 20 object types.'); continue;
            }
            objectNames.add(request.objectApiName);
            normalizedIds.put(i, String.valueOf(recordId));
            add(request.forEscalation == true ? escalationIdsByObject : agentIdsByObject,
                request.objectApiName, String.valueOf(recordId));
        }

        Map<String, String> escalationSnapshots =
            AEIR_ContextSnapshotService.getSnapshots(escalationIdsByObject, true);
        Map<String, String> agentSnapshots =
            AEIR_ContextSnapshotService.getSnapshots(agentIdsByObject, false);

        for (Integer i = 0; i < requests.size(); i++) {
            Request request = requests[i];
            Response response = new Response();
            if (errors.containsKey(i)) {
                response.message = errors.get(i);
                output.add(response);
                continue;
            }
            response.snapshotJson = request.forEscalation == true
                ? escalationSnapshots.get(normalizedIds.get(i))
                : agentSnapshots.get(normalizedIds.get(i));
            // A missing entry means the record was deleted, is not accessible to this user,
            // or has no whitelisted fields. Say which outcome it is rather than returning
            // null alongside a success message.
            response.message = response.snapshotJson == null
                ? 'No snapshot available: the record is inaccessible or has no whitelisted fields.'
                : 'Whitelisted record snapshot returned.';
            output.add(response);
        }
        return output;
    }

    private static void add(Map<String, Set<String>> target, String objectApiName, String recordId) {
        if (!target.containsKey(objectApiName)) target.put(objectApiName, new Set<String>());
        target.get(objectApiName).add(recordId);
    }
}
