@IsTest
private class AEIR_MonitorProgressTest {
    private static final Datetime OBSERVED_AT = Datetime.newInstanceGmt(2026, 1, 1, 12, 0, 0);
    private static String fakeId(String prefix, Integer n) { return prefix + String.valueOf(n + 1).leftPad(12, '0'); }
    private class FlowPages extends AEIR_FlowInterviewMonitor.EvidenceSource {
        List<FlowInterview> rows = new List<FlowInterview>();
        public override List<FlowInterview> page(Datetime at, Id lastId, Integer size) {
            List<FlowInterview> output = new List<FlowInterview>();
            for (FlowInterview row : rows) if (at == null || row.CreatedDate > at
                || (row.CreatedDate == at && String.valueOf(row.Id).compareTo(String.valueOf(lastId)) > 0)) {
                output.add(row); if (output.size() == size) break;
            }
            return output;
        }
    }
    private class AsyncPages extends AEIR_AsyncJobMonitorScheduler.EvidenceSource {
        List<AsyncApexJob> rows = new List<AsyncApexJob>();
        public override List<AsyncApexJob> page(Datetime at, Id lastId, Integer size) {
            List<AsyncApexJob> output = new List<AsyncApexJob>();
            for (AsyncApexJob row : rows) if (at == null || row.CompletedDate > at
                || (row.CompletedDate == at && String.valueOf(row.Id).compareTo(String.valueOf(lastId)) > 0)) {
                output.add(row); if (output.size() == size) break;
            }
            return output;
        }
    }
    private static void quiet() {
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.USER_NOTIFICATIONS, false);
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AUTO_DIAGNOSIS, false);
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AI_DIAGNOSIS, false);
    }
    @IsTest static void flowMonitorMovesPastTwoHundredAlreadyCapturedInterviews() {
        quiet(); FlowPages source = new FlowPages(); List<Error_Log__c> existing = new List<Error_Log__c>();
        for (Integer i = 0; i < 201; i++) {
            source.rows.add((FlowInterview)JSON.deserialize(JSON.serialize(new Map<String, Object>{
                'Id' => fakeId('301', i), 'Guid' => 'backlog-' + i, 'InterviewLabel' => 'Backlog Flow',
                'CurrentElement' => 'Update_Records', 'Error' => 'Save failed', 'CreatedDate' => OBSERVED_AT,
                'CreatedById' => UserInfo.getUserId() }), FlowInterview.class));
            if (i < 200) existing.add(new Error_Log__c(Correlation_Id__c = 'FLOWINT-backlog-' + i,
                User__c = UserInfo.getUserId(), Source_Type__c = 'Flow', Status__c = 'New'));
        }
        insert existing;
        insert new Aegis_Org_Setting__c(SetupOwnerId = UserInfo.getOrganizationId(), Company_Name__c = 'Preserve Setup');
        AEIR_FlowInterviewMonitor.evidenceSource = source;
        Test.startTest();
        System.assertEquals(0, AEIR_FlowInterviewMonitor.reconcile());
        System.assertEquals((Id)fakeId('301', 199), AEIR_MonitorCursorService.read(true).lastId);
        System.assertEquals(1, AEIR_FlowInterviewMonitor.reconcile());
        Test.stopTest();
        System.assertEquals(201, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c LIKE 'FLOWINT-backlog-%']);
        System.assertEquals(null, AEIR_MonitorCursorService.read(true).at, 'End of sweep resets so late status changes are seen.');
        System.assertEquals('Preserve Setup', [SELECT Company_Name__c FROM Aegis_Org_Setting__c LIMIT 1].Company_Name__c);
    }
    @IsTest static void asyncMonitorMovesPastOneHundredAlreadyCapturedJobs() {
        quiet(); AsyncPages source = new AsyncPages(); List<Error_Log__c> existing = new List<Error_Log__c>();
        for (Integer i = 0; i < 101; i++) {
            String idValue = fakeId('707', i);
            source.rows.add((AsyncApexJob)JSON.deserialize(JSON.serialize(new Map<String, Object>{
                'Id' => idValue, 'Status' => 'Failed', 'JobType' => 'Queueable', 'ExtendedStatus' => 'Save failed',
                'CreatedDate' => OBSERVED_AT.addDays(-7), 'CompletedDate' => OBSERVED_AT,
                'CreatedById' => UserInfo.getUserId() }), AsyncApexJob.class));
            if (i < 100) existing.add(new Error_Log__c(Correlation_Id__c = 'ASYNC-' + (Id)idValue,
                Async_Job_Id__c = (Id)idValue, User__c = UserInfo.getUserId(), Source_Type__c = 'Queueable', Status__c = 'New'));
        }
        insert existing; AEIR_AsyncJobMonitorScheduler.evidenceSource = source;
        Test.startTest();
        System.assertEquals(0, AEIR_AsyncJobMonitorScheduler.monitorFailedJobs());
        System.assertNotEquals(null, AEIR_MonitorCursorService.read(false).lastId);
        System.assertEquals(1, AEIR_AsyncJobMonitorScheduler.monitorFailedJobs());
        Test.stopTest();
        System.assertEquals(101, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c LIKE 'ASYNC-%']);
        System.assertEquals(null, AEIR_MonitorCursorService.read(false).at);
    }
    @IsTest static void monitorCursorsDoNotOverwriteOneAnother() {
        AEIR_MonitorCursorService.save(AEIR_MonitorCursorService.read(true), true, OBSERVED_AT, (Id)fakeId('301', 1));
        AEIR_MonitorCursorService.save(AEIR_MonitorCursorService.read(false), false, OBSERVED_AT.addHours(1), (Id)fakeId('707', 2));
        System.assertEquals(OBSERVED_AT, AEIR_MonitorCursorService.read(true).at);
        System.assertEquals(OBSERVED_AT.addHours(1), AEIR_MonitorCursorService.read(false).at);
    }
    private class CoverageEvidence extends AEIR_FlowCoverageService.EvidenceSource {
        public override List<FlowInterview> failedInterviews() {
            return new List<FlowInterview>{(FlowInterview)JSON.deserialize(
                '{"Guid":"new-failure","InterviewLabel":"Same Flow","CurrentElement":"Update_Records"}', FlowInterview.class)};
        }
        public override List<FlowDefinitionView> activeFlows() { return new List<FlowDefinitionView>(); }
    }
    @IsTest static void olderCapturesOfTheSameFlowCannotHideANewGap() {
        insert new Error_Log__c(Correlation_Id__c = 'FLOWINT-old-failure', Source_Type__c = 'Flow',
            Source_Name__c = 'Same Flow / Update_Records', User__c = UserInfo.getUserId(), Status__c = 'New');
        AEIR_FlowCoverageService.evidenceSource = new CoverageEvidence();
        AEIR_FlowCoverageService.CoverageReport before = AEIR_FlowCoverageService.scan();
        System.assertEquals(1, before.uncapturedFailures);
        System.assertEquals(0, before.totalFailuresCaptured);
        System.assertEquals(1, before.historicalCaptureCount);
        insert new Error_Log__c(Correlation_Id__c = 'FLOWINT-new-failure', Source_Type__c = 'Flow',
            Source_Name__c = 'Same Flow / Update_Records', User__c = UserInfo.getUserId(), Status__c = 'New');
        AEIR_FlowCoverageService.CoverageReport after = AEIR_FlowCoverageService.scan();
        System.assertEquals(0, after.uncapturedFailures);
        System.assertEquals(1, after.totalFailuresCaptured);
    }
    @IsTest static void longIncidentSourcesPreserveObjectTimeBucketAndSuffix() {
        Error_Log__c first = new Error_Log__c(Source_Type__c = 'Flow', Source_Name__c = ''.leftPad(250, 'x'),
            Error_Category__c = 'Validation Rule', Object_API_Name__c = 'Account');
        Error_Log__c other = first.clone(false, false, false, false); other.Object_API_Name__c = 'Contact';
        String key = AEIR_IncidentAggregationService.buildKey(first, OBSERVED_AT);
        System.assert(key.length() <= 255);
        System.assertNotEquals(key, AEIR_IncidentAggregationService.buildKey(other, OBSERVED_AT));
        System.assertNotEquals(key, AEIR_IncidentAggregationService.buildKey(first, OBSERVED_AT.addHours(2)));
        other = first.clone(false, false, false, false); other.Source_Name__c += 'y';
        System.assertNotEquals(key, AEIR_IncidentAggregationService.buildKey(other, OBSERVED_AT));
        System.assertEquals(key, AEIR_IncidentAggregationService.buildKey(first, OBSERVED_AT));
    }
}
