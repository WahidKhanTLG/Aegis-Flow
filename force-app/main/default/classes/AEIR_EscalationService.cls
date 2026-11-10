/**
 * Builds and routes developer escalation packages.
 *
 * The original implementation was single-record: each escalation cost roughly five DML
 * (insert escalation, insert audit, update escalation, update audit, update log) plus a
 * record-snapshot query per record. A platform event batch or an invocable action handling
 * more than about thirty records exhausted DML limits.
 *
 * Everything now flows through createForErrors(), which builds the whole set first and
 * flushes each channel once: one email send, one Case insert, one audit insert, one status
 * update. Cost is bounded regardless of batch size, and the single-record entry points
 * delegate to the bulk path so the two cannot diverge in behaviour.
 */
public with sharing class AEIR_EscalationService {

    public class EscalationResult {
        @AuraEnabled public Id escalationId;
        /**
         * The source record this escalation came from. createForErrors() returns results in
         * SOQL order, not input order, so a bulk caller cannot correlate by index. These two
         * fields are the correlation key.
         */
        @AuraEnabled public Id errorLogId;
        @AuraEnabled public Id diagnosticSessionId;
        @AuraEnabled public String status;
        @AuraEnabled public String subject;
        @AuraEnabled public String recipient;
        @AuraEnabled public String channel;
    }

    public class AEIR_Exception extends Exception {}
    public class AEIR_EscalationException extends Exception {}

    // ---------- entry points ----------

    /** Single-record convenience. Delegates to the bulk path. */
    public static EscalationResult createForError(Id errorLogId, String routeKey, Boolean sendEmailNow) {
        List<EscalationResult> results = createForErrors(new List<Id>{ errorLogId }, routeKey, sendEmailNow);
        return results.isEmpty() ? null : results[0];
    }

    /** Bulk escalation: one insert, one dispatch pass, one status update for the whole set. */
    public static List<EscalationResult> createForErrors(List<Id> errorLogIds, String routeKey, Boolean sendNow) {
        List<EscalationResult> out = new List<EscalationResult>();
        if (errorLogIds == null || errorLogIds.isEmpty()) return out;

        String errorLogQuery = 'SELECT Id, Correlation_Id__c, Error_Category__c, Severity__c, Source_Type__c, Source_Name__c, '
            + 'Original_Error_Message__c, Normalized_Message__c, Stack_Trace__c, Object_API_Name__c, '
            + 'Record_Id__c, User__c, Page_URL__c, Action_Name__c, Debug_Log_Link__c '
            + 'FROM Error_Log__c WHERE Id IN :errorLogIds FOR UPDATE';
        List<Error_Log__c> logs = Database.query(errorLogQuery, AccessLevel.SYSTEM_MODE);
        if (logs.isEmpty()) return out;

        // Snapshots batched by object, so cost scales with distinct objects not records.
        Map<String, Set<String>> idsByObject = new Map<String, Set<String>>();
        for (Error_Log__c log : logs) {
            if (String.isBlank(log.Object_API_Name__c) || String.isBlank(log.Record_Id__c)) continue;
            if (!idsByObject.containsKey(log.Object_API_Name__c)) {
                idsByObject.put(log.Object_API_Name__c, new Set<String>());
            }
            idsByObject.get(log.Object_API_Name__c).add(log.Record_Id__c);
        }
        Map<String, String> snapshots = AEIR_ContextSnapshotService.getSnapshots(idsByObject, true);

        List<Developer_Escalation__c> escalations = new List<Developer_Escalation__c>();
        for (Error_Log__c log : logs) {
            Escalation_Route__mdt route = findRoute(routeKey, log.Source_Type__c, log.Severity__c);
            String diagnosticPackage = buildPackage(log, null, snapshots.get(log.Record_Id__c));
            Developer_Escalation__c escalation = new Developer_Escalation__c(
                Request_Key__c = requestKey(log.Id, route.Route_Key__c),
                Correlation_Id__c = log.Correlation_Id__c,
                Error_Log__c = log.Id,
                Route_Key__c = route.Route_Key__c,
                Channel__c = safeChannel(route.Channel__c),
                Recipient__c = recipientFor(route, 'Developer'),
                Severity__c = log.Severity__c,
                Subject__c = '[Aegis Flow] ' + log.Severity__c + ' | ' + log.Source_Type__c + ' | ' + log.Correlation_Id__c,
                Summary__c = log.Normalized_Message__c,
                Diagnostic_Package_JSON__c = diagnosticPackage,
                Status__c = 'New',
                SLA_Due_At__c = AEIR_PolicyConfigService.resolveSlaDueAt(log.Severity__c)
            );
            if (log.User__c != null) escalation.OwnerId = log.User__c;
            escalations.add(escalation);
        }

        Set<Id> changedSources = new Set<Id>();
        escalations = persistAndDispatch(escalations, sendNow, changedSources);

        List<Error_Log__c> statusUpdates = new List<Error_Log__c>();
        for (Error_Log__c log : logs) if (changedSources.contains(log.Id)) {
            statusUpdates.add(new Error_Log__c(Id = log.Id, Status__c = 'Escalated'));
        }
        if (!statusUpdates.isEmpty()) Database.update(statusUpdates, true, AccessLevel.SYSTEM_MODE);

        for (Developer_Escalation__c escalation : escalations) out.add(result(escalation));
        return out;
    }

    /** Single-record convenience. Delegates to the bulk path. */
    public static EscalationResult createForSession(Id sessionId, String routeKey, Boolean sendEmailNow) {
        List<EscalationResult> results = createForSessions(new List<Id>{ sessionId }, routeKey, sendEmailNow);
        return results.isEmpty() ? null : results[0];
    }

    /**
     * Bulk manual escalation. A session that already points at a captured error is routed
     * through the error path instead, so a "get help" click on a real failure produces the
     * same package as an automatic escalation rather than a description-only one.
     */
    public static List<EscalationResult> createForSessions(List<Id> sessionIds, String routeKey, Boolean sendNow) {
        List<EscalationResult> out = new List<EscalationResult>();
        if (sessionIds == null || sessionIds.isEmpty()) return out;

        List<Diagnostic_Session__c> sessions = [
            SELECT Id, Correlation_Id__c, User_Description__c, Object_API_Name__c,
                   Context_Record_Id__c, Page_URL__c, User__c, Recent_Error_Log__c, Agent_Response__c
            FROM Diagnostic_Session__c WHERE Id IN :sessionIds FOR UPDATE
        ];
        if (sessions.isEmpty()) return out;

        // Sessions carrying a captured error delegate to the error path, in one batch.
        List<Id> linkedLogIds = new List<Id>();
        List<Diagnostic_Session__c> manualOnly = new List<Diagnostic_Session__c>();
        for (Diagnostic_Session__c session : sessions) {
            if (session.Recent_Error_Log__c != null) linkedLogIds.add(session.Recent_Error_Log__c);
            else manualOnly.add(session);
        }
        if (!linkedLogIds.isEmpty()) out.addAll(createForErrors(linkedLogIds, routeKey, sendNow));
        if (manualOnly.isEmpty()) return out;

        List<Developer_Escalation__c> escalations = new List<Developer_Escalation__c>();
        for (Diagnostic_Session__c session : manualOnly) {
            Escalation_Route__mdt route = findRoute(routeKey, 'Manual', 'Medium');
            String diagnosticPackage = buildPackage(null, session, null);
            Developer_Escalation__c escalation = new Developer_Escalation__c(
                Request_Key__c = requestKey(session.Id, route.Route_Key__c),
                Correlation_Id__c = session.Correlation_Id__c,
                Diagnostic_Session__c = session.Id,
                Route_Key__c = route.Route_Key__c,
                Channel__c = safeChannel(route.Channel__c),
                Recipient__c = recipientFor(route, 'Admin'),
                Severity__c = 'Medium',
                Subject__c = '[Aegis Flow] Manual diagnostic | ' + session.Correlation_Id__c,
                Summary__c = session.User_Description__c,
                Diagnostic_Package_JSON__c = diagnosticPackage,
                Status__c = 'New',
                SLA_Due_At__c = AEIR_PolicyConfigService.resolveSlaDueAt('Medium')
            );
            if (session.User__c != null) escalation.OwnerId = session.User__c;
            escalations.add(escalation);
            session.Resolution_Status__c = 'Escalated';
            session.Needs_Escalation__c = true;
        }

        Set<Id> changedSources = new Set<Id>();
        escalations = persistAndDispatch(escalations, sendNow, changedSources);
        List<Diagnostic_Session__c> statusUpdates = new List<Diagnostic_Session__c>();
        for (Diagnostic_Session__c session : manualOnly) if (changedSources.contains(session.Id)) {
            statusUpdates.add(new Diagnostic_Session__c(Id = session.Id, Resolution_Status__c = 'Escalated', Needs_Escalation__c = true));
        }
        if (!statusUpdates.isEmpty()) Database.update(statusUpdates, true, AccessLevel.SYSTEM_MODE);

        for (Developer_Escalation__c escalation : escalations) out.add(result(escalation));
        return out;
    }

    /** One logical escalation per source and canonical route. No implicit resend. */
    private static String requestKey(Id sourceId, String routeKey) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(JSON.serialize(
            new List<String>{String.valueOf(sourceId), String.isBlank(routeKey) ? '' : routeKey.trim().toLowerCase()}))));
    }

    private static List<Developer_Escalation__c> persistAndDispatch(
        List<Developer_Escalation__c> candidates, Boolean sendNow, Set<Id> changedSources) {
        Set<Id> sourceIds = new Set<Id>();
        for (Developer_Escalation__c row : candidates) sourceIds.add(row.Error_Log__c == null ? row.Diagnostic_Session__c : row.Error_Log__c);
        // Include legacy rows whose new request key is still null; never resend their
        // completed/failed/pending delivery merely because metadata was upgraded.
        List<Developer_Escalation__c> prior = Database.queryWithBinds(
            'SELECT Id, Request_Key__c, Delivery_Requested_At__c, Error_Log__c, Diagnostic_Session__c, '
            + 'Status__c, Subject__c, Recipient__c, Channel__c, Route_Key__c, Diagnostic_Package_JSON__c, '
            + 'Summary__c, Severity__c, Correlation_Id__c, SLA_Due_At__c FROM Developer_Escalation__c '
            + 'WHERE Error_Log__c IN :sourceIds OR Diagnostic_Session__c IN :sourceIds ORDER BY CreatedDate ASC, Id ASC',
            new Map<String, Object>{'sourceIds' => sourceIds}, AccessLevel.SYSTEM_MODE);
        Map<String, Developer_Escalation__c> existing = new Map<String, Developer_Escalation__c>();
        Set<Id> legacyIds = new Set<Id>();
        for (Developer_Escalation__c row : prior) {
            String key = requestKey(row.Error_Log__c == null ? row.Diagnostic_Session__c : row.Error_Log__c, row.Route_Key__c);
            Developer_Escalation__c chosen = existing.get(key);
            if (chosen == null || (chosen.Request_Key__c == null && row.Request_Key__c != null)
                || (chosen.Request_Key__c == null && row.Request_Key__c == null
                    && chosen.Status__c == 'New' && row.Status__c != 'New')) existing.put(key, row);
            if (row.Request_Key__c == null) legacyIds.add(row.Id);
        }
        Set<Id> previouslyAttempted = new Set<Id>();
        if (!legacyIds.isEmpty()) for (Delivery_Audit__c audit : [SELECT Developer_Escalation__c
            FROM Delivery_Audit__c WHERE Developer_Escalation__c IN :legacyIds]) previouslyAttempted.add(audit.Developer_Escalation__c);
        Set<String> priorDeliveryKeys = new Set<String>();
        for (Developer_Escalation__c row : prior) {
            if (row.Status__c != 'New' || row.Delivery_Requested_At__c != null || previouslyAttempted.contains(row.Id)) {
                priorDeliveryKeys.add(requestKey(row.Error_Log__c == null ? row.Diagnostic_Session__c : row.Error_Log__c, row.Route_Key__c));
            }
        }

        List<Developer_Escalation__c> output = new List<Developer_Escalation__c>();
        List<Developer_Escalation__c> inserts = new List<Developer_Escalation__c>();
        List<Developer_Escalation__c> patches = new List<Developer_Escalation__c>();
        List<Developer_Escalation__c> dispatch = new List<Developer_Escalation__c>();
        List<String> packages = new List<String>();
        for (Developer_Escalation__c candidate : candidates) {
            Developer_Escalation__c row = existing.get(candidate.Request_Key__c);
            Boolean fresh = row == null;
            if (fresh) { row = candidate; inserts.add(row); existing.put(row.Request_Key__c, row); }
            if (fresh) changedSources.add(row.Error_Log__c == null ? row.Diagnostic_Session__c : row.Error_Log__c);
            Boolean changed = false;
            if (row.Request_Key__c == null) { row.Request_Key__c = candidate.Request_Key__c; changed = true; }
            if (sendNow == true && row.Status__c == 'New' && row.Delivery_Requested_At__c == null
                && !priorDeliveryKeys.contains(candidate.Request_Key__c)) {
                row.Delivery_Requested_At__c = Datetime.now();
                changedSources.add(row.Error_Log__c == null ? row.Diagnostic_Session__c : row.Error_Log__c);
                changed = true;
                dispatch.add(row);
                packages.add(row.Diagnostic_Package_JSON__c);
            }
            if (!fresh && changed) patches.add(row);
            output.add(row);
        }
        if (!inserts.isEmpty()) Database.insert(inserts, true, AccessLevel.SYSTEM_MODE);
        if (!patches.isEmpty()) Database.update(patches, true, AccessLevel.SYSTEM_MODE);
        // The source row lock and durable claim remain held until commit. A second
        // transaction observes the existing claim and can only return the prior result.
        dispatchAll(dispatch, packages, sendNow);
        return output;
    }

    // ---------- routing ----------

    /** Cached per transaction: a bulk caller resolves a route for every record. */
    @TestVisible private static List<Escalation_Route__mdt> cachedRoutes;

    private static List<Escalation_Route__mdt> routes() {
        if (cachedRoutes == null) {
            cachedRoutes = [
                SELECT DeveloperName, Route_Key__c, Channel__c, Recipient__c, Source_Type__c, Severity__c, Active__c,
                    Named_Credential__c, Endpoint_Path__c, Target__c
                FROM Escalation_Route__mdt WHERE Active__c = true ORDER BY DeveloperName LIMIT 200
            ];
        }
        return cachedRoutes;
    }

    private static Escalation_Route__mdt findRoute(String routeKey, String sourceType, String severity) {
        List<Escalation_Route__mdt> available = routes();
        if (available.isEmpty()) throw new AEIR_Exception('No active Escalation_Route__mdt records are configured.');
        if (!String.isBlank(routeKey)) {
            for (Escalation_Route__mdt route : available) {
                if (route.Route_Key__c == routeKey) return route;
            }
            throw new AEIR_Exception('The requested escalation route is not active: ' + routeKey);
        }
        Escalation_Route__mdt best;
        Integer bestScore = -1;
        for (Escalation_Route__mdt route : available) {
            Integer score = 0;
            if (String.isBlank(route.Source_Type__c)) score += 1;
            else if (route.Source_Type__c == sourceType) score += 4;
            else continue;
            if (String.isBlank(route.Severity__c)) score += 1;
            else if (route.Severity__c == severity) score += 4;
            else continue;
            if (score > bestScore) { best = route; bestScore = score; }
        }
        return best == null ? available[0] : best;
    }

    /** Trusted metadata-only lookup used again when an asynchronous connector runs. */
    public static Map<String, Escalation_Route__mdt> connectorRoutes(Set<String> keys) {
        Map<String, Escalation_Route__mdt> selected = new Map<String, Escalation_Route__mdt>();
        Set<String> ambiguous = new Set<String>();
        for (Escalation_Route__mdt route : routes()) {
            if (keys == null || !keys.contains(route.Route_Key__c)) continue;
            if (selected.containsKey(route.Route_Key__c)) ambiguous.add(route.Route_Key__c);
            selected.put(route.Route_Key__c, route);
        }
        for (String key : ambiguous) selected.remove(key);
        return selected;
    }

    private static String recipientFor(Escalation_Route__mdt route, String role) {
        String channel = safeChannel(route.Channel__c);
        if (channel == 'Email') return effectiveRecipient(role, route.Recipient__c);
        // Connector destinations come exclusively from validated Named Credential metadata.
        return channel == 'Case' || channel == 'None' ? null : route.Named_Credential__c;
    }

    // ---------- package ----------

    /** @param prefetchedSnapshot supplied by the caller so no query happens per record. */
    private static String buildPackage(Error_Log__c log, Diagnostic_Session__c session, String prefetchedSnapshot) {
        Map<String, Object> diagnosticPackage = new Map<String, Object>();
        diagnosticPackage.put('generatedAt', Datetime.now());
        diagnosticPackage.put('organizationId', UserInfo.getOrganizationId());
        diagnosticPackage.put('generatedByUserId', UserInfo.getUserId());
        if (log != null) {
            diagnosticPackage.put('summary', log.Normalized_Message__c);
            diagnosticPackage.put('correlationId', log.Correlation_Id__c);
            diagnosticPackage.put('technicalError', log.Original_Error_Message__c);
            diagnosticPackage.put('stackTrace', log.Stack_Trace__c);
            diagnosticPackage.put('sourceType', log.Source_Type__c);
            diagnosticPackage.put('sourceName', log.Source_Name__c);
            diagnosticPackage.put('objectApiName', log.Object_API_Name__c);
            diagnosticPackage.put('recordId', log.Record_Id__c);
            diagnosticPackage.put('pageUrl', log.Page_URL__c);
            diagnosticPackage.put('userAction', log.Action_Name__c);
            diagnosticPackage.put('recordSnapshot', prefetchedSnapshot);
            diagnosticPackage.put('debugLogLink', log.Debug_Log_Link__c);
        }
        if (session != null) {
            diagnosticPackage.put('correlationId', session.Correlation_Id__c);
            diagnosticPackage.put('manualDescription', session.User_Description__c);
            diagnosticPackage.put('objectApiName', session.Object_API_Name__c);
            diagnosticPackage.put('recordId', session.Context_Record_Id__c);
            diagnosticPackage.put('pageUrl', session.Page_URL__c);
            diagnosticPackage.put('agentResponse', session.Agent_Response__c);
        }
        return AEIR_SecuritySanitizerService.mask(JSON.serializePretty(diagnosticPackage));
    }

    private static String buildCaseDescription(Developer_Escalation__c escalation, String diagnosticPackage) {
        String owner = AEIR_PolicyConfigService.resolveOwnerTeam(escalation.Severity__c);
        return 'Aegis Flow diagnostic escalation\n\n'
            + 'Correlation Id: ' + escalation.Correlation_Id__c + '\n'
            + 'Severity: ' + escalation.Severity__c + '\n'
            + 'Owner team: ' + (String.isBlank(owner) ? 'Unassigned' : owner) + '\n'
            + 'SLA due: ' + String.valueOf(escalation.SLA_Due_At__c) + '\n\n'
            + 'Summary: ' + escalation.Summary__c + '\n\n'
            + 'Diagnostic package:\n'
            + AEIR_SecuritySanitizerService.safeTruncate(diagnosticPackage, 24000);
    }

    // ---------- dispatch ----------

    /** Optional Case Origin value; set only when the admin has added it to the picklist. */
    @TestVisible
    private static final String CASE_ORIGIN = 'Aegis Flow';

    private static Boolean caseOriginIsValid;

    @TestVisible
    private static Boolean caseOriginSupported() {
        if (caseOriginIsValid == null) {
            caseOriginIsValid = false;
            for (Schema.PicklistEntry entry : Case.Origin.getDescribe().getPicklistValues()) {
                if (entry.isActive() && entry.getValue() == CASE_ORIGIN) {
                    caseOriginIsValid = true;
                    break;
                }
            }
        }
        return caseOriginIsValid;
    }

    /**
     * Batched dispatch. Channels are collected first, then flushed one operation each.
     *
     * Email and Case flush synchronously. Configured external connectors create durable
     * Pending audit claims and deliver in a separate callout-capable queueable transaction.
     */
    @TestVisible
    private static void dispatchAll(List<Developer_Escalation__c> escalations, List<String> packages, Boolean sendNow) {
        if (sendNow != true || escalations == null || escalations.isEmpty()) return;

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<Developer_Escalation__c> emailEscalations = new List<Developer_Escalation__c>();
        List<Case> cases = new List<Case>();
        List<Developer_Escalation__c> caseEscalations = new List<Developer_Escalation__c>();
        List<Delivery_Audit__c> audits = new List<Delivery_Audit__c>();
        List<Delivery_Audit__c> connectorAudits = new List<Delivery_Audit__c>();
        List<Developer_Escalation__c> toUpdate = new List<Developer_Escalation__c>();

        Boolean caseCreatable = Schema.SObjectType.Case.isCreateable();
        String orgUrl = '';
        try { orgUrl = URL.getOrgDomainUrl().toExternalForm(); } catch (Exception ignored) { orgUrl = ''; }

        for (Integer i = 0; i < escalations.size(); i++) {
            Developer_Escalation__c escalation = escalations[i];
            String diagnosticPackage = packages != null && i < packages.size() ? packages[i] : '';

            if (escalation.Channel__c == 'Email') {
                List<String> toAddresses = validAddresses(escalation.Recipient__c);
                if (toAddresses.isEmpty()) {
                    escalation.Status__c = 'Failed';
                    toUpdate.add(escalation);
                    audits.add(audit(escalation, 'Email', 'Failed',
                        'The configured escalation recipient is not a valid email address.'));
                    continue;
                }
                Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
                message.setToAddresses(toAddresses);
                message.setSubject(escalation.Subject__c);
                message.setPlainTextBody(
                    'A Salesforce diagnostic escalation was created by Aegis Flow.\n\nSummary:\n' + escalation.Summary__c
                    + '\n\nDiagnostic Package:\n' + diagnosticPackage
                    + '\n\nOpen Salesforce record: ' + orgUrl + '/' + escalation.Id);
                messages.add(message);
                emailEscalations.add(escalation);

            } else if (escalation.Channel__c == 'Case') {
                if (!caseCreatable) {
                    escalation.Status__c = 'Failed';
                    toUpdate.add(escalation);
                    audits.add(audit(escalation, 'Case', 'Failed', 'You do not have permission to create Cases.'));
                    continue;
                }
                Case ticket = new Case(
                    Subject = escalation.Subject__c,
                    Description = buildCaseDescription(escalation, diagnosticPackage),
                    Priority = escalation.Severity__c == 'Critical' ? 'High' : 'Medium',
                    Status = 'New');
                // Origin is a restricted picklist on a standard object, so "Aegis Flow"
                // only exists if the admin added it. Setting it unconditionally made every
                // Case-channel escalation fail INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST, and
                // because the insert is allOrNone=false that failure was silent.
                if (caseOriginSupported()) ticket.Origin = CASE_ORIGIN;
                cases.add(ticket);
                caseEscalations.add(escalation);

            } else if (escalation.Channel__c != 'None') {
                escalation.Status__c = 'Pending';
                toUpdate.add(escalation);
                String problem = 'Connector extensions are disabled.';
                if (AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.CONNECTOR_EXTENSIONS)) {
                    Escalation_Route__mdt route;
                    try { route = findRoute(escalation.Route_Key__c, null, null); }
                    catch (Exception missingRoute) { route = null; }
                    problem = AEIR_ConnectorDeliveryJob.routeConfigurationError(route);
                    if (problem == null && route.Channel__c != escalation.Channel__c) problem = 'The configured route channel does not match the escalation.';
                }
                Delivery_Audit__c pending = audit(escalation, escalation.Channel__c, 'Pending',
                    problem == null ? 'Ready for asynchronous connector delivery.' : problem);
                audits.add(pending);
                if (problem == null) connectorAudits.add(pending);
            }
        }

        if (!messages.isEmpty()) {
            List<Messaging.SendEmailResult> sendResults;
            try {
                sendResults = Messaging.sendEmail(messages, false);
            } catch (Exception sendFailure) {
                sendResults = null;
                for (Developer_Escalation__c escalation : emailEscalations) {
                    escalation.Status__c = 'Failed';
                    toUpdate.add(escalation);
                    audits.add(audit(escalation, 'Email', 'Failed',
                        AEIR_SecuritySanitizerService.mask(sendFailure.getMessage())));
                }
            }
            if (sendResults != null) {
                for (Integer i = 0; i < emailEscalations.size(); i++) {
                    Developer_Escalation__c escalation = emailEscalations[i];
                    Boolean ok = i < sendResults.size() && sendResults[i].isSuccess();
                    escalation.Status__c = ok ? 'Sent' : 'Failed';
                    if (ok) escalation.Sent_At__c = Datetime.now();
                    toUpdate.add(escalation);
                    String detail = ok
                        ? 'Salesforce email service accepted the message.'
                        : (i < sendResults.size() && !sendResults[i].getErrors().isEmpty()
                            ? sendResults[i].getErrors()[0].getMessage()
                            : 'Unknown email delivery error.');
                    audits.add(audit(escalation, 'Email', ok ? 'Delivered' : 'Failed', detail));
                }
            }
        }

        if (!cases.isEmpty()) {
                List<Database.SaveResult> caseResults = Database.insert(cases, false, AccessLevel.SYSTEM_MODE);
            Set<Id> createdIds = new Set<Id>();
            for (Database.SaveResult sr : caseResults) {
                if (sr.isSuccess()) createdIds.add(sr.getId());
            }
            Map<Id, Case> byId = new Map<Id, Case>([SELECT Id, CaseNumber FROM Case WHERE Id IN :createdIds]);
            for (Integer i = 0; i < caseEscalations.size(); i++) {
                Developer_Escalation__c escalation = caseEscalations[i];
                Database.SaveResult sr = i < caseResults.size() ? caseResults[i] : null;
                if (sr != null && sr.isSuccess()) {
                    Case created = byId.get(sr.getId());
                    escalation.External_Ticket_Id__c = created == null ? null : created.CaseNumber;
                    escalation.Status__c = 'Sent';
                    escalation.Sent_At__c = Datetime.now();
                    audits.add(audit(escalation, 'Case', 'Delivered',
                        'Case ' + (created == null ? '' : created.CaseNumber) + ' created.'));
                } else {
                    escalation.Status__c = 'Failed';
                    audits.add(audit(escalation, 'Case', 'Failed',
                        sr == null || sr.getErrors().isEmpty()
                            ? 'Case creation failed.' : sr.getErrors()[0].getMessage()));
                }
                toUpdate.add(escalation);
            }
        }

        // allOrNone=false keeps one bad row from failing the batch, but it also means a
        // rejected row disappears without a word. Report what was lost: an audit that never
        // landed is worse than no audit at all, because the console shows a clean history.
        if (!toUpdate.isEmpty()) reportPartialFailures(Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE), 'escalation status update');
        if (!audits.isEmpty()) reportPartialFailures(Database.insert(audits, false, AccessLevel.SYSTEM_MODE), 'delivery audit insert');
        List<Delivery_Audit__c> persistedConnectorAudits = new List<Delivery_Audit__c>();
        for (Delivery_Audit__c pending : connectorAudits) if (pending.Id != null) persistedConnectorAudits.add(pending);
        if (!persistedConnectorAudits.isEmpty()) {
            try { AEIR_ConnectorDeliveryJob.enqueueAudits(persistedConnectorAudits); }
            catch (Exception queueFailure) {
                for (Delivery_Audit__c pending : persistedConnectorAudits) pending.Response_Body__c =
                    'Not queued: connector work requires an explicit retry after queue/configuration recovery.';
                reportPartialFailures(Database.update(persistedConnectorAudits, false, AccessLevel.SYSTEM_MODE), 'connector queue failure audit');
                System.debug(LoggingLevel.WARN, 'Aegis Flow: connector work was not queued; Pending audits remain available.');
            }
        }
    }

    // ---------- helpers ----------

    @TestVisible
    private static List<String> validAddresses(String recipients) {
        List<String> out = new List<String>();
        if (String.isBlank(recipients)) return out;
        for (String candidate : recipients.split(',')) {
            String trimmed = candidate.trim();
            if (Pattern.matches('^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$', trimmed)) out.add(trimmed);
        }
        return out;
    }

    /**
     * Delivery_Audit__c.Channel__c is a restricted picklist and does not use the same value
     * set as Developer_Escalation__c.Channel__c - the Case value is spelled "Salesforce Case"
     * there. Writing the escalation's spelling straight through failed the restricted
     * picklist, and because audits are inserted with allOrNone=false that failure was
     * invisible: the Case and connector escalations left no delivery trace at all, which is
     * the exact opposite of what an audit is for. Anything unrecognised lands on Other so an
     * audit row always exists.
     */
    private static Set<String> auditChannels;

    @TestVisible
    private static String auditChannel(String channel) {
        if (auditChannels == null) {
            auditChannels = new Set<String>();
            for (Schema.PicklistEntry entry : Delivery_Audit__c.Channel__c.getDescribe().getPicklistValues()) {
                if (entry.isActive()) auditChannels.add(entry.getValue());
            }
        }
        if (String.isBlank(channel)) return 'Other';
        if (auditChannels.contains(channel)) return channel;
        if (channel == 'Case' && auditChannels.contains('Salesforce Case')) return 'Salesforce Case';
        return 'Other';
    }

    @TestVisible
    private static Integer reportPartialFailures(List<Database.SaveResult> results, String operation) {
        Integer failed = 0;
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) continue;
            failed++;
            System.debug(LoggingLevel.WARN, 'Aegis Flow: ' + operation + ' rejected a row: '
                + (result.getErrors().isEmpty() ? 'unknown error' : result.getErrors()[0].getMessage()));
        }
        return failed;
    }

    private static Delivery_Audit__c audit(Developer_Escalation__c escalation, String channel, String status, String detail) {
        return new Delivery_Audit__c(
            Developer_Escalation__c = escalation.Id,
            Correlation_Id__c = escalation.Correlation_Id__c,
            Channel__c = auditChannel(channel),
            Endpoint__c = AEIR_SecuritySanitizerService.safeTruncate(escalation.Recipient__c, 255),
            Payload_Summary__c = AEIR_SecuritySanitizerService.safeTruncate(escalation.Subject__c, 32000),
            Status__c = status,
            Attempt_Count__c = 1,
            Response_Body__c = AEIR_SecuritySanitizerService.safeTruncate(detail, 32000));
    }

    private static EscalationResult result(Developer_Escalation__c escalation) {
        EscalationResult value = new EscalationResult();
        value.escalationId = escalation.Id;
        value.errorLogId = escalation.Error_Log__c;
        value.diagnosticSessionId = escalation.Diagnostic_Session__c;
        value.status = escalation.Status__c;
        value.subject = escalation.Subject__c;
        value.recipient = escalation.Recipient__c;
        value.channel = escalation.Channel__c;
        return value;
    }

    @TestVisible
    private static String safeChannel(String channel) {
        return new Set<String>{ 'Email', 'Case', 'Jira', 'Slack', 'Teams', 'GitHub Issue', 'Webhook', 'None' }
            .contains(channel) ? channel : 'Email';
    }

    /** Evidence manifest for the package (spec 12, Debug Evidence). */
    @TestVisible
    private static List<Error_Attachment__c> evidenceFor(Id errorLogId) {
        return AEIR_FeedbackService.evidenceFor(errorLogId);
    }

    /**
     * Onboarding configuration wins over the packaged placeholder, and a fresh install
     * still reaches a real person via the system administrator fallback (AF-15).
     */
    private static String effectiveRecipient(String routeType, String routeRecipient) {
        AEIR_OrgSetupService.RecipientResolution resolved =
            AEIR_OrgSetupService.resolveRecipients(routeType, routeRecipient);
        return resolved.recipients.isEmpty() ? routeRecipient : String.join(resolved.recipients, ',');
    }
}
