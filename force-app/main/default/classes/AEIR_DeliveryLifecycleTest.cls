@IsTest
private class AEIR_DeliveryLifecycleTest {
    private static Error_Log__c log(String correlation) {
        Error_Log__c row = new Error_Log__c(Correlation_Id__c = correlation, User__c = UserInfo.getUserId(),
            Source_Type__c = 'Flow', Source_Name__c = 'Delivery Fixture', Severity__c = 'Medium', Status__c = 'New');
        insert row; return row;
    }
    private static void caseRoute() {
        AEIR_EscalationService.cachedRoutes = new List<Escalation_Route__mdt>{new Escalation_Route__mdt(
            DeveloperName = 'REPLAY_CASE', Route_Key__c = 'REPLAY_CASE', Channel__c = 'Case', Active__c = true)};
    }
    private class Replay implements Queueable {
        private Id sourceId;
        Replay(Id idValue) { sourceId = idValue; }
        public void execute(QueueableContext context) {
            caseRoute();
            AEIR_EscalationService.createForError(sourceId, 'REPLAY_CASE', true);
        }
    }
    @IsTest static void replayInAnotherTransactionCannotDeliverAgain() {
        caseRoute(); Error_Log__c error = log('DELIVERY-ASYNC-REPLAY');
        Test.startTest();
        AEIR_EscalationService.createForError(error.Id, 'REPLAY_CASE', true);
        System.enqueueJob(new Replay(error.Id));
        Test.stopTest();
        System.assertEquals(1, [SELECT count() FROM Developer_Escalation__c WHERE Error_Log__c = :error.Id]);
        System.assertEquals(1, [SELECT count() FROM Case WHERE Subject LIKE '%DELIVERY-ASYNC-REPLAY%']);
    }
    @IsTest static void repeatedEscalationRequestsReuseRecordAndDeliverOnce() {
        caseRoute(); Error_Log__c error = log('DELIVERY-REPLAY');
        Test.startTest();
        AEIR_EscalationService.EscalationResult first = AEIR_EscalationService.createForError(error.Id, 'REPLAY_CASE', true);
        AEIR_EscalationService.EscalationResult replay = AEIR_EscalationService.createForError(error.Id, 'REPLAY_CASE', true);
        AEIR_EscalationRequestedEventHandler.handle(new List<Escalation_Requested__e>{new Escalation_Requested__e(
            Correlation_Id__c = error.Correlation_Id__c, Error_Log_Id__c = error.Id, Route_Key__c = 'REPLAY_CASE')});
        Test.stopTest();
        System.assertEquals(first.escalationId, replay.escalationId);
        System.assertEquals(1, [SELECT count() FROM Developer_Escalation__c WHERE Error_Log__c = :error.Id]);
        System.assertEquals(1, [SELECT count() FROM Case WHERE Subject LIKE '%DELIVERY-REPLAY%']);
        System.assertEquals(1, [SELECT count() FROM Delivery_Audit__c WHERE Developer_Escalation__c = :first.escalationId]);
    }
    @IsTest static void draftCanBeSentOnceAndSubsequentRequestsDoNotResend() {
        caseRoute(); Error_Log__c error = log('DELIVERY-DRAFT');
        AEIR_EscalationService.EscalationResult draft = AEIR_EscalationService.createForError(error.Id, 'REPLAY_CASE', false);
        System.assertEquals(0, [SELECT count() FROM Case WHERE Subject LIKE '%DELIVERY-DRAFT%']);
        Developer_Escalation__c savedDraft = [SELECT SLA_Due_At__c FROM Developer_Escalation__c WHERE Id = :draft.escalationId];
        AEIR_EscalationService.EscalationResult sent = AEIR_EscalationService.createForError(error.Id, 'REPLAY_CASE', true);
        AEIR_EscalationService.createForError(error.Id, 'REPLAY_CASE', true);
        System.assertEquals(draft.escalationId, sent.escalationId);
        System.assertEquals(1, [SELECT count() FROM Case WHERE Subject LIKE '%DELIVERY-DRAFT%']);
        Case delivered = [SELECT Description FROM Case WHERE Subject LIKE '%DELIVERY-DRAFT%' LIMIT 1];
        System.assert(delivered.Description.contains('SLA due: ' + String.valueOf(savedDraft.SLA_Due_At__c)),
            'Sending an existing draft must load its original SLA into the Case description.');
        System.assertNotEquals(null, [SELECT Delivery_Requested_At__c FROM Developer_Escalation__c WHERE Id = :sent.escalationId].Delivery_Requested_At__c);
    }
    @IsTest static void replayDoesNotReopenAResolvedErrorOrChangeItsResolutionTime() {
        caseRoute(); Error_Log__c error = log('DELIVERY-RESOLVED-REPLAY');
        AEIR_EscalationService.createForError(error.Id, 'REPLAY_CASE', true);
        error.Status__c = 'Resolved'; update error;
        Datetime resolvedAt = [SELECT Resolved_At__c FROM Error_Log__c WHERE Id = :error.Id].Resolved_At__c;
        AEIR_EscalationService.createForError(error.Id, 'REPLAY_CASE', true);
        Error_Log__c afterReplay = [SELECT Status__c, Resolved_At__c FROM Error_Log__c WHERE Id = :error.Id];
        System.assertEquals('Resolved', afterReplay.Status__c);
        System.assertEquals(resolvedAt, afterReplay.Resolved_At__c);
        System.assertEquals(1, [SELECT count() FROM Case WHERE Subject LIKE '%DELIVERY-RESOLVED-REPLAY%']);
    }
    @IsTest static void legacyDeliveredEscalationIsNotAutomaticallyResent() {
        caseRoute(); Error_Log__c error = log('LEGACY-DELIVERY');
        Developer_Escalation__c legacy = new Developer_Escalation__c(Error_Log__c = error.Id,
            Correlation_Id__c = error.Correlation_Id__c, Route_Key__c = 'REPLAY_CASE', Channel__c = 'Case', Status__c = 'Sent');
        insert legacy;
        AEIR_EscalationService.EscalationResult result = AEIR_EscalationService.createForError(error.Id, 'REPLAY_CASE', true);
        System.assertEquals(legacy.Id, result.escalationId);
        System.assertEquals(0, [SELECT count() FROM Case WHERE Subject LIKE '%LEGACY-DELIVERY%']);
        System.assertNotEquals(null, [SELECT Request_Key__c FROM Developer_Escalation__c WHERE Id = :legacy.Id].Request_Key__c);
    }
    @IsTest static void manualSessionEscalationsHaveTheSameReplayProtection() {
        caseRoute(); Diagnostic_Session__c session = new Diagnostic_Session__c(Correlation_Id__c = 'MANUAL-REPLAY',
            User__c = UserInfo.getUserId(), Resolution_Status__c = 'Open', User_Description__c = 'I need help');
        insert session;
        AEIR_EscalationService.EscalationResult first = AEIR_EscalationService.createForSession(session.Id, 'REPLAY_CASE', true);
        AEIR_EscalationService.EscalationResult replay = AEIR_EscalationService.createForSession(session.Id, 'REPLAY_CASE', true);
        System.assertEquals(first.escalationId, replay.escalationId);
        System.assertEquals(1, [SELECT count() FROM Case WHERE Subject LIKE '%MANUAL-REPLAY%']);
    }
    @IsTest static void durationsUseTransitionsAndUnrelatedEditsCannotRewriteThem() {
        Datetime created = Datetime.now().addHours(-2); Error_Log__c error = log('TIMING-TRANSITIONS');
        Test.setCreatedDate(error.Id, created);
        AEIR_ErrorLifecycleService.clockOverride = created.addMinutes(10);
        error.Status__c = 'Diagnosed'; update error;
        AEIR_ErrorLifecycleService.clockOverride = created.addMinutes(60);
        error.Status__c = 'Resolved'; update error;
        AEIR_ErrorLifecycleService.clockOverride = created.addMinutes(90);
        error.Original_Error_Message__c = 'Unrelated edit';
        error.First_Diagnosed_At__c = created; error.Resolved_At__c = created;
        Database.update(error, AccessLevel.SYSTEM_MODE);
        Error_Log__c saved = [SELECT First_Diagnosed_At__c, Resolved_At__c FROM Error_Log__c WHERE Id = :error.Id];
        System.assertEquals(created.addMinutes(10), saved.First_Diagnosed_At__c);
        System.assertEquals(created.addMinutes(60), saved.Resolved_At__c);
        AEIR_AdminConsoleController.Metrics metrics = AEIR_AdminConsoleController.getMetrics();
        System.assertEquals(10, metrics.meanMinutesToDiagnosis);
        System.assertEquals(60, metrics.meanMinutesToResolution);
    }
    @IsTest static void reopeningClearsResolutionTimeAndNewResolutionGetsANewTime() {
        Datetime first = Datetime.now(); Error_Log__c error = log('TIMING-REOPEN');
        AEIR_ErrorLifecycleService.clockOverride = first;
        error.Status__c = 'Resolved'; update error;
        error.Status__c = 'New'; update error;
        System.assertEquals(null, [SELECT Resolved_At__c FROM Error_Log__c WHERE Id = :error.Id].Resolved_At__c);
        AEIR_ErrorLifecycleService.clockOverride = first.addMinutes(20);
        error.Status__c = 'Resolved'; update error;
        System.assertEquals(first.addMinutes(20), [SELECT Resolved_At__c FROM Error_Log__c WHERE Id = :error.Id].Resolved_At__c);
    }
    @IsTest static void durationFormulasPreserveUnknownZeroAndKnownTimes() {
        Datetime created = Datetime.now().addHours(-2);
        Error_Log__c unknown = log('FORMULA-UNKNOWN');
        Error_Log__c zero = log('FORMULA-ZERO');
        Error_Log__c elapsed = log('FORMULA-ELAPSED');
        Error_Log__c invalid = log('FORMULA-INVALID');
        Test.setCreatedDate(unknown.Id, created);
        Test.setCreatedDate(zero.Id, created);
        Test.setCreatedDate(elapsed.Id, created);
        Test.setCreatedDate(invalid.Id, created);

        AEIR_ErrorLifecycleService.clockOverride = created;
        zero.Status__c = 'Diagnosed'; update zero;
        zero.Status__c = 'Resolved'; update zero;
        AEIR_ErrorLifecycleService.clockOverride = created.addMinutes(10);
        elapsed.Status__c = 'Diagnosed'; update elapsed;
        AEIR_ErrorLifecycleService.clockOverride = created.addMinutes(60);
        elapsed.Status__c = 'Resolved'; update elapsed;
        AEIR_ErrorLifecycleService.clockOverride = created.addMinutes(-1);
        invalid.Status__c = 'Diagnosed'; update invalid;
        invalid.Status__c = 'Resolved'; update invalid;

        Set<Id> ids = new Set<Id>{unknown.Id, zero.Id, elapsed.Id, invalid.Id};
        Map<Id, Error_Log__c> saved = new Map<Id, Error_Log__c>([
            SELECT Diagnosis_Duration_Minutes__c, Resolution_Duration_Minutes__c
            FROM Error_Log__c WHERE Id IN :ids
        ]);
        System.assertEquals(null, saved.get(unknown.Id).Diagnosis_Duration_Minutes__c,
            'Missing history must remain unknown rather than become zero.');
        System.assertEquals(null, saved.get(unknown.Id).Resolution_Duration_Minutes__c);
        System.assertEquals(0, saved.get(zero.Id).Diagnosis_Duration_Minutes__c,
            'An actual zero-minute transition must remain distinguishable from unknown.');
        System.assertEquals(0, saved.get(zero.Id).Resolution_Duration_Minutes__c);
        System.assertEquals(10, saved.get(elapsed.Id).Diagnosis_Duration_Minutes__c);
        System.assertEquals(60, saved.get(elapsed.Id).Resolution_Duration_Minutes__c);
        System.assertEquals(null, saved.get(invalid.Id).Diagnosis_Duration_Minutes__c,
            'An invalid transition earlier than capture must not produce negative history.');
        System.assertEquals(null, saved.get(invalid.Id).Resolution_Duration_Minutes__c);

        elapsed.Status__c = 'New'; update elapsed;
        Error_Log__c reopened = [SELECT Diagnosis_Duration_Minutes__c, Resolution_Duration_Minutes__c
            FROM Error_Log__c WHERE Id = :elapsed.Id];
        System.assertEquals(10, reopened.Diagnosis_Duration_Minutes__c);
        System.assertEquals(null, reopened.Resolution_Duration_Minutes__c,
            'Reopening removes the current resolution duration without changing first diagnosis.');
    }
}
