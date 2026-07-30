/**
 * Bulk escalation. The single-record path cost roughly five DML and three queries each,
 * so a batch beyond about thirty records exhausted DML limits. These tests assert a
 * bounded cost, not just that the path runs.
 */
@IsTest
private class AEIR_EscalationBulkTest {

    private static List<Error_Log__c> seedLogs(Integer count, String severity) {
        Account a = new Account(Name = 'Aegis Escalation Bulk');
        insert a;
        List<Error_Log__c> logs = new List<Error_Log__c>();
        for (Integer i = 0; i < count; i++) {
            logs.add(new Error_Log__c(
                Correlation_Id__c = 'ESC-' + i + '-' + Datetime.now().getTime(),
                Source_Type__c = 'Apex Class',
                Source_Name__c = 'BulkEscalationProbe',
                Object_API_Name__c = 'Account',
                Record_Id__c = a.Id,
                Error_Category__c = 'Null Pointer',
                Severity__c = severity,
                Original_Error_Message__c = 'System.NullPointerException: probe ' + i,
                Normalized_Message__c = 'A referenced value was empty.',
                Status__c = 'New',
                User__c = UserInfo.getUserId()));
        }
        insert logs;
        return logs;
    }

    private static List<Id> idsOf(List<Error_Log__c> logs) {
        List<Id> ids = new List<Id>();
        for (Error_Log__c l : logs) ids.add(l.Id);
        return ids;
    }

    @IsTest
    static void bulkEscalationCostIsBounded() {
        List<Id> ids = idsOf(seedLogs(60, 'High'));

        Test.startTest();
        Integer q = Limits.getQueries(), d = Limits.getDmlStatements(), e = Limits.getEmailInvocations();
        List<AEIR_EscalationService.EscalationResult> results =
            AEIR_EscalationService.createForErrors(ids, null, true);
        Integer queriesUsed = Limits.getQueries() - q;
        Integer dmlUsed = Limits.getDmlStatements() - d;
        Integer emailsUsed = Limits.getEmailInvocations() - e;
        Test.stopTest();

        System.assertEquals(60, results.size(), 'Every log should produce an escalation.');
        System.assert(queriesUsed <= 12, 'Query cost must not scale with batch size, used ' + queriesUsed);
        System.assert(dmlUsed <= 12, 'DML cost must not scale with batch size, used ' + dmlUsed);
        System.assert(emailsUsed <= 1, 'All emails must go out in a single send, used ' + emailsUsed);
        System.assertEquals(60, [SELECT count() FROM Developer_Escalation__c WHERE Correlation_Id__c LIKE 'ESC-%']);
    }

    @IsTest
    static void bulkEscalationWritesAuditAndMarksLogsEscalated() {
        List<Error_Log__c> logs = seedLogs(5, 'Critical');

        Test.startTest();
        AEIR_EscalationService.createForErrors(idsOf(logs), null, true);
        Test.stopTest();

        System.assertEquals(5, [SELECT count() FROM Error_Log__c WHERE Id IN :idsOf(logs) AND Status__c = 'Escalated'],
            'Every escalated log must be marked.');
        System.assertEquals(5, [SELECT count() FROM Delivery_Audit__c WHERE Correlation_Id__c LIKE 'ESC-%'],
            'Spec 12 requires a delivery record per escalation.');
        Developer_Escalation__c esc = [SELECT Severity__c, SLA_Due_At__c, Diagnostic_Package_JSON__c, Recipient__c
                                       FROM Developer_Escalation__c WHERE Correlation_Id__c LIKE 'ESC-%' LIMIT 1];
        System.assertEquals('Critical', esc.Severity__c);
        System.assertNotEquals(null, esc.SLA_Due_At__c, 'SLA must come from policy.');
        System.assert(esc.Diagnostic_Package_JSON__c.contains('recordSnapshot'),
            'The package must carry a record snapshot (spec 12).');
    }

    @IsTest
    static void singleRecordEntryPointStillWorksAndMatchesBulk() {
        List<Error_Log__c> logs = seedLogs(1, 'Medium');

        Test.startTest();
        AEIR_EscalationService.EscalationResult single =
            AEIR_EscalationService.createForError(logs[0].Id, null, false);
        Test.stopTest();

        System.assertNotEquals(null, single, 'The single-record wrapper must still return a result.');
        System.assertNotEquals(null, single.escalationId);
        System.assertEquals('New', single.status, 'sendNow=false must leave the escalation unsent.');
    }

    @IsTest
    static void emptyAndUnknownInputAreHandled() {
        Test.startTest();
        System.assertEquals(0, AEIR_EscalationService.createForErrors(null, null, true).size());
        System.assertEquals(0, AEIR_EscalationService.createForErrors(new List<Id>(), null, true).size());
        Test.stopTest();
    }

    /**
     * Channel comes from Escalation_Route__mdt, and custom metadata cannot be inserted in a
     * test. So the channel branches are driven through dispatchAll directly - that is the
     * batching unit, and it is the part that regressed under bulk load.
     */
    private static List<Developer_Escalation__c> escalationsOn(String channel, String recipient, Integer count) {
        List<Developer_Escalation__c> escalations = new List<Developer_Escalation__c>();
        for (Integer i = 0; i < count; i++) {
            escalations.add(new Developer_Escalation__c(
                Correlation_Id__c = 'DISPATCH-' + channel + '-' + i,
                Channel__c = channel,
                Recipient__c = recipient,
                Severity__c = i == 0 ? 'Critical' : 'High',
                Subject__c = '[Aegis Flow] dispatch probe ' + i,
                Summary__c = 'A referenced value was empty.',
                Status__c = 'New',
                SLA_Due_At__c = Datetime.now().addHours(4)));
        }
        insert escalations;
        return escalations;
    }

    private static List<String> packagesFor(Integer count) {
        List<String> packages = new List<String>();
        for (Integer i = 0; i < count; i++) packages.add('{"correlationId":"DISPATCH-' + i + '"}');
        return packages;
    }

    @IsTest
    static void caseChannelCreatesCasesInOneInsertAndStampsTheTicketNumber() {
        List<Developer_Escalation__c> escalations = escalationsOn('Case', null, 25);

        Test.startTest();
        Integer d = Limits.getDmlStatements();
        AEIR_EscalationService.dispatchAll(escalations, packagesFor(25), true);
        Integer dmlUsed = Limits.getDmlStatements() - d;
        Test.stopTest();

        System.assert(dmlUsed <= 4, 'Case dispatch must batch, used ' + dmlUsed + ' DML for 25 escalations.');
        System.assertEquals(25, [SELECT count() FROM Case WHERE Subject LIKE '[Aegis Flow]%']);
        List<Developer_Escalation__c> saved =
            [SELECT Status__c, External_Ticket_Id__c, Sent_At__c FROM Developer_Escalation__c WHERE Channel__c = 'Case'];
        for (Developer_Escalation__c e : saved) {
            System.assertEquals('Sent', e.Status__c);
            System.assertNotEquals(null, e.External_Ticket_Id__c, 'The Case number must be written back.');
            System.assertNotEquals(null, e.Sent_At__c);
        }
        System.assertEquals(25, [SELECT count() FROM Delivery_Audit__c WHERE Status__c = 'Delivered'],
            'Delivery_Audit__c.Channel__c spells this "Salesforce Case", so an unmapped value '
            + 'is rejected by the restricted picklist and the audit vanishes.');
        System.assertEquals(25, [SELECT count() FROM Delivery_Audit__c WHERE Channel__c = 'Salesforce Case']);
        Case created = [SELECT Description, Priority, Origin FROM Case
                        WHERE Subject LIKE '[Aegis Flow]%' AND Priority = 'High' LIMIT 1];
        System.assertEquals(AEIR_EscalationService.caseOriginSupported() ? AEIR_EscalationService.CASE_ORIGIN : null,
            created.Origin,
            'Origin must be set only when the admin added the value, never blindly.');
        System.assert(created.Description.contains('Correlation Id:'), 'The Case body must carry the diagnostic package.');
        System.assert(created.Description.contains('SLA due:'));
    }

    @IsTest
    static void unimplementedConnectorRecordsPendingRatherThanLookingDelivered() {
        List<Developer_Escalation__c> escalations = escalationsOn('Slack', null, 3);

        Test.startTest();
        AEIR_EscalationService.dispatchAll(escalations, packagesFor(3), true);
        Test.stopTest();

        System.assertEquals(3, [SELECT count() FROM Developer_Escalation__c WHERE Status__c = 'Pending'],
            'An unbuilt connector must not report the escalation as sent.');
        List<Delivery_Audit__c> audits = [SELECT Status__c, Response_Body__c FROM Delivery_Audit__c];
        System.assertEquals(3, audits.size());
        for (Delivery_Audit__c a : audits) {
            System.assertEquals('Pending', a.Status__c);
            System.assert(a.Response_Body__c.contains('not implemented'), 'The audit must say why nothing was delivered.');
        }
    }

    @IsTest
    static void invalidRecipientIsRecordedAsFailedNotSilentlySent() {
        List<Developer_Escalation__c> escalations = escalationsOn('Email', 'not-an-email', 4);

        Test.startTest();
        Integer e = Limits.getEmailInvocations();
        AEIR_EscalationService.dispatchAll(escalations, packagesFor(4), true);
        System.assertEquals(e, Limits.getEmailInvocations(), 'No send should be attempted with no valid address.');
        Test.stopTest();

        System.assertEquals(4, [SELECT count() FROM Developer_Escalation__c WHERE Status__c = 'Failed']);
        Delivery_Audit__c audit = [SELECT Status__c, Response_Body__c FROM Delivery_Audit__c LIMIT 1];
        System.assertEquals('Failed', audit.Status__c);
        System.assert(audit.Response_Body__c.contains('not a valid email address'));
    }

    @IsTest
    static void emailChannelSendsOnceAndMarksEverythingSent() {
        List<Developer_Escalation__c> escalations = escalationsOn('Email', 'aegis.probe@example.com', 10);

        Test.startTest();
        Integer e = Limits.getEmailInvocations();
        AEIR_EscalationService.dispatchAll(escalations, packagesFor(10), true);
        System.assertEquals(1, Limits.getEmailInvocations() - e, '10 escalations must cost one send, not ten.');
        Test.stopTest();

        System.assertEquals(10, [SELECT count() FROM Developer_Escalation__c WHERE Status__c = 'Sent']);
        System.assertEquals(10, [SELECT count() FROM Delivery_Audit__c WHERE Channel__c = 'Email']);
    }

    @IsTest
    static void noneChannelAndSendNowFalseDispatchNothing() {
        List<Developer_Escalation__c> none = escalationsOn('None', null, 2);

        Test.startTest();
        AEIR_EscalationService.dispatchAll(none, packagesFor(2), true);
        AEIR_EscalationService.dispatchAll(escalationsOn('Email', 'a@b.com', 2), packagesFor(2), false);
        AEIR_EscalationService.dispatchAll(null, packagesFor(2), true);
        Test.stopTest();

        System.assertEquals(0, [SELECT count() FROM Delivery_Audit__c],
            'Channel None and sendNow=false must produce no delivery attempt at all.');
        System.assertEquals(0, [SELECT count() FROM Developer_Escalation__c WHERE Status__c != 'New']);
    }

    @IsTest
    static void unknownRouteKeyFailsLoudly() {
        List<Id> ids = idsOf(seedLogs(1, 'High'));
        String message;

        Test.startTest();
        try {
            AEIR_EscalationService.createForErrors(ids, 'NO_SUCH_ROUTE', true);
        } catch (Exception e) {
            message = e.getMessage();
        }
        Test.stopTest();

        System.assertNotEquals(null, message, 'A misconfigured route must not silently fall back to a default.');
        System.assert(message.contains('NO_SUCH_ROUTE'), 'The error must name the route: ' + message);
    }

    @IsTest
    static void manualSessionWithoutAnErrorLogStillEscalates() {
        Diagnostic_Session__c session = new Diagnostic_Session__c(
            Correlation_Id__c = 'SESS-' + Datetime.now().getTime(),
            User_Description__c = 'The Save button does nothing on this page.',
            Object_API_Name__c = 'Account',
            Page_URL__c = '/lightning/o/Account/home',
            User__c = UserInfo.getUserId(),
            Resolution_Status__c = 'Open');
        insert session;

        Test.startTest();
        AEIR_EscalationService.EscalationResult result =
            AEIR_EscalationService.createForSession(session.Id, null, true);
        Test.stopTest();

        System.assertNotEquals(null, result.escalationId, 'A manual "get help" session must escalate on its own.');
        Developer_Escalation__c esc = [SELECT Summary__c, Severity__c, Diagnostic_Package_JSON__c
                                       FROM Developer_Escalation__c WHERE Id = :result.escalationId];
        System.assertEquals('Medium', esc.Severity__c, 'A manual session has no severity signal, so it defaults.');
        System.assert(esc.Diagnostic_Package_JSON__c.contains('manualDescription'),
            'The package must carry what the user typed.');
        Diagnostic_Session__c after = [SELECT Resolution_Status__c, Needs_Escalation__c
                                       FROM Diagnostic_Session__c WHERE Id = :session.Id];
        System.assertEquals('Escalated', after.Resolution_Status__c);
        System.assertEquals(true, after.Needs_Escalation__c);
    }

    @IsTest
    static void sessionCarryingAnErrorLogUsesTheErrorPath() {
        List<Error_Log__c> logs = seedLogs(1, 'High');
        Diagnostic_Session__c session = new Diagnostic_Session__c(
            Correlation_Id__c = 'SESS-LINKED-' + Datetime.now().getTime(),
            User_Description__c = 'Order save failed.',
            Recent_Error_Log__c = logs[0].Id,
            User__c = UserInfo.getUserId(),
            Resolution_Status__c = 'Open');
        insert session;

        Test.startTest();
        AEIR_EscalationService.EscalationResult result =
            AEIR_EscalationService.createForSession(session.Id, null, false);
        Test.stopTest();

        Developer_Escalation__c esc =
            [SELECT Error_Log__c FROM Developer_Escalation__c WHERE Id = :result.escalationId];
        System.assertEquals(logs[0].Id, esc.Error_Log__c,
            'A session linked to a real error must escalate the error, not a bare description.');
    }

    @IsTest
    static void helperBehaviourIsCorrect() {
        System.assertEquals('Salesforce Case', AEIR_EscalationService.auditChannel('Case'),
            'The audit object uses a different spelling than the escalation object.');
        System.assertEquals('Email', AEIR_EscalationService.auditChannel('Email'));
        System.assertEquals('Slack', AEIR_EscalationService.auditChannel('Slack'));
        System.assertEquals('Other', AEIR_EscalationService.auditChannel('Carrier Pigeon'),
            'An unknown channel must still produce an audit row, not be dropped.');
        System.assertEquals('Other', AEIR_EscalationService.auditChannel(null));
        System.assertEquals(2, AEIR_EscalationService.validAddresses('a@b.com, c@d.com').size());
        System.assertEquals(0, AEIR_EscalationService.validAddresses('nope').size());
        System.assertEquals(0, AEIR_EscalationService.validAddresses(null).size());
        System.assertEquals('Case', AEIR_EscalationService.safeChannel('Case'));
        System.assertEquals('Email', AEIR_EscalationService.safeChannel('NotAChannel'),
            'An unknown channel must fall back to Email rather than dropping the escalation.');
        System.assertEquals(0, AEIR_EscalationService.evidenceFor(null).size());
    }
}