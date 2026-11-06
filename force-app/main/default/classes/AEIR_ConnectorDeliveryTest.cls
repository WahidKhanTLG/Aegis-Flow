@IsTest
private class AEIR_ConnectorDeliveryTest {
    @TestSetup
    static void permissions() {
        AEIR_CaptureRetryBulkTest.createAuthorizedRetryUser('Connector');
        User consumer = new User(Alias = 'aecuser', Email = 'connector-consumer@example.invalid',
            Username = 'aegis-connector-consumer-' + Datetime.now().getTime() + '@example.invalid',
            LastName = 'AegisConnectorConsumer', ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
        insert consumer;
        insert new PermissionSetAssignment(AssigneeId = consumer.Id,
            PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'AEIR_End_User' LIMIT 1].Id);
        Group readers = new Group(Name = 'Aegis Connector Consumer Readers', DeveloperName = 'AEIR_Connector_Consumer_Readers', Type = 'Regular');
        insert readers;
        insert new GroupMember(GroupId = readers.Id, UserOrGroupId = consumer.Id);

        insert new User(Alias = 'aecdeny', Email = 'connector-denied@example.invalid',
            Username = 'aegis-connector-denied-' + Datetime.now().getTime() + '@example.invalid',
            LastName = 'AegisConnectorUnprivileged', ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
    }
    private static User authorizedUser() {
        return [SELECT Id FROM User WHERE LastName = 'AegisRetryAuthorizedConnector' LIMIT 1];
    }
    private static Escalation_Route__mdt route(String channel) {
        Escalation_Route__mdt route = new Escalation_Route__mdt(DeveloperName = 'TEST_CONNECTOR',
            Route_Key__c = 'TEST_CONNECTOR', Channel__c = channel, Active__c = true,
            Named_Credential__c = channel == 'Slack' ? 'Slack_Alerts' : 'Aegis_Connector');
        if (channel == 'Slack') route.Target__c = '{"channelId":"C1234567890"}';
        if (channel == 'GitHub Issue') route.Target__c = '{"owner":"example-org","repo":"salesforce-errors"}';
        if (channel == 'Jira') route.Target__c = '{"projectKey":"OPS","issueTypeId":"10001"}';
        if (channel == 'Teams') route.Target__c = '{"teamId":"00000000-0000-0000-0000-000000000001","channelId":"19:example@thread.tacv2"}';
        return route;
    }
    private static List<Delivery_Audit__c> seed(String channel, Integer size) {
        List<Developer_Escalation__c> escalations = new List<Developer_Escalation__c>();
        for (Integer i = 0; i < size; i++) escalations.add(new Developer_Escalation__c(
            Correlation_Id__c = 'CONNECTOR-' + i, Route_Key__c = 'TEST_CONNECTOR', Channel__c = channel,
            Subject__c = '[Aegis Flow] Connector regression', Summary__c = 'A supported Salesforce process failed.',
            Diagnostic_Package_JSON__c = '{"password":"SYNTHETIC_VALUE_NOT_TO_SEND","process":"service"}',
            Severity__c = 'Medium', Status__c = 'Pending'));
        insert escalations;
        List<Delivery_Audit__c> audits = new List<Delivery_Audit__c>();
        for (Developer_Escalation__c escalation : escalations) audits.add(new Delivery_Audit__c(
            Developer_Escalation__c = escalation.Id, Correlation_Id__c = escalation.Correlation_Id__c,
            Channel__c = channel, Status__c = 'Pending', Attempt_Count__c = 1));
        insert audits;
        return audits;
    }
    private static List<Id> ids(List<Delivery_Audit__c> audits) {
        List<Id> result = new List<Id>();
        for (Delivery_Audit__c audit : audits) result.add(audit.Id);
        return result;
    }
    private static AEIR_ConnectorDeliveryJob job(List<Delivery_Audit__c> audits, String channel) {
        AEIR_ConnectorDeliveryJob job = new AEIR_ConnectorDeliveryJob(ids(audits));
        job.enabledOverride = true;
        job.routeOverrides = new List<Escalation_Route__mdt>{ route(channel) };
        return job;
    }
    private class NoOpJob implements Queueable {
        public void execute(QueueableContext context) {}
    }
    private static void claim(List<Delivery_Audit__c> audits, Id jobId) {
        List<Delivery_Audit__c> updates = new List<Delivery_Audit__c>();
        for (Delivery_Audit__c audit : audits) updates.add(new Delivery_Audit__c(Id = audit.Id,
            Response_Body__c = JSON.serialize(new Map<String, Object>{ 'state' => 'Queued', 'jobId' => jobId })));
        Database.update(updates, true, AccessLevel.SYSTEM_MODE);
    }
    private static Id enqueue(AEIR_ConnectorDeliveryJob worker, List<Delivery_Audit__c> audits) {
        Id jobId = System.enqueueJob(worker);
        claim(audits, jobId);
        return jobId;
    }
    private class BoundedBatchProbe implements Queueable, Database.AllowsCallouts {
        private List<Id> auditIds;
        BoundedBatchProbe(List<Id> auditIds) { this.auditIds = auditIds; }
        public void execute(QueueableContext context) {
            AEIR_ConnectorDeliveryJob worker = new AEIR_ConnectorDeliveryJob(auditIds);
            worker.enabledOverride = true;
            worker.routeOverrides = new List<Escalation_Route__mdt>{ route('Webhook') };
            worker.execute(context);
            System.assertEquals(10, [SELECT count() FROM Delivery_Audit__c WHERE Id IN :auditIds AND Status__c = 'Delivered'],
                'One fresh queueable transaction must perform exactly ten deliveries.');
            System.assertEquals(1, [SELECT count() FROM Delivery_Audit__c WHERE Id IN :auditIds AND Status__c = 'Pending'],
                'The remainder must be durably pending for continuation or explicit recovery.');
        }
    }
    private class ProviderMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('POST', request.getMethod());
            System.assert(request.getEndpoint().startsWith('callout:'), 'Only Named Credential callouts are allowed.');
            System.assert(request.getHeader('Idempotency-Key').startsWith('aegis-escalation-'));
            System.assert(!request.getBody().contains('SYNTHETIC_VALUE_NOT_TO_SEND'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"accepted":true}');
            if (request.getEndpoint().contains('/rest/api/3/issue')) { response.setStatusCode(201); response.setBody('{"key":"OPS-123"}'); }
            if (request.getEndpoint().contains('/repos/')) { response.setStatusCode(201); response.setBody('{"number":42}'); }
            if (request.getEndpoint().contains('/v1.0/teams/')) { response.setStatusCode(201); response.setBody('{"id":"174001"}'); }
            if (request.getEndpoint() == 'callout:Slack_Alerts/api/chat.postMessage') response.setBody('{"ok":true,"ts":"174001.000100"}');
            return response;
        }
    }
    private class RateLimitMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(429);
            response.setHeader('Retry-After', '120');
            response.setBody('{"token":"REMOTE_SECRET_MUST_NOT_BE_STORED"}');
            return response;
        }
    }
    private class TimeoutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            throw new CalloutException('Synthetic timeout at https://example.invalid/SECRET_ENDPOINT');
        }
    }
    private class GatewayFailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(503);
            response.setBody('No result can be confirmed at the gateway.');
            return response;
        }
    }
    private class IncompleteSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(201);
            response.setBody('{"accepted":true}');
            return response;
        }
    }
    private class NeverCallMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assert(false, 'An unconfigured or disabled connector must not call out.');
            return new HttpResponse();
        }
    }

    @IsTest
    static void providerAdaptersUseTheirDocumentedPayloads() {
        List<Delivery_Audit__c> audits = seed('Webhook', 1);
        Developer_Escalation__c escalation = [SELECT Id, Subject__c, Summary__c, Correlation_Id__c,
            Severity__c, Diagnostic_Package_JSON__c FROM Developer_Escalation__c LIMIT 1];
        HttpRequest webhook = AEIR_ConnectorDeliveryJob.requestFor(escalation, route('Webhook'));
        Map<String, Object> webhookBody = (Map<String, Object>)JSON.deserializeUntyped(webhook.getBody());
        System.assertEquals('1.0', webhookBody.get('schemaVersion'));
        System.assertEquals(String.valueOf(escalation.Id), webhookBody.get('escalationId'));
        System.assert(!webhook.getBody().contains('SYNTHETIC_VALUE_NOT_TO_SEND'));
        HttpRequest slack = AEIR_ConnectorDeliveryJob.requestFor(escalation, route('Slack'));
        System.assert(((Map<String, Object>)JSON.deserializeUntyped(slack.getBody())).containsKey('text'));
        HttpRequest jira = AEIR_ConnectorDeliveryJob.requestFor(escalation, route('Jira'));
        Map<String, Object> jiraFields = (Map<String, Object>)((Map<String, Object>)JSON.deserializeUntyped(jira.getBody())).get('fields');
        System.assertEquals('doc', ((Map<String, Object>)jiraFields.get('description')).get('type'), 'Jira v3 requires ADF descriptions.');
        System.assertEquals('callout:Aegis_Connector/rest/api/3/issue', jira.getEndpoint());
        HttpRequest github = AEIR_ConnectorDeliveryJob.requestFor(escalation, route('GitHub Issue'));
        System.assertEquals('callout:Aegis_Connector/repos/example-org/salesforce-errors/issues', github.getEndpoint());
        System.assert(((Map<String, Object>)JSON.deserializeUntyped(github.getBody())).containsKey('title'));
        HttpRequest teams = AEIR_ConnectorDeliveryJob.requestFor(escalation, route('Teams'));
        System.assert(teams.getEndpoint().contains('/v1.0/teams/'));
        System.assertEquals('text', ((Map<String, Object>)((Map<String, Object>)JSON.deserializeUntyped(teams.getBody())).get('body')).get('contentType'));
    }

    @IsTest
    static void queuedWebhookDeliversAndPersistsAuditOutcome() {
        List<Delivery_Audit__c> audits = seed('Webhook', 1);
        Test.setMock(HttpCalloutMock.class, new ProviderMock());
        Test.startTest();
        enqueue(job(audits, 'Webhook'), audits);
        Test.stopTest();
        Delivery_Audit__c audit = [SELECT Status__c, Response_Body__c FROM Delivery_Audit__c WHERE Id = :audits[0].Id];
        System.assertEquals('Delivered', audit.Status__c);
        System.assert(audit.Response_Body__c.contains('"httpStatus":200'));
        Developer_Escalation__c escalation = [SELECT Status__c, Sent_At__c FROM Developer_Escalation__c LIMIT 1];
        System.assertEquals('Sent', escalation.Status__c);
        System.assertNotEquals(null, escalation.Sent_At__c);
    }

    @IsTest
    static void jiraSuccessStoresTheReturnedIssueKey() {
        List<Delivery_Audit__c> audits = seed('Jira', 1);
        Test.setMock(HttpCalloutMock.class, new ProviderMock());
        Test.startTest();
        enqueue(job(audits, 'Jira'), audits);
        Test.stopTest();
        Developer_Escalation__c escalation = [SELECT Status__c, External_Ticket_Id__c FROM Developer_Escalation__c LIMIT 1];
        System.assertEquals('Sent', escalation.Status__c);
        System.assertEquals('OPS-123', escalation.External_Ticket_Id__c);
    }

    @IsTest
    static void rateLimitIsRecordedWithoutAutomaticRetryOrResponseSecret() {
        List<Delivery_Audit__c> audits = seed('Webhook', 1);
        Test.setMock(HttpCalloutMock.class, new RateLimitMock());
        Test.startTest();
        enqueue(job(audits, 'Webhook'), audits);
        Test.stopTest();
        Delivery_Audit__c audit = [SELECT Status__c, Response_Body__c FROM Delivery_Audit__c LIMIT 1];
        System.assertEquals('Failed', audit.Status__c);
        Map<String, Object> metadata = (Map<String, Object>)JSON.deserializeUntyped(audit.Response_Body__c);
        System.assertEquals(429, (Decimal)metadata.get('httpStatus'));
        System.assertEquals(120, (Decimal)metadata.get('retryAfterSeconds'));
        System.assert(!audit.Response_Body__c.contains('REMOTE_SECRET_MUST_NOT_BE_STORED'));
        System.assertEquals('Pending', [SELECT Status__c FROM Developer_Escalation__c LIMIT 1].Status__c);
        System.assertEquals(1, [SELECT count() FROM Delivery_Audit__c]);
    }

    @IsTest
    static void timeoutRemainsUncertainAndDoesNotPersistResolvedSecretUrls() {
        List<Delivery_Audit__c> audits = seed('Webhook', 1);
        Test.setMock(HttpCalloutMock.class, new TimeoutMock());
        Test.startTest();
        enqueue(job(audits, 'Webhook'), audits);
        Test.stopTest();
        Delivery_Audit__c audit = [SELECT Status__c, Response_Body__c FROM Delivery_Audit__c LIMIT 1];
        System.assertEquals('Failed', audit.Status__c);
        System.assert(audit.Response_Body__c.contains('Uncertain'));
        System.assert(!audit.Response_Body__c.contains('SECRET_ENDPOINT'));
    }

    @IsTest
    static void disabledAndUnconfiguredConnectorsStayPending() {
        List<Delivery_Audit__c> audits = seed('Webhook', 1);
        AEIR_ConnectorDeliveryJob job = job(audits, 'Webhook');
        job.enabledOverride = false;
        Test.setMock(HttpCalloutMock.class, new NeverCallMock());
        Test.startTest();
        enqueue(job, audits);
        Test.stopTest();
        Delivery_Audit__c audit = [SELECT Status__c, Response_Body__c FROM Delivery_Audit__c LIMIT 1];
        System.assertEquals('Pending', audit.Status__c);
        System.assert(audit.Response_Body__c.contains('disabled'));
        Escalation_Route__mdt missingCredential = route('Webhook');
        missingCredential.Named_Credential__c = null;
        System.assert(AEIR_ConnectorDeliveryJob.routeConfigurationError(missingCredential).contains('Named Credential'));
    }

    @IsTest
    static void endpointValidationRejectsUrlsTraversalAndSecretQueryParameters() {
        Escalation_Route__mdt route = route('Webhook');
        for (String unsafe : new List<String>{ 'https://example.invalid', '//example.invalid', '/../path',
            '/%2e%2e/path', '/hook?token=secret', '/foo\\bar', '/./path' }) {
            route.Endpoint_Path__c = unsafe;
            System.assertNotEquals(null, AEIR_ConnectorDeliveryJob.routeConfigurationError(route), unsafe);
        }
        route.Endpoint_Path__c = '/aegis/events';
        System.assertEquals(null, AEIR_ConnectorDeliveryJob.routeConfigurationError(route));
        route.Named_Credential__c = 'https://example.invalid';
        System.assertNotEquals(null, AEIR_ConnectorDeliveryJob.routeConfigurationError(route));
        Escalation_Route__mdt jira = route('Jira');
        jira.Target__c = '{"projectKey":"OPS"}';
        System.assertNotEquals(null, AEIR_ConnectorDeliveryJob.routeConfigurationError(jira));
    }

    @IsTest
    static void nonEmailRouteDoesNotResolveAnEmailRecipient() {
        Escalation_Route__mdt route = route('Webhook');
        route.Recipient__c = 'unused@example.invalid';
        AEIR_EscalationService.cachedRoutes = new List<Escalation_Route__mdt>{ route };
        Error_Log__c log = new Error_Log__c(Correlation_Id__c = 'CONNECTOR-ROUTING', Source_Type__c = 'API',
            Source_Name__c = 'Integration', Severity__c = 'Medium', Normalized_Message__c = 'Integration failed.',
            Status__c = 'New', User__c = UserInfo.getUserId());
        insert log;
        AEIR_EscalationService.EscalationResult result = AEIR_EscalationService.createForError(log.Id, 'TEST_CONNECTOR', false);
        System.assertEquals('Aegis_Connector', result.recipient);
        System.assertEquals('New', result.status);
        System.assertEquals(0, [SELECT count() FROM Delivery_Audit__c]);
    }

    @IsTest
    static void explicitRetriesRespectAttemptCapRetryAfterAndUncertainOutcomes() {
        Test.startTest();
        System.runAs(authorizedUser()) {
            System.assert(FeatureManagement.checkPermission('AEIR_Execute_Retry'), 'The dedicated retry fixture must have its native custom permission.');
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.CONNECTOR_EXTENSIONS, true);
            AEIR_EscalationService.cachedRoutes = new List<Escalation_Route__mdt>{ route('Webhook') };
            List<Delivery_Audit__c> audits = seed('Webhook', 3);
            audits[0].Status__c = 'Failed'; audits[0].Attempt_Count__c = 3;
            audits[1].Status__c = 'Failed'; audits[1].Response_Body__c = '{"state":"Failed","retryAfterSeconds":120}';
            audits[2].Status__c = 'Failed'; audits[2].Response_Body__c = '{"state":"Uncertain"}';
            update audits;
            List<Id> escalationIds = new List<Id>();
            for (Delivery_Audit__c audit : audits) escalationIds.add(audit.Developer_Escalation__c);
            Map<Id, String> results = AEIR_ConnectorDeliveryJob.retryEscalations(escalationIds);
            System.assert(results.get(escalationIds[0]).contains('Maximum'));
            System.assert(results.get(escalationIds[1]).contains('Retry-After'));
            System.assert(results.get(escalationIds[2]).contains('uncertain'));
            System.assertEquals(3, [SELECT count() FROM Delivery_Audit__c]);
        }
        Test.stopTest();
    }

    @IsTest
    static void explicitRetryQueuesOneNewDurableAttempt() {
        Id escalationId;
        Test.startTest();
        System.runAs(authorizedUser()) {
            System.assert(FeatureManagement.checkPermission('AEIR_Execute_Retry'), 'The dedicated retry fixture must have its native custom permission.');
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.CONNECTOR_EXTENSIONS, true);
            AEIR_EscalationService.cachedRoutes = new List<Escalation_Route__mdt>{ route('Webhook') };
            List<Delivery_Audit__c> audits = seed('Webhook', 1);
            audits[0].Status__c = 'Failed'; audits[0].Response_Body__c = '{"state":"Failed","httpStatus":400}';
            update audits;
            escalationId = audits[0].Developer_Escalation__c;
            Test.setMock(HttpCalloutMock.class, new ProviderMock());
            Map<Id, String> results = AEIR_ConnectorDeliveryJob.retryEscalations(new List<Id>{ audits[0].Developer_Escalation__c });
            System.assertEquals('Queued', results.get(audits[0].Developer_Escalation__c));
            System.assertEquals(2, [SELECT count() FROM Delivery_Audit__c]);
            // The configured test route must execute a real mocked delivery, then
            // finalize exactly the newly queued second attempt.
            System.assertEquals(2, [SELECT MAX(Attempt_Count__c) highest FROM Delivery_Audit__c][0].get('highest'));
        }
        Test.stopTest();
        List<Delivery_Audit__c> completedAttempts = [SELECT Status__c, Attempt_Count__c FROM Delivery_Audit__c
            WHERE Developer_Escalation__c = :escalationId ORDER BY Attempt_Count__c DESC];
        System.assertEquals(2, completedAttempts.size());
        System.assertEquals(2, completedAttempts[0].Attempt_Count__c);
        System.assertEquals('Delivered', completedAttempts[0].Status__c);
        System.assertEquals('Failed', completedAttempts[1].Status__c);
        Developer_Escalation__c delivered = [SELECT Status__c, Sent_At__c FROM Developer_Escalation__c WHERE Id = :escalationId];
        System.assertEquals('Sent', delivered.Status__c);
        System.assertNotEquals(null, delivered.Sent_At__c);
    }

    @IsTest
    static void queuedClaimBlocksDuplicateExplicitRetry() {
        Test.startTest();
        System.runAs(authorizedUser()) {
            System.assert(FeatureManagement.checkPermission('AEIR_Execute_Retry'), 'The dedicated retry fixture must have its native custom permission.');
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.CONNECTOR_EXTENSIONS, true);
            AEIR_EscalationService.cachedRoutes = new List<Escalation_Route__mdt>{ route('Webhook') };
            List<Delivery_Audit__c> audits = seed('Webhook', 1);
            AEIR_ConnectorDeliveryJob.enqueueAudits(audits);
            Map<Id, String> results = AEIR_ConnectorDeliveryJob.retryEscalations(new List<Id>{ audits[0].Developer_Escalation__c });
            System.assert(results.get(audits[0].Developer_Escalation__c).contains('already queued'));
            System.assertEquals(1, [SELECT count() FROM Delivery_Audit__c]);
        }
        Test.stopTest();
    }

    @IsTest
    static void unprivilegedCallerCannotRequestExternalRetries() {
        User caller = [SELECT Id FROM User WHERE LastName = 'AegisConnectorUnprivileged' LIMIT 1];
        System.runAs(caller) {
            Boolean denied = false;
            try { AEIR_ConnectorDeliveryJob.retryEscalations(new List<Id>()); }
            catch (AEIR_ConnectorDeliveryJob.ConnectorException expected) { denied = true; }
            System.assert(denied);
        }
    }
    @IsTest
    static void providerSuccessMustConfirmTheCreatedIssue() {
        List<Delivery_Audit__c> audits = seed('Jira', 1);
        Test.setMock(HttpCalloutMock.class, new IncompleteSuccessMock());
        Test.startTest();
        enqueue(job(audits, 'Jira'), audits);
        Test.stopTest();
        Delivery_Audit__c audit = [SELECT Status__c, Response_Body__c FROM Delivery_Audit__c LIMIT 1];
        System.assertEquals('Failed', audit.Status__c);
        System.assert(audit.Response_Body__c.contains('Uncertain'));
        Developer_Escalation__c escalation = [SELECT Status__c, External_Ticket_Id__c FROM Developer_Escalation__c LIMIT 1];
        System.assertEquals('Failed', escalation.Status__c);
        System.assertEquals(null, escalation.External_Ticket_Id__c);
    }

    @IsTest
    static void activeButUnconfiguredWorkerDoesNotCallOut() {
        List<Delivery_Audit__c> audits = seed('Webhook', 1);
        AEIR_ConnectorDeliveryJob worker = job(audits, 'Webhook');
        worker.routeOverrides[0].Named_Credential__c = null;
        Test.setMock(HttpCalloutMock.class, new NeverCallMock());
        Test.startTest();
        enqueue(worker, audits);
        Test.stopTest();
        Delivery_Audit__c audit = [SELECT Status__c, Response_Body__c FROM Delivery_Audit__c LIMIT 1];
        System.assertEquals('Pending', audit.Status__c);
        System.assert(audit.Response_Body__c.contains('Named Credential'));
    }

    @IsTest
    static void calloutBatchIsBoundedAndRemainingWorkHasFiniteContinuation() {
        List<Delivery_Audit__c> audits = seed('Webhook', 11);
        Test.setMock(HttpCalloutMock.class, new ProviderMock());
        Test.startTest();
        AsyncOptions options = new AsyncOptions();
        options.MaximumQueueableStackDepth = 25;
        Id probeJobId = System.enqueueJob(new BoundedBatchProbe(ids(audits)), options);
        claim(audits, probeJobId);
        Test.stopTest();
        System.assertEquals(10, [SELECT count() FROM Delivery_Audit__c WHERE Status__c = 'Delivered']);
        System.assertEquals(1, [SELECT count() FROM Delivery_Audit__c WHERE Status__c = 'Pending']);
        System.assertEquals(11, [SELECT count() FROM Delivery_Audit__c]);
        List<Id> tooMany = new List<Id>();
        // Distinct valid-looking audit IDs are unnecessary: the constructor must dedupe
        // repeated IDs, keeping a public caller from inflating a single delivery request.
        for (Integer i = 0; i < 201; i++) tooMany.add(audits[0].Id);
        System.assertNotEquals(null, new AEIR_ConnectorDeliveryJob(tooMany));
    }

    @IsTest
    static void gatewayFailureCannotBeBlindlyRetried() {
        List<Delivery_Audit__c> audits = seed('Webhook', 1);
        Test.setMock(HttpCalloutMock.class, new GatewayFailureMock());
        Test.startTest();
        enqueue(job(audits, 'Webhook'), audits);
        Test.stopTest();
        System.runAs(authorizedUser()) {
            System.assert(FeatureManagement.checkPermission('AEIR_Execute_Retry'), 'The dedicated retry fixture must have its native custom permission.');
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.CONNECTOR_EXTENSIONS, true);
            AEIR_EscalationService.cachedRoutes = new List<Escalation_Route__mdt>{ route('Webhook') };
            Delivery_Audit__c audit = [SELECT Response_Body__c FROM Delivery_Audit__c LIMIT 1];
            System.assert(audit.Response_Body__c.contains('Uncertain'));
            Map<Id, String> result = AEIR_ConnectorDeliveryJob.retryEscalations(new List<Id>{ audits[0].Developer_Escalation__c });
            System.assert(result.get(audits[0].Developer_Escalation__c).contains('uncertain'));
            System.assertEquals(1, [SELECT count() FROM Delivery_Audit__c]);
        }
    }

    @IsTest
    static void constrainedParentDefersWithoutUndoingConfirmedDeliveries() {
        List<Delivery_Audit__c> audits = seed('Webhook', 11);
        AsyncOptions options = new AsyncOptions();
        options.MaximumQueueableStackDepth = 1;
        Test.setMock(HttpCalloutMock.class, new ProviderMock());
        Test.startTest();
        Id parentJobId = System.enqueueJob(new BoundedBatchProbe(ids(audits)), options);
        claim(audits, parentJobId);
        Test.stopTest();
        System.assertEquals(10, [SELECT count() FROM Delivery_Audit__c WHERE Status__c = 'Delivered']);
        System.assertEquals(10, [SELECT count() FROM Developer_Escalation__c WHERE Status__c = 'Sent']);
        Delivery_Audit__c pending = [SELECT Response_Body__c FROM Delivery_Audit__c WHERE Status__c = 'Pending' LIMIT 1];
        System.assert(pending.Response_Body__c.contains('NotQueued'), 'Unscheduled continuation must not retain a live-queue claim.');
        System.assert(pending.Response_Body__c.contains('new transaction'));
    }

    @IsTest
    static void endUserEscalationDeliversWithoutDirectTechnicalAuditReadAccess() {
        User consumer = [SELECT Id FROM User WHERE LastName = 'AegisConnectorConsumer' LIMIT 1];
        Id escalationId;
        Test.setMock(HttpCalloutMock.class, new ProviderMock());
        Test.startTest();
        System.runAs(consumer) {
            System.assert(!Schema.SObjectType.Delivery_Audit__c.isAccessible());
            System.assert(!Schema.SObjectType.Developer_Escalation__c.isAccessible());
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.CONNECTOR_EXTENSIONS, true);
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.USER_NOTIFICATIONS, false);
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AI_DIAGNOSIS, false);
            AEIR_EscalationService.cachedRoutes = new List<Escalation_Route__mdt>{ route('Webhook') };
            AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
            input.correlationId = 'ENDUSER-CONNECTOR';
            input.sourceType = 'LWC';
            input.originalMessage = 'REQUIRED_FIELD_MISSING: Name';
            AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(input);
            escalationId = AEIR_EscalationService.createForError(captured.errorLogId, 'TEST_CONNECTOR', true).escalationId;
        }
        Test.stopTest();
        System.assertEquals('Sent', [SELECT Status__c FROM Developer_Escalation__c WHERE Id = :escalationId].Status__c);
        System.assertEquals(1, [SELECT count() FROM Delivery_Audit__c WHERE Developer_Escalation__c = :escalationId AND Status__c = 'Delivered']);
    }

    @IsTest
    static void staleJobCannotConsumeAReplacementClaim() {
        List<Delivery_Audit__c> audits = seed('Webhook', 1);
        Test.setMock(HttpCalloutMock.class, new NeverCallMock());
        Test.startTest();
        enqueue(job(audits, 'Webhook'), audits);
        Id replacementJob = System.enqueueJob(new NoOpJob());
        claim(audits, replacementJob);
        Test.stopTest();
        Delivery_Audit__c saved = [SELECT Status__c, Response_Body__c FROM Delivery_Audit__c LIMIT 1];
        System.assertEquals('Pending', saved.Status__c);
        System.assert(saved.Response_Body__c.contains(String.valueOf(replacementJob)));
    }

    @IsTest
    static void consumerCannotClaimOrDeliverAnotherCreatorsOutbox() {
        User consumer = [SELECT Id FROM User WHERE LastName = 'AegisConnectorConsumer' LIMIT 1];
        List<Delivery_Audit__c> audits = seed('Webhook', 1);
        Group readers = [SELECT Id FROM Group WHERE DeveloperName = 'AEIR_Connector_Consumer_Readers' LIMIT 1];
        insert new Delivery_Audit__Share(ParentId = audits[0].Id, UserOrGroupId = readers.Id, AccessLevel = 'Read', RowCause = 'Manual');
        insert new Developer_Escalation__Share(ParentId = audits[0].Developer_Escalation__c,
            UserOrGroupId = readers.Id, AccessLevel = 'Read', RowCause = 'Manual');
        Id consumerJobId;
        Test.setMock(HttpCalloutMock.class, new NeverCallMock());
        Test.startTest();
        System.runAs(consumer) {
            System.assert(!FeatureManagement.checkPermission('AEIR_Execute_Retry'));
            System.assert(!FeatureManagement.checkPermission('AEIR_Process_Diagnostics'));
            System.assert(!Schema.SObjectType.Delivery_Audit__c.isAccessible(), 'Record sharing must not grant direct technical audit CRUD.');
            System.assert(!Schema.SObjectType.Developer_Escalation__c.isAccessible(), 'The fixture retains its consumer object permissions.');
            Boolean denied = false;
            try { AEIR_ConnectorDeliveryJob.enqueueAudits(audits); }
            catch (AEIR_ConnectorDeliveryJob.ConnectorException expected) { denied = true; }
            System.assert(denied, 'A public factory cannot overwrite a foreign delivery claim.');
            consumerJobId = System.enqueueJob(job(audits, 'Webhook'));
        }
        // Only the legitimate creator can write the claim. The queued job still runs
        // as the consumer and must reject the mismatched audit provenance.
        claim(audits, consumerJobId);
        Test.stopTest();
        System.assertEquals('Pending', [SELECT Status__c FROM Delivery_Audit__c LIMIT 1].Status__c);
        System.assertEquals('Pending', [SELECT Status__c FROM Developer_Escalation__c LIMIT 1].Status__c);
    }

}
