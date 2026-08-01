@IsTest
private class AEIR_RetentionSchedulerTest {
    @IsTest
    static void errorLogPolicyPurgesRawEvidenceAndPreservesConfiguredAttachmentManifest() {
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.sourceType = 'Apex Class';
        input.sourceName = 'Retention Scheduler Test';
        input.originalMessage = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: old evidence';
        input.contextJson = '{"token":"retention-test"}';
        AEIR_ErrorCaptureService.CaptureResult capture = AEIR_ErrorCaptureService.capture(input);

        AEIR_AgentforceGatewayService.DiagnosisResult diagnosis = AEIR_AgentforceGatewayService.diagnoseError(capture.errorLogId);
        AEIR_EscalationService.EscalationResult escalation =
            AEIR_EscalationService.createForError(capture.errorLogId, 'DEFAULT_DEV_EMAIL', false);
        AEIR_FeedbackService.FeedbackInput feedback = new AEIR_FeedbackService.FeedbackInput();
        feedback.errorLogId = capture.errorLogId;
        feedback.comments = 'This is sensitive feedback.';
        AEIR_FeedbackService.submitFeedback(feedback);
        Id attachmentId = AEIR_FeedbackService.attachEvidence(
            capture.errorLogId, '069000000000001', 'diagnostic.log', 'Debug Log', true
        );

        Test.setCreatedDate(capture.errorLogId, Datetime.now().addDays(-366));
        Test.startTest();
        AEIR_RetentionScheduler.purge();
        Test.stopTest();

        System.assertEquals(0, [SELECT count() FROM Error_Log__c WHERE Id = :capture.errorLogId]);
        System.assertEquals(0, [SELECT count() FROM Error_Context__c WHERE Error_Log__c = :capture.errorLogId]);
        System.assertEquals(0, [SELECT count() FROM AI_Diagnosis__c WHERE Id = :diagnosis.diagnosisId]);

        Developer_Escalation__c retainedEscalation = [
            SELECT Diagnostic_Package_JSON__c, Summary__c FROM Developer_Escalation__c WHERE Id = :escalation.escalationId
        ];
        System.assertEquals(null, retainedEscalation.Diagnostic_Package_JSON__c);
        System.assert(retainedEscalation.Summary__c.contains('technical evidence deleted'));

        Error_Feedback__c retainedFeedback = [SELECT Comments__c FROM Error_Feedback__c LIMIT 1];
        System.assertEquals(null, retainedFeedback.Comments__c);
        Error_Attachment__c retainedAttachment = [SELECT Error_Log__c FROM Error_Attachment__c WHERE Id = :attachmentId];
        System.assertEquals(null, retainedAttachment.Error_Log__c,
            'The packaged policy retains attachment manifests when Delete_Attachments__c is false.');
    }

    @IsTest
    static void diagnosticSessionPolicyPurgesSessionAndAssociatedDiagnosis() {
        AEIR_DiagnosticSessionService.SessionInput input = new AEIR_DiagnosticSessionService.SessionInput();
        input.objectApiName = 'Account';
        input.pageUrl = '/lightning/o/Account/list';
        input.userDescription = 'Sensitive manual diagnostic details.';
        input.detectedIssueType = 'Navigation Help';
        AEIR_DiagnosticSessionService.SessionResult session = AEIR_DiagnosticSessionService.createSession(input);
        AEIR_AgentforceGatewayService.DiagnosisResult diagnosis = AEIR_AgentforceGatewayService.diagnoseSession(session.sessionId);
        AEIR_EscalationService.EscalationResult escalation =
            AEIR_EscalationService.createForSession(session.sessionId, 'DEFAULT_DEV_EMAIL', false);

        Test.setCreatedDate(session.sessionId, Datetime.now().addDays(-181));
        Test.startTest();
        AEIR_RetentionScheduler.purge();
        Test.stopTest();

        System.assertEquals(0, [SELECT count() FROM Diagnostic_Session__c WHERE Id = :session.sessionId]);
        System.assertEquals(0, [SELECT count() FROM AI_Diagnosis__c WHERE Id = :diagnosis.diagnosisId]);
        Developer_Escalation__c retainedEscalation = [
            SELECT Diagnostic_Package_JSON__c, Summary__c FROM Developer_Escalation__c WHERE Id = :escalation.escalationId
        ];
        System.assertEquals(null, retainedEscalation.Diagnostic_Package_JSON__c);
        System.assert(retainedEscalation.Summary__c.contains('technical evidence deleted'));
    }

    @IsTest
    static void attachmentPolicyCanRemoveAttachmentManifestsWithoutDeletingFiles() {
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.sourceType = 'Apex Class';
        input.sourceName = 'Attachment Retention Test';
        input.originalMessage = 'old evidence';
        Id errorLogId = AEIR_ErrorCaptureService.capture(input).errorLogId;
        Id attachmentId = AEIR_FeedbackService.attachEvidence(
            errorLogId, '069000000000002', 'diagnostic.log', 'Debug Log', true
        );

        Test.startTest();
        AEIR_RetentionScheduler.purgeErrorLogs(new Set<Id>{ errorLogId }, true);
        Test.stopTest();

        System.assertEquals(0, [SELECT count() FROM Error_Attachment__c WHERE Id = :attachmentId]);
        System.assertEquals(0, [SELECT count() FROM Error_Log__c WHERE Id = :errorLogId]);
    }
}
