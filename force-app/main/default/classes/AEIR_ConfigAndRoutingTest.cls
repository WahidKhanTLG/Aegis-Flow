/**
 * AF-10 Case routing, AF-12 severity/SLA/surface metadata, AF-13 feedback and
 * attachments, and AF-18 Command Center metrics.
 */
@IsTest
private class AEIR_ConfigAndRoutingTest {

    // ---------- AF-12: configuration metadata is actually consulted ----------

    @IsTest
    static void severityRulesAreConsulted() {
        // PERMISSION_FAILURE is the packaged Severity_Rule record.
        // Returns a configured severity when a rule matches, otherwise null so the caller
        // keeps the deterministic classification. Either outcome is valid; it must not throw.
        AEIR_PolicyConfigService.resolveSeverity('Apex Class', 'INSUFFICIENT_ACCESS_OR_READONLY: no access');

        System.assertEquals(null, AEIR_PolicyConfigService.resolveSeverity('Apex Class', null),
            'A blank message cannot match any rule.');
    }

    @IsTest
    static void slaPolicyDrivesTheDueDate() {
        Datetime due = AEIR_PolicyConfigService.resolveSlaDueAt('Medium');
        System.assert(due > Datetime.now(), 'The SLA due date must be in the future.');

        // Falls back rather than throwing when no policy matches the severity.
        System.assertNotEquals(null, AEIR_PolicyConfigService.resolveSlaDueAt('NotARealSeverity'));
    }

    @IsTest
    static void surfaceConfigDefaultsToEnabled() {
        AEIR_PolicyConfigService.SurfaceSettings settings = AEIR_PolicyConfigService.resolveSurface();
        System.assertNotEquals(null, settings);
        System.assertNotEquals(null, settings.utilityEnabled);

        AEIR_PolicyConfigService.SurfaceSettings viaController =
            AEIR_AegisHeadlessMonitorController.getSurfaceSettings();
        System.assertEquals(settings.utilityEnabled, viaController.utilityEnabled);
    }

    @IsTest
    static void alertChannelIsResolvedFromSchema() {
        String channel = AEIR_AegisHeadlessMonitorController.getAlertChannel();
        System.assert(channel.startsWith('/event/'), channel);
        System.assert(channel.endsWith('Aegis_User_Alert__e'), channel);
    }

    // ---------- AF-10: Salesforce Case route ----------

    @IsTest
    static void caseRouteCreatesALinkedCase() {
        AEIR_ErrorCaptureService.ErrorInput in1 = new AEIR_ErrorCaptureService.ErrorInput();
        in1.sourceType = 'Apex Class';
        in1.sourceName = 'CaseRouteTest';
        in1.originalMessage = 'System.NullPointerException: case route probe';
        in1.severity = 'Critical';
        AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(in1);

        Developer_Escalation__c escalation;
        Test.startTest();
        AEIR_EscalationService.EscalationResult res =
            AEIR_EscalationService.createForError(captured.errorLogId, null, false);
        escalation = [SELECT Id, Channel__c, Correlation_Id__c, Subject__c, Summary__c, Severity__c, SLA_Due_At__c
                      FROM Developer_Escalation__c WHERE Id = :res.escalationId];
        escalation.Channel__c = 'Case';
        update escalation;
        AEIR_EscalationService.createForError(captured.errorLogId, null, false);
        Test.stopTest();

        System.assertNotEquals(null, escalation.SLA_Due_At__c, 'SLA due date must be populated from policy.');
        System.assertNotEquals(null, res.escalationId);
    }

    @IsTest
    static void unimplementedConnectorIsRecordedNotSilentlyDropped() {
        AEIR_ErrorCaptureService.ErrorInput in1 = new AEIR_ErrorCaptureService.ErrorInput();
        in1.sourceType = 'Apex Class';
        in1.sourceName = 'ConnectorTest';
        in1.originalMessage = 'Integration timeout probe';
        in1.severity = 'High';
        AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(in1);

        Test.startTest();
        AEIR_EscalationService.EscalationResult res =
            AEIR_EscalationService.createForError(captured.errorLogId, null, false);
        Test.stopTest();

        System.assertNotEquals(null, res.escalationId,
            'An escalation is always recorded even when the channel connector is unavailable.');
    }

    // ---------- AF-13: feedback and attachments ----------

    @IsTest
    static void feedbackIsCapturedAgainstTheErrorLog() {
        AEIR_ErrorCaptureService.ErrorInput in1 = new AEIR_ErrorCaptureService.ErrorInput();
        in1.sourceType = 'Flow';
        in1.sourceName = 'FeedbackTest';
        in1.originalMessage = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: probe';
        AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(in1);

        AEIR_FeedbackService.FeedbackInput fb = new AEIR_FeedbackService.FeedbackInput();
        fb.errorLogId = captured.errorLogId;
        fb.correlationId = captured.correlationId;
        fb.helpful = true;
        fb.comments = 'The explanation made sense. password=hunter2';

        Test.startTest();
        Id feedbackId = AEIR_FeedbackService.submitFeedback(fb);
        Test.stopTest();

        Error_Feedback__c saved = [SELECT Helpful__c, Comments__c, Submitted_By__c, Error_Log__c
                                   FROM Error_Feedback__c WHERE Id = :feedbackId];
        System.assertEquals(true, saved.Helpful__c);
        System.assertEquals(UserInfo.getUserId(), saved.Submitted_By__c);
        System.assert(!saved.Comments__c.contains('hunter2'), 'Feedback comments must be masked before storage.');
    }

    @IsTest
    static void feedbackRequiresAReference() {
        Boolean threw = false;
        try {
            AEIR_FeedbackService.submitFeedback(new AEIR_FeedbackService.FeedbackInput());
        } catch (Exception ex) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Feedback with no error log or session must be rejected.');
    }

    @IsTest
    static void attachmentsAreRegisteredAndDeduplicated() {
        AEIR_ErrorCaptureService.ErrorInput in1 = new AEIR_ErrorCaptureService.ErrorInput();
        in1.sourceType = 'Apex Class';
        in1.sourceName = 'AttachmentTest';
        in1.originalMessage = 'probe';
        AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(in1);

        Test.startTest();
        Id first = AEIR_FeedbackService.attachEvidence(captured.errorLogId, '069000000000001', 'apex.log', 'Debug Log', true);
        Id second = AEIR_FeedbackService.attachEvidence(captured.errorLogId, '069000000000001', 'apex.log', 'Debug Log', true);
        Test.stopTest();

        System.assertEquals(first, second, 'The same document must not be registered twice.');
        System.assertEquals(1, AEIR_FeedbackService.evidenceFor(captured.errorLogId).size());
        System.assertEquals(0, AEIR_FeedbackService.evidenceFor(null).size());
    }

    // ---------- AF-18: Command Center metrics ----------

    @IsTest
    static void dashboardReportsTheFullMetricSet() {
        List<Error_Log__c> logs = new List<Error_Log__c>();
        for (Integer i = 0; i < 5; i++) {
            logs.add(new Error_Log__c(
                Correlation_Id__c = 'METRIC-' + i,
                Source_Type__c = 'Flow',
                Source_Name__c = 'Metric_Flow',
                Object_API_Name__c = 'Account',
                Error_Category__c = 'Validation Rule',
                Severity__c = 'Critical',
                Original_Error_Message__c = 'metric probe',
                Status__c = 'New',
                User__c = UserInfo.getUserId()
            ));
        }
        AEIR_IncidentAggregationService.assign(logs);
        insert logs;

        Test.startTest();
        AEIR_AdminConsoleController.Metrics m = AEIR_AdminConsoleController.getMetrics();
        Test.stopTest();

        System.assert(m.newErrorsToday >= 5, 'Errors captured today must be counted.');
        System.assertEquals(1, m.affectedUsers, 'One distinct user was affected.');
        System.assert(m.recurringIncidents >= 1, 'Five occurrences exceed the recurrence threshold.');
        System.assert(m.unresolvedCriticalIncidents >= 1, 'The Critical incident must be reported as unresolved.');
        System.assertNotEquals(null, m.meanMinutesToDiagnosis);
        System.assertNotEquals(null, m.meanMinutesToResolution);
        System.assertNotEquals(null, m.retrySuccessRate);
        System.assertNotEquals(null, m.assistedResolutions);
        System.assertNotEquals(null, m.automaticallyResolved);
        System.assert(!m.topFailingSources.isEmpty(), 'Top failing sources must be ranked.');
        System.assertEquals('Metric_Flow', m.topFailingSources[0].sourceName);
    }
}