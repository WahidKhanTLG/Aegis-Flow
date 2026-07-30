/**
 * Flow-invocable developer escalation.
 *
 * Flow calls an invocable action once with every record in the batch, so this looped over
 * requests calling the single-record escalation API. Past roughly thirty records that
 * exhausted DML. Requests are now grouped by route key and escalated in bulk.
 *
 * Responses are matched back to requests by source record id, not by list position:
 * createForErrors() returns results in SOQL order, which is not the order the ids went in.
 */
public with sharing class AEIR_CreateEscalationAction {

    public class Request {
        @InvocableVariable public Id errorLogId;
        @InvocableVariable public Id diagnosticSessionId;
        @InvocableVariable public String routeKey;
        @InvocableVariable public Boolean sendEmailNow;
    }

    public class Response {
        @InvocableVariable public Id escalationId;
        @InvocableVariable public String status;
        @InvocableVariable public String subject;
    }

    @InvocableMethod(label='AEIR Create Developer Escalation'
        description='Creates a developer escalation package and optionally sends configured email.')
    public static List<Response> createEscalation(List<Request> requests) {
        List<Response> out = new List<Response>();
        if (requests == null || requests.isEmpty()) return out;

        // Grouped by route key AND send flag: both are per-request in the Flow signature, and
        // sendEmailNow cannot be collapsed without silently sending mail the Flow asked to
        // hold, or holding mail it asked to send.
        Map<String, RequestGroup> groups = new Map<String, RequestGroup>();
        for (Request req : requests) {
            if (req.errorLogId == null && req.diagnosticSessionId == null) continue;
            RequestGroup g = groupFor(groups, req);
            if (req.errorLogId != null) g.logIds.add(req.errorLogId);
            else g.sessionIds.add(req.diagnosticSessionId);
        }

        Map<Id, AEIR_EscalationService.EscalationResult> bySource =
            new Map<Id, AEIR_EscalationService.EscalationResult>();

        for (RequestGroup g : groups.values()) {
            if (!g.logIds.isEmpty()) {
                for (AEIR_EscalationService.EscalationResult result
                        : AEIR_EscalationService.createForErrors(g.logIds, g.routeKey, g.sendNow)) {
                    if (result != null && result.errorLogId != null) bySource.put(result.errorLogId, result);
                }
            }
            if (!g.sessionIds.isEmpty()) {
                for (AEIR_EscalationService.EscalationResult result
                        : AEIR_EscalationService.createForSessions(g.sessionIds, g.routeKey, g.sendNow)) {
                    if (result == null) continue;
                    // A session linked to a captured error escalates through the error path,
                    // so it comes back keyed by the log rather than the session.
                    if (result.diagnosticSessionId != null) bySource.put(result.diagnosticSessionId, result);
                    if (result.errorLogId != null) bySource.put(result.errorLogId, result);
                }
            }
        }

        // One response per request, in request order, as the invocable contract requires.
        for (Request req : requests) {
            AEIR_EscalationService.EscalationResult result =
                req.errorLogId != null ? bySource.get(req.errorLogId) : bySource.get(req.diagnosticSessionId);
            Response response = new Response();
            if (result == null) {
                // The source record no longer exists, or a linked session resolved to a log
                // this request never named. Say so rather than returning a blank row.
                response.status = 'Not Escalated';
            } else {
                response.escalationId = result.escalationId;
                response.status = result.status;
                response.subject = result.subject;
            }
            out.add(response);
        }
        return out;
    }

    /**
     * A batch of requests that can share one bulk call. Route key and send flag are both
     * per-request in the Flow signature: sendEmailNow cannot be collapsed without either
     * sending mail a Flow asked to hold, or holding mail it asked to send.
     */
    private class RequestGroup {
        String routeKey;
        Boolean sendNow;
        List<Id> logIds = new List<Id>();
        List<Id> sessionIds = new List<Id>();
    }

    private static RequestGroup groupFor(Map<String, RequestGroup> groups, Request req) {
        String routeKey = String.isBlank(req.routeKey) ? null : req.routeKey;
        Boolean sendNow = req.sendEmailNow == true;
        // Length-prefixed so a route key containing the separator cannot collide with another.
        String key = String.valueOf(routeKey == null ? 0 : routeKey.length())
            + ':' + routeKey + ':' + sendNow;
        RequestGroup g = groups.get(key);
        if (g == null) {
            g = new RequestGroup();
            g.routeKey = routeKey;
            g.sendNow = sendNow;
            groups.put(key, g);
        }
        return g;
    }

}