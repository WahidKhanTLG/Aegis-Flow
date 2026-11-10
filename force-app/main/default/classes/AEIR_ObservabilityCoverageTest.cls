@IsTest
private class AEIR_ObservabilityCoverageTest {
    @TestSetup
    static void setupSnapshotUsers() {
        Profile profile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String suffix = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 12);
        List<User> users = new List<User>();
        for (String alias : new List<String>{ 'aobsread', 'aobsdeny' }) {
            users.add(new User(FirstName = 'Aegis', LastName = 'Observability', Alias = alias,
                Email = alias + '@example.invalid', Username = alias + '.' + suffix + '@example.invalid',
                ProfileId = profile.Id, TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'));
        }
        insert users;
        PermissionSet endUser = [SELECT Id FROM PermissionSet WHERE Name = 'AEIR_End_User' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = users[0].Id, PermissionSetId = endUser.Id);
    }

    private static Context_Field_Setting__mdt rule(String field, Boolean agent, Boolean escalation) {
        return new Context_Field_Setting__mdt(Active__c = true, Field_API_Name__c = field,
            Include_In_Agent__c = agent, Include_In_Escalation__c = escalation);
    }
    private static Map<String, Object> objectJson(String jsonValue) {
        return (Map<String, Object>) JSON.deserializeUntyped(jsonValue);
    }

    @IsTest
    static void singleSnapshotUsesPackagedWhitelistAndRedactsCredentials() {
        Account accountRecord = new Account(Name = 'Single snapshot', Description = 'password=SINGLE_SNAPSHOT_PRIVATE');
        insert accountRecord;
        Map<String, Object> snapshot = objectJson(AEIR_ContextSnapshotService.getSnapshot('Account', accountRecord.Id, false));
        System.assertEquals('Single snapshot', snapshot.get('Account.Name'));
        System.assertEquals(String.valueOf(accountRecord.Id), snapshot.get('Account.Id'));
        System.assertEquals('password=[MASKED]', snapshot.get('Account.Description'));
        System.assert(!snapshot.containsKey('Account.AnnualRevenue'), 'Readable fields still require an explicit whitelist.');
        System.assert(!JSON.serialize(snapshot).contains('SINGLE_SNAPSHOT_PRIVATE'));
    }

    @IsTest
    static void agentAndEscalationWhitelistsRemainSeparateForSingleAndBulkReads() {
        AEIR_ContextSnapshotService.configurationOverrides = new Map<String, List<Context_Field_Setting__mdt>>{
            'Account' => new List<Context_Field_Setting__mdt>{
                rule('Name', true, false), rule('Description', false, true), rule('Does_Not_Exist__c', true, true),
                new Context_Field_Setting__mdt(Active__c = false, Field_API_Name__c = 'AnnualRevenue',
                    Include_In_Agent__c = true, Include_In_Escalation__c = true)
            }
        };
        Account accountRecord = new Account(Name = 'Separated whitelist', Description = 'password=BULK_SNAPSHOT_PRIVATE');
        insert accountRecord;
        Map<String, Object> agent = objectJson(AEIR_ContextSnapshotService.getSnapshot('Account', accountRecord.Id, false));
        Map<String, Object> escalation = objectJson(AEIR_ContextSnapshotService.getSnapshot('Account', accountRecord.Id, true));
        System.assertEquals('Separated whitelist', agent.get('Account.Name'));
        System.assert(!agent.containsKey('Account.Description'));
        System.assert(!escalation.containsKey('Account.Name'));
        System.assertEquals('password=[MASKED]', escalation.get('Account.Description'));
        Map<String, String> bulkSnapshots = AEIR_ContextSnapshotService.getSnapshots(
            new Map<String, Set<String>>{ 'Account' => new Set<String>{ accountRecord.Id } }, true);
        System.assertEquals(escalation, objectJson(bulkSnapshots.get(String.valueOf(accountRecord.Id))));
        System.assert(!JSON.serialize(bulkSnapshots).contains('BULK_SNAPSHOT_PRIVATE'));
    }

    @IsTest
    static void snapshotFlsAndObjectAccessRemainEffectiveWithConfiguredFields() {
        User reader = [SELECT Id FROM User WHERE Alias = 'aobsread' LIMIT 1];
        User denied = [SELECT Id FROM User WHERE Alias = 'aobsdeny' LIMIT 1];
        Error_Log__c log = new Error_Log__c(OwnerId = reader.Id, User__c = reader.Id,
            Correlation_Id__c = 'OBSERVABILITY-FLS', Source_Type__c = 'Flow', Severity__c = 'Medium', Status__c = 'New',
            Normalized_Message__c = 'Safe diagnostic summary', Original_Error_Message__c = 'FLS_PRIVATE_EVIDENCE');
        insert log;
        String objectName = Error_Log__c.SObjectType.getDescribe().getName();
        String rawField = Error_Log__c.Original_Error_Message__c.getDescribe().getName();
        String safeField = Error_Log__c.Normalized_Message__c.getDescribe().getName();
        AEIR_ContextSnapshotService.configurationOverrides = new Map<String, List<Context_Field_Setting__mdt>>{
            objectName => new List<Context_Field_Setting__mdt>{ rule(rawField, true, true), rule(safeField, true, true) }
        };
        System.runAs(reader) {
            System.assertEquals(false, Error_Log__c.Original_Error_Message__c.getDescribe().isAccessible());
            Map<String, Object> single = objectJson(AEIR_ContextSnapshotService.getSnapshot(objectName, log.Id, false));
            System.assertEquals('Safe diagnostic summary', single.get(objectName + '.' + safeField));
            System.assert(!single.containsKey(objectName + '.' + rawField));
            Map<String, String> bulkSnapshots = AEIR_ContextSnapshotService.getSnapshots(
                new Map<String, Set<String>>{ objectName => new Set<String>{ log.Id } }, false);
            System.assert(!JSON.serialize(bulkSnapshots).contains('FLS_PRIVATE_EVIDENCE'));
            System.assertEquals(single, objectJson(bulkSnapshots.get(String.valueOf(log.Id))));
        }
        System.runAs(denied) {
            System.assertEquals(false, Error_Log__c.SObjectType.getDescribe().isAccessible());
            System.assertEquals('{}', AEIR_ContextSnapshotService.getSnapshot(objectName, log.Id, false));
            System.assertEquals(0, AEIR_ContextSnapshotService.getSnapshots(
                new Map<String, Set<String>>{ objectName => new Set<String>{ log.Id } }, false).size());
        }
    }

    @IsTest
    static void snapshotsHandleMissingConfigurationInvalidObjectsAndBadIds() {
        Account accountRecord = new Account(Name = 'Id-only snapshot');
        insert accountRecord;
        AEIR_ContextSnapshotService.configurationOverrides = new Map<String, List<Context_Field_Setting__mdt>>();
        Map<String, Object> idOnly = objectJson(AEIR_ContextSnapshotService.getSnapshot('Account', accountRecord.Id, false));
        System.assertEquals(new Set<String>{ 'Account.Id' }, idOnly.keySet());
        System.assertEquals('{}', AEIR_ContextSnapshotService.getSnapshot(null, accountRecord.Id, false));
        System.assertEquals('{}', AEIR_ContextSnapshotService.getSnapshot('Account', null, false));
        System.assertEquals('{}', AEIR_ContextSnapshotService.getSnapshot('No_Such_Object__c', accountRecord.Id, false));
        System.assert(objectJson(AEIR_ContextSnapshotService.getSnapshot('Account', 'not-an-id', false)).containsKey('snapshotError'));
        System.assertEquals(0, AEIR_ContextSnapshotService.getSnapshots(null, false).size());
        System.assertEquals(0, AEIR_ContextSnapshotService.getSnapshots(new Map<String, Set<String>>{
            null => new Set<String>{ accountRecord.Id }, 'Account' => new Set<String>(),
            'Case' => null, 'No_Such_Object__c' => new Set<String>{ accountRecord.Id }
        }, false).size());
        Map<String, String> malformed = AEIR_ContextSnapshotService.getSnapshots(
            new Map<String, Set<String>>{ 'Account' => new Set<String>{ 'not-an-id', accountRecord.Id } }, false);
        System.assertEquals(2, malformed.size(), 'Reject only the malformed entry while preserving a valid snapshot.');
        System.assert(objectJson(malformed.get('not-an-id')).containsKey('snapshotError'));
        System.assertEquals(String.valueOf(accountRecord.Id), objectJson(malformed.get(String.valueOf(accountRecord.Id))).get('Account.Id'));
        Map<String, String> mismatched = AEIR_ContextSnapshotService.getSnapshots(
            new Map<String, Set<String>>{ 'Case' => new Set<String>{ accountRecord.Id } }, false);
        System.assert(objectJson(mismatched.get(String.valueOf(accountRecord.Id))).containsKey('snapshotError'),
            'A valid Salesforce Id must still match the requested object type.');
    }

    @IsTest
    static void snapshotOmissionPreservesTheCallersLastTenQueries() {
        List<Account> accounts = new List<Account>{ new Account(Name = 'Snapshot budget one'), new Account(Name = 'Snapshot budget two') };
        insert accounts;
        Id firstId = accounts[0].Id;
        Test.startTest();
        // Deliberately consume real query budget to verify the production limit guard.
        while (Limits.getLimitQueries() - Limits.getQueries() > 10) {
            List<Account> budget = [SELECT Id FROM Account WHERE Id = :firstId LIMIT 1];
        }
        Integer beforeQueries = Limits.getQueries();
        String single = AEIR_ContextSnapshotService.getSnapshot('Account', firstId, false);
        Map<String, String> bulkSnapshots = AEIR_ContextSnapshotService.getSnapshots(
            new Map<String, Set<String>>{ 'Account' => new Set<String>{ accounts[0].Id, accounts[1].Id } }, false);
        System.assertEquals(beforeQueries, Limits.getQueries(), 'Omission must not consume any of the caller reserve.');
        System.assertEquals(10, Limits.getLimitQueries() - Limits.getQueries());
        System.assert(((String) objectJson(single).get('snapshotError')).contains('query capacity'));
        System.assertEquals(2, bulkSnapshots.size(), 'Every omitted record receives an explicit result.');
        for (String snapshot : bulkSnapshots.values()) {
            System.assertEquals(objectJson(single), objectJson(snapshot));
        }
        Test.stopTest();
    }

    private class SourceDeniedException extends Exception {}
    private class FixtureEvidence extends AEIR_FlowCoverageService.EvidenceSource {
        List<FlowInterview> interviews = new List<FlowInterview>();
        List<FlowDefinitionView> inventory = new List<FlowDefinitionView>();
        Boolean denyInterviews = false;
        public override List<FlowInterview> failedInterviews() {
            if (denyInterviews) throw new SourceDeniedException('Synthetic provider access denial');
            return interviews;
        }
        public override List<FlowDefinitionView> activeFlows() { return inventory; }
    }
    private static FlowInterview interview(String guid, String label) {
        return (FlowInterview) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'FlowInterview' }, 'Guid' => guid,
            'InterviewLabel' => label, 'CurrentElement' => 'Update_Records',
            'Error' => 'password=FLOW_SAMPLE_PRIVATE', 'CreatedDate' => Datetime.now()
        }), FlowInterview.class);
    }
    private static FlowDefinitionView flow(String apiName, String label, String type, String triggerType) {
        return (FlowDefinitionView) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'FlowDefinitionView' },
            'ApiName' => apiName, 'Label' => label, 'ProcessType' => type, 'TriggerType' => triggerType
        }), FlowDefinitionView.class);
    }
    private static void capture(String source, Integer count) {
        List<Error_Log__c> logs = new List<Error_Log__c>();
        for (Integer i = 0; i < count; i++) logs.add(new Error_Log__c(
            Correlation_Id__c = 'OBS-' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)),
            User__c = UserInfo.getUserId(), Source_Type__c = 'Flow', Source_Name__c = source,
            Severity__c = 'Medium', Status__c = 'New'));
        insert logs;
    }
    private static void captureMatch(String source, String guid) {
        insert new Error_Log__c(Correlation_Id__c = 'FLOWINT-' + guid, User__c = UserInfo.getUserId(),
            Source_Type__c = 'Flow', Source_Name__c = source, Severity__c = 'Medium', Status__c = 'New');
    }
    private static Map<String, AEIR_FlowCoverageService.FlowCoverage> byLabel(AEIR_FlowCoverageService.CoverageReport report) {
        Map<String, AEIR_FlowCoverageService.FlowCoverage> rows = new Map<String, AEIR_FlowCoverageService.FlowCoverage>();
        for (AEIR_FlowCoverageService.FlowCoverage row : report.flows) rows.put(row.label, row);
        return rows;
    }

    @IsTest
    static void flowCoverageDedupesInterviewsAndDoesNotHideGapsWithOtherFlowsHistory() {
        FixtureEvidence source = new FixtureEvidence();
        source.interviews = new List<FlowInterview>{
            interview('gap-1', 'Gap Flow 1/2/2026, 10:00 AM'), interview('gap-2', 'Gap Flow 1/2/2026, 9:00 AM'),
            interview('gap-3', 'Gap Flow 1/2/2026, 8:00 AM'), interview('matched-1', 'Matched Flow 1/2/2026, 10:00 AM'),
            interview('matched-2', 'Matched Flow 1/2/2026, 9:00 AM'), interview('matched-1', 'Matched Flow 1/2/2026, 10:00 AM'),
            interview('interactive-1', 'Interactive Flow 1/2/2026, 10:00 AM'), interview('unknown-1', 'Unknown Inventory Flow')
        };
        source.inventory = new List<FlowDefinitionView>{
            flow('Gap_Flow', 'Gap Flow', 'AutoLaunchedFlow', 'RecordAfterSave'),
            flow('Matched_Flow', 'Matched Flow', 'AutoLaunchedFlow', null),
            flow('Interactive_Flow', 'Interactive Flow', 'Flow', null),
            flow('Aegis_Error_Capture_Fault_Subflow', 'Capture Subflow', 'AutoLaunchedFlow', null),
            flow('Unnamed', null, 'Workflow', null)
        };
        AEIR_FlowCoverageService.evidenceSource = source;
        captureMatch('Gap Flow / Update_Records', 'gap-1');
        captureMatch('Matched Flow / First_Element', 'matched-1');
        captureMatch('Matched Flow / Second_Element', 'matched-2');
        capture('Purged Flow / Update_Records', 5);
        AEIR_FlowCoverageService.CoverageReport report = AEIR_FlowCoverageService.scan();
        Map<String, AEIR_FlowCoverageService.FlowCoverage> rows = byLabel(report);
        System.assertEquals(7, report.totalFailuresObserved, 'Repeated delivery of the same interview must not inflate observations.');
        System.assertEquals(3, report.totalFailuresCaptured);
        System.assertEquals(8, report.historicalCaptureCount);
        System.assertEquals(4, report.uncapturedFailures, 'Purged history from another Flow must not hide current capture gaps.');
        System.assertEquals(4, report.totalActiveFlows, 'The capture subflow is infrastructure, not a customer Flow.');
        System.assertEquals(3, report.silentRiskFlows);
        System.assertEquals(2, rows.get('Gap Flow').captureGap);
        System.assertEquals('Capture gap', rows.get('Gap Flow').status);
        System.assertEquals('Silent failure', rows.get('Gap Flow').riskTier);
        System.assertEquals('Gap_Flow', rows.get('Gap Flow').apiName);
        System.assertEquals('User visible', rows.get('Interactive Flow').riskTier);
        System.assertEquals('Unknown', rows.get('Unknown Inventory Flow').riskTier);
        System.assertEquals(2, rows.get('Matched Flow').failuresObserved);
        System.assertEquals(2, rows.get('Matched Flow').failuresCaptured, 'Element suffixes must fold into one Flow.');
        System.assertEquals('Captured', rows.get('Matched Flow').status);
        System.assert(rows.get('Purged Flow').recommendation.contains('observed window'));
        System.assertEquals('Gap Flow', report.flows[0].label, 'Triage places the largest real gap first.');
        System.assert(!rows.get('Gap Flow').sampleError.contains('FLOW_SAMPLE_PRIVATE'));
        System.assert(report.summary.startsWith('4 of 7'));
    }

    @IsTest
    static void fullyMatchedFailuresHaveCapturedStatusAndAccurateSummary() {
        FixtureEvidence source = new FixtureEvidence();
        source.interviews.add(interview('all-matched', 'All Matched 1/2/2026, 10:00 AM'));
        source.inventory.add(flow('All_Matched', 'All Matched', 'Flow', null));
        AEIR_FlowCoverageService.evidenceSource = source;
        captureMatch('All Matched / Update_Records', 'all-matched');
        AEIR_FlowCoverageService.CoverageReport report = AEIR_FlowCoverageService.scan();
        System.assertEquals(0, report.uncapturedFailures);
        System.assertEquals('Captured', report.flows[0].status);
        System.assert(report.summary.startsWith('All 1 recorded Flow failure'));
    }

    @IsTest
    static void emptyInterviewsDistinguishHealthyInventoryFromPurgedCaptureHistory() {
        FixtureEvidence source = new FixtureEvidence();
        source.inventory.add(flow('Never_Failed', 'Never Failed', 'AutoLaunchedFlow', null));
        AEIR_FlowCoverageService.evidenceSource = source;
        AEIR_FlowCoverageService.CoverageReport empty = AEIR_FlowCoverageService.scan();
        System.assertEquals(0, empty.flows.size());
        System.assertEquals(1, empty.totalActiveFlows);
        System.assert(empty.summary.startsWith('No Flow failures recorded.'));
        capture('Historical Flow / Update_Records', 2);
        AEIR_FlowCoverageService.CoverageReport historical = AEIR_FlowCoverageService.scan();
        System.assertEquals(0, historical.totalFailuresObserved);
        System.assertEquals(0, historical.totalFailuresCaptured);
        System.assertEquals(2, historical.historicalCaptureCount);
        System.assertEquals('Captured', historical.flows[0].status);
        System.assert(historical.summary.contains('previously captured'));
        System.assertEquals('Unknown Flow', AEIR_FlowCoverageService.flowNameFrom(' 1/2/2026, 10:00 AM'));
    }

    @IsTest
    static void interviewPermissionFailureIsExplicitWithoutDiscardingKnownCaptures() {
        FixtureEvidence source = new FixtureEvidence();
        source.denyInterviews = true;
        AEIR_FlowCoverageService.evidenceSource = source;
        capture('Captured Despite Unreadable Interviews / Update_Records', 1);
        AEIR_FlowCoverageService.CoverageReport report = AEIR_FlowCoverageService.scan();
        System.assertEquals(false, report.interviewDataReadable);
        System.assertEquals(0, report.totalFailuresCaptured);
        System.assertEquals(1, report.historicalCaptureCount);
        System.assertEquals(0, report.totalFailuresObserved);
        System.assert(report.summary.contains('could not be read'));
        System.assert(!report.summary.startsWith('All'), 'Unavailable evidence must not be represented as complete coverage.');
    }
}
