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
        for (Request request : requests) {
            if (String.isBlank(request.objectApiName) || String.isBlank(request.recordId)) continue;
            add(request.forEscalation == true ? escalationIdsByObject : agentIdsByObject,
                request.objectApiName, request.recordId);
        }

        Map<String, String> escalationSnapshots =
            AEIR_ContextSnapshotService.getSnapshots(escalationIdsByObject, true);
        Map<String, String> agentSnapshots =
            AEIR_ContextSnapshotService.getSnapshots(agentIdsByObject, false);

        for (Request request : requests) {
            Response response = new Response();
            if (String.isBlank(request.objectApiName) || String.isBlank(request.recordId)) {
                response.message = 'An object API name and a record id are both required.';
                output.add(response);
                continue;
            }
            response.snapshotJson = request.forEscalation == true
                ? escalationSnapshots.get(request.recordId)
                : agentSnapshots.get(request.recordId);
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