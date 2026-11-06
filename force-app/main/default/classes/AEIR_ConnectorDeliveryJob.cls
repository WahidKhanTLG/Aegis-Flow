/**
 * Named-Credential-only escalation outbox. Calls out before doing any DML and uses
 * finite batches of ten. Failed deliveries are never automatically re-posted: explicit
 * retry is privileged, bounded to three attempts, and respects Retry-After.
 */
public with sharing class AEIR_ConnectorDeliveryJob implements Queueable, Database.AllowsCallouts {
    public static final Integer MAX_ITEMS = 200;
    public static final Integer BATCH_SIZE = 10;
    public static final Integer MAX_ATTEMPTS = 3;
    private static final Integer MAX_CHAIN_DEPTH = 25;
    private List<Id> auditIds;
    @TestVisible private Boolean enabledOverride;
    @TestVisible private List<Escalation_Route__mdt> routeOverrides;
    public class ConnectorException extends Exception {}

    public AEIR_ConnectorDeliveryJob(List<Id> pendingAuditIds) {
        auditIds = new List<Id>();
        Set<Id> seen = new Set<Id>();
        if (pendingAuditIds != null) for (Id auditId : pendingAuditIds) {
            if (auditId != null && seen.add(auditId)) auditIds.add(auditId);
        }
        if (auditIds.size() > MAX_ITEMS) throw new ConnectorException('Connector dispatch supports at most 200 items.');
    }

    /** Enqueue and claim atomically, so explicit retries can recognize a live job. */
    public static Id enqueueAudits(List<Delivery_Audit__c> audits) {
        if (audits == null || audits.isEmpty()) return null;
        List<Id> ids = new List<Id>();
        for (Delivery_Audit__c audit : audits) if (audit.Id != null) ids.add(audit.Id);
        if (ids.isEmpty()) return null;
        Set<Id> requestedIds = new Set<Id>(ids);
        Boolean processor = isDeliveryProcessor();
        Id caller = UserInfo.getUserId();
        List<Delivery_Audit__c> available = (List<Delivery_Audit__c>)Database.queryWithBinds(
            'SELECT Id, CreatedById FROM Delivery_Audit__c WHERE Id IN :requestedIds',
            new Map<String, Object>{ 'requestedIds' => requestedIds }, AccessLevel.SYSTEM_MODE);
        if (available.size() != requestedIds.size()) throw new ConnectorException('The delivery claim is unavailable.');
        for (Delivery_Audit__c row : available) if (!processor && row.CreatedById != caller) {
            throw new ConnectorException('The delivery claim is unavailable to this user.');
        }
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) throw new ConnectorException('No queueable capacity remains in this transaction.');
        if (System.isQueueable() && AsyncInfo.hasMaxStackDepth()
            && AsyncInfo.getCurrentQueueableStackDepth() >= AsyncInfo.getMaximumQueueableStackDepth()) {
            throw new ConnectorException('The current queueable chain has reached its configured maximum depth.');
        }
        Savepoint claim = Database.setSavepoint();
        try {
            AEIR_ConnectorDeliveryJob worker = new AEIR_ConnectorDeliveryJob(ids);
            Id jobId;
            if (System.isQueueable()) {
                // Child jobs inherit the root chain's limit; it cannot be reset per hop.
                jobId = System.enqueueJob(worker);
            } else {
                AsyncOptions options = new AsyncOptions();
                // Up to20 finite batches plus room for an initial dispatcher. Explicitly
                // overrides the Developer/Trial default depth of five for new chains.
                options.MaximumQueueableStackDepth = MAX_CHAIN_DEPTH;
                jobId = System.enqueueJob(worker, options);
            }
            List<Delivery_Audit__c> claims = new List<Delivery_Audit__c>();
            for (Id auditId : ids) claims.add(new Delivery_Audit__c(Id = auditId,
                Response_Body__c = JSON.serialize(new Map<String, Object>{ 'state' => 'Queued', 'jobId' => jobId })));
            Database.update(claims, true, AccessLevel.SYSTEM_MODE);
            return jobId;
        } catch (Exception failure) {
            Database.rollback(claim);
            throw new ConnectorException('Connector work could not be queued with a durable delivery claim.');
        } finally {
            Database.releaseSavepoint(claim);
        }
    }

    public void execute(QueueableContext context) {
        if (auditIds.isEmpty() || context == null || context.getJobId() == null) return;
        Id currentJobId = context.getJobId();
        Boolean processor = isDeliveryProcessor();
        Boolean enabled = enabledOverride == null
            ? AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.CONNECTOR_EXTENSIONS) : enabledOverride;
        List<Id> currentIds = new List<Id>();
        List<Id> remainder = new List<Id>();
        for (Integer i = 0; i < auditIds.size(); i++) {
            if (!enabled || i < BATCH_SIZE) currentIds.add(auditIds[i]);
            else remainder.add(auditIds[i]);
        }
        // Technical evidence is read only by the trusted outbox worker. End users may
        // request an authorized escalation without gaining direct audit/evidence access.
        List<Delivery_Audit__c> audits = (List<Delivery_Audit__c>)Database.queryWithBinds(
            'SELECT Id, CreatedById, Response_Body__c, Status__c, Attempt_Count__c, Developer_Escalation__c, Correlation_Id__c, '
            + 'Developer_Escalation__r.Id, Developer_Escalation__r.Status__c, Developer_Escalation__r.Channel__c, '
            + 'Developer_Escalation__r.Route_Key__c, Developer_Escalation__r.Correlation_Id__c, '
            + 'Developer_Escalation__r.Subject__c, Developer_Escalation__r.Summary__c, '
            + 'Developer_Escalation__r.Severity__c, Developer_Escalation__r.Diagnostic_Package_JSON__c, '
            + 'Developer_Escalation__r.Sent_At__c FROM Delivery_Audit__c WHERE Id IN :currentIds',
            new Map<String, Object>{ 'currentIds' => currentIds }, AccessLevel.SYSTEM_MODE);
        Set<String> routeKeys = new Set<String>();
        for (Delivery_Audit__c audit : audits) if (audit.Developer_Escalation__c != null && ownsClaim(audit, currentJobId, processor)) routeKeys.add(audit.Developer_Escalation__r.Route_Key__c);
        Map<String, Escalation_Route__mdt> routes = routeOverrides == null
            ? AEIR_EscalationService.connectorRoutes(routeKeys) : routesByKey(routeOverrides);
        List<Delivery_Audit__c> auditUpdates = new List<Delivery_Audit__c>();
        Map<Id, Developer_Escalation__c> escalationUpdates = new Map<Id, Developer_Escalation__c>();
        Set<Id> handledEscalations = new Set<Id>();
        for (Delivery_Audit__c audit : audits) {
            if (audit.Status__c != 'Pending' || audit.Developer_Escalation__c == null || !ownsClaim(audit, currentJobId, processor)) continue;
            Developer_Escalation__c escalation = audit.Developer_Escalation__r;
            if (escalation.Status__c == 'Sent' || escalation.Sent_At__c != null) continue;
            if (!handledEscalations.add(escalation.Id)) continue;
            Escalation_Route__mdt route = routes.get(escalation.Route_Key__c);
            String problem = !enabled ? 'Connector extensions are disabled.' : routeConfigurationError(route);
            if (problem == null && route.Channel__c != escalation.Channel__c) problem = 'The route channel changed after dispatch.';
            if (problem != null) {
                audit.Response_Body__c = outcome('NotQueued', problem, null, null);
                auditUpdates.add(audit);
                continue;
            }
            String state = 'Failed';
            String message;
            Integer statusCode;
            Integer retryAfter;
            String reference;
            try {
                HttpResponse response = new Http().send(requestFor(escalation, route));
                statusCode = response.getStatusCode();
                Boolean accepted = statusCode >= 200 && statusCode < 300;
                Boolean explicitlyRejected = false;
                if (accepted && route.Channel__c == 'Slack') {
                    try {
                        Map<String, Object> slack = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                        explicitlyRejected = slack.get('ok') == false;
                        reference = slack.get('ts') == null ? null : String.valueOf(slack.get('ts'));
                        accepted = slack.get('ok') == true && reference != null && Pattern.matches('^[0-9]+[.][0-9]+$', reference);
                    } catch (Exception invalidSlackResponse) { accepted = false; }
                }
                if (accepted && new Set<String>{ 'Jira', 'GitHub Issue', 'Teams' }.contains(route.Channel__c)) {
                    accepted = statusCode == 201;
                    if (accepted) {
                        try {
                            Map<String, Object> body = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                            Object value = body.get(route.Channel__c == 'Jira' ? 'key' : route.Channel__c == 'GitHub Issue' ? 'number' : 'id');
                            reference = value == null ? null : String.valueOf(value);
                            accepted = !String.isBlank(reference) && Pattern.matches('^[A-Za-z0-9_.-]{1,255}$', reference);
                        } catch (Exception invalidResponse) { accepted = false; }
                    }
                }
                if (accepted) {
                    state = 'Delivered';
                    message = 'The configured destination accepted the escalation.';
                    escalation.Status__c = 'Sent';
                    escalation.Sent_At__c = Datetime.now();
                    if (reference != null) escalation.External_Ticket_Id__c = reference;
                } else {
                    state = (statusCode >= 500 || statusCode == 408 || (statusCode >= 200 && statusCode < 300 && !explicitlyRejected)) ? 'Uncertain' : 'Failed';
                    escalation.Status__c = statusCode == 429 ? 'Pending' : 'Failed';
                    retryAfter = statusCode == 429 ? retryDelay(response.getHeader('Retry-After')) : null;
                    message = state == 'Uncertain' ? 'The destination response did not confirm the expected resource. Reconcile before retrying.'
                        : 'The connector returned HTTP ' + statusCode + '. No automatic retry was scheduled.';
                }
            } catch (ConnectorException invalidPayload) {
                state = 'NotQueued';
                escalation.Status__c = 'Pending';
                message = invalidPayload.getMessage();
            } catch (Exception noConfirmedResponse) {
                state = 'Uncertain';
                escalation.Status__c = 'Failed';
                message = 'No confirmed response was received. Reconcile the external destination before retrying.';
                // Exceptions may contain a resolved secret webhook URL; never persist it.
                System.debug(LoggingLevel.WARN, 'Aegis connector callout failed without a confirmed response.');
            }
            audit.Status__c = state == 'Delivered' ? 'Delivered' : state == 'NotQueued' ? 'Pending' : 'Failed';
            audit.Endpoint__c = route.Named_Credential__c;
            audit.Response_Body__c = outcome(state, message, statusCode, retryAfter);
            auditUpdates.add(audit);
            Developer_Escalation__c updateRow = new Developer_Escalation__c(
                Id = escalation.Id, Status__c = escalation.Status__c, Sent_At__c = escalation.Sent_At__c);
            if (state == 'Delivered' && reference != null) updateRow.External_Ticket_Id__c = reference;
            escalationUpdates.put(escalation.Id, updateRow);
        }
        // All callouts above finish before the first database write.
        if (!auditUpdates.isEmpty()) Database.update(auditUpdates, true, AccessLevel.SYSTEM_MODE);
        if (!escalationUpdates.isEmpty()) Database.update(escalationUpdates.values(), true, AccessLevel.SYSTEM_MODE);
        if (!remainder.isEmpty()) {
            List<Delivery_Audit__c> next = new List<Delivery_Audit__c>();
            for (Delivery_Audit__c pending : (List<Delivery_Audit__c>)Database.queryWithBinds(
                'SELECT Id, CreatedById, Status__c, Response_Body__c FROM Delivery_Audit__c WHERE Id IN :remainder',
                new Map<String, Object>{ 'remainder' => remainder }, AccessLevel.SYSTEM_MODE)) {
                if (pending.Status__c == 'Pending' && ownsClaim(pending, currentJobId, processor)) next.add(new Delivery_Audit__c(Id = pending.Id));
            }
            try { enqueueAudits(next); }
            catch (Exception continuationUnavailable) {
                // Preserve confirmed results from this batch. A limited parent chain
                // must not roll back delivery outcomes or falsely claim unscheduled work.
                for (Delivery_Audit__c pending : next) pending.Response_Body__c = outcome('NotQueued',
                    'Continuation capacity was unavailable. Request an explicit retry in a new transaction.', null, null);
                Database.update(next, true, AccessLevel.SYSTEM_MODE);
                System.debug(LoggingLevel.WARN, 'Aegis connector continuation was deferred; remaining audits are Pending and not queued.');
            }
        }
    }

    /** Explicit recovery only: bounded attempts, active feature/config, no live-claim duplicates. */
    public static Map<Id, String> retryEscalations(List<Id> escalationIds) {
        if (!FeatureManagement.checkPermission('AEIR_Execute_Retry')) throw new ConnectorException('Aegis Execute Retry permission is required.');
        if (!AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.CONNECTOR_EXTENSIONS)) throw new ConnectorException('Connector extensions are disabled.');
        Set<Id> ids = escalationIds == null ? new Set<Id>() : new Set<Id>(escalationIds);
        if (ids.size() > MAX_ITEMS) throw new ConnectorException('Retry supports at most 200 escalations.');
        Map<Id, String> result = new Map<Id, String>();
        if (ids.isEmpty()) return result;
        List<Developer_Escalation__c> escalations = [SELECT Id, Route_Key__c, Status__c, Sent_At__c,
            Channel__c, Correlation_Id__c, Subject__c FROM Developer_Escalation__c WHERE Id IN :ids FOR UPDATE];
        Map<Id, Delivery_Audit__c> latest = new Map<Id, Delivery_Audit__c>();
        for (Delivery_Audit__c audit : [SELECT Id, Developer_Escalation__c, Status__c, Attempt_Count__c,
            Response_Body__c, LastModifiedDate FROM Delivery_Audit__c WHERE Developer_Escalation__c IN :ids
            ORDER BY Attempt_Count__c DESC, CreatedDate DESC]) {
            if (!latest.containsKey(audit.Developer_Escalation__c)) latest.put(audit.Developer_Escalation__c, audit);
        }
        Set<String> routeKeys = new Set<String>();
        Set<Id> jobIds = new Set<Id>();
        for (Developer_Escalation__c escalation : escalations) routeKeys.add(escalation.Route_Key__c);
        for (Delivery_Audit__c audit : latest.values()) {
            Map<String, Object> metadata = responseMetadata(audit.Response_Body__c);
            if (metadata.get('state') == 'Queued' && metadata.get('jobId') != null) {
                try { Id jobId = (Id)String.valueOf(metadata.get('jobId')); if (jobId.getSObjectType() == AsyncApexJob.SObjectType) jobIds.add(jobId); } catch (Exception invalidJobId) { /* Treat unverified claims as uncertain below. */ }
            }
        }
        Map<Id, AsyncApexJob> jobs = new Map<Id, AsyncApexJob>();
        if (!jobIds.isEmpty()) jobs = new Map<Id, AsyncApexJob>([SELECT Id, Status FROM AsyncApexJob WHERE Id IN :jobIds]);
        Map<String, Escalation_Route__mdt> routes = AEIR_EscalationService.connectorRoutes(routeKeys);
        List<Delivery_Audit__c> attempts = new List<Delivery_Audit__c>();
        List<Developer_Escalation__c> updates = new List<Developer_Escalation__c>();
        for (Developer_Escalation__c escalation : escalations) {
            if (escalation.Status__c == 'Sent' || escalation.Sent_At__c != null) { result.put(escalation.Id, 'Already delivered.'); continue; }
            Escalation_Route__mdt route = routes.get(escalation.Route_Key__c);
            String problem = routeConfigurationError(route);
            if (problem != null) { result.put(escalation.Id, problem); continue; }
            Delivery_Audit__c prior = latest.get(escalation.Id);
            Integer attemptNumber = prior == null || prior.Attempt_Count__c == null ? 1 : Integer.valueOf(prior.Attempt_Count__c) + 1;
            if (attemptNumber > MAX_ATTEMPTS) { result.put(escalation.Id, 'Maximum connector attempts reached.'); continue; }
            Map<String, Object> metadata = prior == null ? new Map<String, Object>() : responseMetadata(prior.Response_Body__c);
            if (metadata.get('state') == 'Uncertain') { result.put(escalation.Id, 'Reconcile the uncertain external outcome before retrying.'); continue; }
            if (metadata.get('state') == 'Queued') {
                Id jobId;
                try { jobId = (Id)String.valueOf(metadata.get('jobId')); } catch (Exception invalidJobId) { jobId = null; }
                AsyncApexJob job = jobs.get(jobId);
                result.put(escalation.Id, job != null && new Set<String>{ 'Queued', 'Preparing', 'Processing', 'Holding' }.contains(job.Status)
                    ? 'Delivery is already queued.' : 'The previous delivery job has no committed outcome. Reconcile before retrying.');
                continue;
            }
            Integer seconds = integerValue(metadata.get('retryAfterSeconds'));
            if (prior != null && seconds != null && prior.LastModifiedDate.addSeconds(seconds) > Datetime.now()) {
                result.put(escalation.Id, 'The destination Retry-After interval has not elapsed.'); continue;
            }
            attempts.add(new Delivery_Audit__c(Developer_Escalation__c = escalation.Id,
                Correlation_Id__c = escalation.Correlation_Id__c, Channel__c = escalation.Channel__c,
                Endpoint__c = route.Named_Credential__c, Payload_Summary__c = escalation.Subject__c,
                Status__c = 'Pending', Attempt_Count__c = attemptNumber,
                Response_Body__c = outcome('Ready', 'An explicit retry was requested.', null, null)));
            updates.add(new Developer_Escalation__c(Id = escalation.Id, Status__c = 'Pending'));
            result.put(escalation.Id, 'Queued');
        }
        if (!attempts.isEmpty()) {
            Database.insert(attempts, true, AccessLevel.SYSTEM_MODE);
            Database.update(updates, true, AccessLevel.SYSTEM_MODE);
            enqueueAudits(attempts);
        }
        return result;
    }

    public static String routeConfigurationError(Escalation_Route__mdt route) {
        if (route == null || route.Active__c != true) return 'No active connector route is configured.';
        if (!new Set<String>{ 'Webhook', 'Slack', 'Teams', 'Jira', 'GitHub Issue' }.contains(route.Channel__c)) return 'The route is not an outbound connector.';
        if (String.isBlank(route.Named_Credential__c)) return 'Configure a Named Credential before enabling this connector route.';
        if (!Pattern.matches('^[A-Za-z][A-Za-z0-9_]{0,79}$', route.Named_Credential__c)) return 'The Named Credential identifier is invalid.';
        if (!safePath(route.Endpoint_Path__c)) return 'Only a safe relative connector path is allowed; hosts, traversal, encoding and query authentication are prohibited.';
        try {
            Map<String, Object> target = target(route.Target__c);
            if (route.Channel__c == 'Slack') {
                requireTarget(target, 'channelId', '^[CGD][A-Z0-9]{1,79}$');
                if (!String.isBlank(route.Endpoint_Path__c) && route.Endpoint_Path__c != '/api/chat.postMessage') return 'Slack uses the /api/chat.postMessage endpoint.';
            }
            if (route.Channel__c == 'Jira') {
                requireTarget(target, 'projectKey', '^[A-Za-z][A-Za-z0-9_]{0,99}$');
                requireTarget(target, 'issueTypeId', '^[0-9]{1,30}$');
                if (!String.isBlank(route.Endpoint_Path__c) && route.Endpoint_Path__c != '/rest/api/3/issue') return 'Jira uses the /rest/api/3/issue endpoint.';
            } else if (route.Channel__c == 'GitHub Issue') {
                requireTarget(target, 'owner', '^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$');
                requireTarget(target, 'repo', '^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$');
                String path = '/repos/' + target.get('owner') + '/' + target.get('repo') + '/issues';
                if (!String.isBlank(route.Endpoint_Path__c) && route.Endpoint_Path__c != path) return 'GitHub Endpoint Path must match the configured owner/repository issue endpoint.';
            } else if (route.Channel__c == 'Teams') {
                requireTarget(target, 'teamId', '^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$');
                requireTarget(target, 'channelId', '^[A-Za-z0-9][A-Za-z0-9:@._-]{0,179}$');
                if (!String.isBlank(route.Endpoint_Path__c)) return 'Teams Graph derives its path from Target; leave Endpoint Path blank.';
            }
        } catch (Exception invalidTarget) { return 'Configure valid non-secret Target JSON with the required provider identifiers.'; }
        return null;
    }

    @TestVisible private static HttpRequest requestFor(Developer_Escalation__c escalation, Escalation_Route__mdt route) {
        String problem = routeConfigurationError(route);
        if (problem != null) throw new ConnectorException(problem);
        Map<String, Object> target = target(route.Target__c);
        String path = String.isBlank(route.Endpoint_Path__c) ? '' : route.Endpoint_Path__c;
        String subject = AEIR_SecuritySanitizerService.safeTruncate(AEIR_SecuritySanitizerService.mask(escalation.Subject__c), 240);
        String summary = AEIR_SecuritySanitizerService.safeTruncate(AEIR_SecuritySanitizerService.mask(escalation.Summary__c), 2800);
        String text = subject + '\n' + summary + '\nReference: ' + escalation.Correlation_Id__c
            + '\nEvidence: ' + URL.getOrgDomainUrl().toExternalForm() + '/' + escalation.Id;
        Object body;
        if (route.Channel__c == 'Slack') {
            path = '/api/chat.postMessage';
            body = new Map<String, Object>{ 'channel' => target.get('channelId'),
                'text' => text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;'),
                'mrkdwn' => false, 'parse' => 'none', 'link_names' => false,
                'unfurl_links' => false, 'unfurl_media' => false };
        }
        else if (route.Channel__c == 'Teams') {
            path = '/v1.0/teams/' + EncodingUtil.urlEncode((String)target.get('teamId'), 'UTF-8')
                + '/channels/' + EncodingUtil.urlEncode((String)target.get('channelId'), 'UTF-8') + '/messages';
            body = new Map<String, Object>{ 'body' => new Map<String, Object>{ 'contentType' => 'text', 'content' => text } };
        } else if (route.Channel__c == 'GitHub Issue') {
            path = '/repos/' + target.get('owner') + '/' + target.get('repo') + '/issues';
            body = new Map<String, Object>{ 'title' => AEIR_SecuritySanitizerService.safeTruncate(escalation.Subject__c, 240), 'body' => text };
        } else if (route.Channel__c == 'Jira') {
            path = '/rest/api/3/issue';
            body = new Map<String, Object>{ 'fields' => new Map<String, Object>{
                'project' => new Map<String, Object>{ 'key' => target.get('projectKey') },
                'issuetype' => new Map<String, Object>{ 'id' => target.get('issueTypeId') },
                'summary' => AEIR_SecuritySanitizerService.safeTruncate(escalation.Subject__c, 240),
                'description' => new Map<String, Object>{ 'type' => 'doc', 'version' => 1,
                    'content' => new List<Object>{ new Map<String, Object>{ 'type' => 'paragraph',
                        'content' => new List<Object>{ new Map<String, Object>{ 'type' => 'text', 'text' => text } } } } }
            } };
        } else {
            Object diagnostic;
            try { diagnostic = JSON.deserializeUntyped(AEIR_SecuritySanitizerService.mask(escalation.Diagnostic_Package_JSON__c)); }
            catch (Exception invalidDiagnostic) { throw new ConnectorException('The sanitized diagnostic package is invalid. Repair its evidence before sending.'); }
            body = new Map<String, Object>{ 'schemaVersion' => '1.0', 'eventType' => 'aegis.escalation.created',
                'escalationId' => escalation.Id, 'organizationId' => UserInfo.getOrganizationId(), 'correlationId' => escalation.Correlation_Id__c,
                'severity' => escalation.Severity__c, 'subject' => escalation.Subject__c,
                'summary' => escalation.Summary__c, 'diagnostic' => diagnostic };
        }
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:' + route.Named_Credential__c + path);
        request.setMethod('POST');
        request.setTimeout(10000);
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Idempotency-Key', 'aegis-escalation-' + UserInfo.getOrganizationId() + '-' + escalation.Id);
        if (!String.isBlank(escalation.Correlation_Id__c) && Pattern.matches('^[A-Za-z0-9_.:-]{1,80}$', escalation.Correlation_Id__c)) request.setHeader('X-Aegis-Correlation-Id', escalation.Correlation_Id__c);
        if (route.Channel__c == 'GitHub Issue') {
            request.setHeader('Accept', 'application/vnd.github+json');
            request.setHeader('X-GitHub-Api-Version', '2026-03-10');
        }
        request.setBody(AEIR_SecuritySanitizerService.mask(JSON.serialize(body)));
        return request;
    }

    private static Boolean isDeliveryProcessor() {
        return FeatureManagement.checkPermission('AEIR_Execute_Retry')
            || FeatureManagement.checkPermission('AEIR_Process_Diagnostics');
    }
    private static Boolean ownsClaim(Delivery_Audit__c audit, Id jobId, Boolean processor) {
        if (!processor && audit.CreatedById != UserInfo.getUserId()) return false;
        Map<String, Object> claim = responseMetadata(audit.Response_Body__c);
        return claim.get('state') == 'Queued' && String.valueOf(claim.get('jobId')) == String.valueOf(jobId);
    }
    private static Boolean safePath(String path) {
        if (String.isBlank(path)) return true;
        if (!Pattern.matches('^/[A-Za-z0-9_./-]*$', path) || path.contains('//')) return false;
        for (String segment : path.split('/')) if (segment == '.' || segment == '..') return false;
        return true;
    }
    private static Map<String, Object> target(String input) {
        return String.isBlank(input) ? new Map<String, Object>() : (Map<String, Object>)JSON.deserializeUntyped(input);
    }
    private static void requireTarget(Map<String, Object> target, String key, String expression) {
        Object value = target.get(key);
        if (!(value instanceof String) || !Pattern.matches(expression, (String)value)) throw new ConnectorException('Invalid target identifier.');
    }
    private static Map<String, Escalation_Route__mdt> routesByKey(List<Escalation_Route__mdt> rows) {
        Map<String, Escalation_Route__mdt> routes = new Map<String, Escalation_Route__mdt>();
        for (Escalation_Route__mdt route : rows) routes.put(route.Route_Key__c, route);
        return routes;
    }
    private static Integer retryDelay(String value) {
        Integer seconds = integerValue(value);
        if (seconds != null) return Math.max(1, seconds);
        if (String.isBlank(value)) return 60;
        try {
            List<String> parts = value.trim().split(' ');
            Map<String, String> months = new Map<String, String>{ 'Jan'=>'01', 'Feb'=>'02', 'Mar'=>'03', 'Apr'=>'04',
                'May'=>'05', 'Jun'=>'06', 'Jul'=>'07', 'Aug'=>'08', 'Sep'=>'09', 'Oct'=>'10', 'Nov'=>'11', 'Dec'=>'12' };
            if (parts.size() != 6 || !months.containsKey(parts[2]) || parts[5] != 'GMT') return 60;
            Datetime retryAt = Datetime.valueOfGmt(parts[3] + '-' + months.get(parts[2]) + '-' + parts[1] + ' ' + parts[4]);
            Long delay = (retryAt.getTime() - Datetime.now().getTime()) / 1000;
            return delay > 2147483647 ? 2147483647 : Math.max(1, Integer.valueOf(String.valueOf(delay)));
        } catch (Exception invalidRetryAfter) { return 60; }
    }
    private static Integer integerValue(Object value) {
        try { return value == null ? null : Integer.valueOf(String.valueOf(value)); }
        catch (Exception invalidNumber) { return null; }
    }
    private static Map<String, Object> responseMetadata(String text) {
        try { return String.isBlank(text) ? new Map<String, Object>() : (Map<String, Object>)JSON.deserializeUntyped(text); }
        catch (Exception legacyText) { return new Map<String, Object>(); }
    }
    private static String outcome(String state, String message, Integer status, Integer retryAfter) {
        return JSON.serialize(new Map<String, Object>{ 'state' => state, 'message' => message,
            'httpStatus' => status, 'retryAfterSeconds' => retryAfter, 'completedAt' => Datetime.now() });
    }
}
