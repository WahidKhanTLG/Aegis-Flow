@IsTest
private class AEIR_InputBoundaryTest {
    @TestSetup
    static void setupUsers() {
        Profile profile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String suffix = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 12);
        List<User> users = new List<User>();
        for (String alias : new List<String>{ 'aibown', 'aibpeer', 'aibrole' }) {
            users.add(new User(FirstName = 'Aegis', LastName = 'InputBoundary', Alias = alias,
                Email = alias + '@example.invalid', Username = alias + '.' + suffix + '@example.invalid',
                ProfileId = profile.Id, TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'));
        }
        insert users;
        PermissionSet endUser = [SELECT Id FROM PermissionSet WHERE Name = 'AEIR_End_User' LIMIT 1];
        List<PermissionSetAssignment> grants = new List<PermissionSetAssignment>();
        for (User userRecord : users) grants.add(new PermissionSetAssignment(AssigneeId = userRecord.Id, PermissionSetId = endUser.Id));
        PermissionSet sensitiveOnly = new PermissionSet(Name = 'AEIR_Boundary_Role', Label = 'Aegis Boundary Role Test');
        insert sensitiveOnly;
        // A technical role requires field access as well as the custom permission.
        // Grant no View All: the record-sharing assertions remain meaningful.
        insert new List<ObjectPermissions>{
            new ObjectPermissions(ParentId = sensitiveOnly.Id, SobjectType = 'Error_Log__c', PermissionsRead = true),
            new ObjectPermissions(ParentId = sensitiveOnly.Id, SobjectType = 'Error_Context__c', PermissionsRead = true)
        };
        insert new List<FieldPermissions>{
            new FieldPermissions(ParentId = sensitiveOnly.Id, SobjectType = 'Error_Log__c',
                Field = 'Error_Log__c.Original_Error_Message__c', PermissionsRead = true),
            new FieldPermissions(ParentId = sensitiveOnly.Id, SobjectType = 'Error_Log__c',
                Field = 'Error_Log__c.Stack_Trace__c', PermissionsRead = true),
            new FieldPermissions(ParentId = sensitiveOnly.Id, SobjectType = 'Error_Context__c',
                Field = 'Error_Context__c.Payload_JSON__c', PermissionsRead = true)
        };
        CustomPermission sensitive = [SELECT Id FROM CustomPermission WHERE DeveloperName = 'AEIR_View_Sensitive_Context' LIMIT 1];
        insert new SetupEntityAccess(ParentId = sensitiveOnly.Id, SetupEntityId = sensitive.Id);
        grants.add(new PermissionSetAssignment(AssigneeId = users[2].Id, PermissionSetId = sensitiveOnly.Id));
        insert grants;
    }

    private static User userFor(String alias) {
        return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
    }
    private static Error_Log__c logFor(Id userId, String correlation) {
        return new Error_Log__c(User__c = userId, OwnerId = userId, Correlation_Id__c = correlation,
            Source_Type__c = 'Flow', Source_Name__c = 'Boundary_Test', Severity__c = 'Medium',
            Object_API_Name__c = 'Account', Status__c = 'New', Error_Category__c = 'Missing Data',
            Normalized_Message__c = 'A required value is missing.', Original_Error_Message__c = 'PRIVATE-TECHNICAL-EVIDENCE');
    }
    private static AEIR_GetErrorContextAction.Request errorRequest(Id logId) {
        AEIR_GetErrorContextAction.Request request = new AEIR_GetErrorContextAction.Request();
        request.errorLogId = String.valueOf(logId);
        return request;
    }
    private static String repeated(Integer count) {
        String block = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
        List<String> parts = new List<String>();
        for (Integer i = 0; i <= count / block.length(); i++) parts.add(block);
        return String.join(parts, '').substring(0, count);
    }

    @IsTest
    static void nullAndWrongTypeContextRequestsDoNotLoseValidRequest() {
        User owner = userFor('aibown');
        Error_Log__c log = logFor(owner.Id, 'BOUNDARY-CONTEXT');
        insert log;
        Account accountRecord = new Account(Name = 'Boundary account');
        insert accountRecord;
        System.runAs(owner) {
            List<AEIR_GetErrorContextAction.Response> results = AEIR_GetErrorContextAction.run(
                new List<AEIR_GetErrorContextAction.Request>{ null, errorRequest(accountRecord.Id), errorRequest(log.Id) });
            System.assertEquals(3, results.size());
            System.assertEquals(null, results[0].contextJson);
            System.assertEquals(null, results[1].contextJson);
            System.assertNotEquals(null, results[2].contextJson);
            System.assertEquals('BOUNDARY-CONTEXT', results[2].correlationId);
            System.assert(!results[2].contextJson.contains('PRIVATE-TECHNICAL-EVIDENCE'));
        }
    }

    @IsTest
    static void sensitiveRoleAlsoRequiresRecordSharing() {
        User owner = userFor('aibown');
        User peer = userFor('aibpeer');
        User support = userFor('aibrole');
        Error_Log__c log = logFor(owner.Id, 'BOUNDARY-PRIVATE');
        insert log;
        System.runAs(support) {
            System.assert(FeatureManagement.checkPermission('AEIR_View_Sensitive_Context'));
            System.assertEquals(null, AEIR_GetErrorContextAction.run(
                new List<AEIR_GetErrorContextAction.Request>{ errorRequest(log.Id) })[0].contextJson,
                'The sensitive role alone must not bypass private record sharing.');
        }
        insert new List<Error_Log__Share>{
            new Error_Log__Share(ParentId = log.Id, UserOrGroupId = peer.Id, AccessLevel = 'Read', RowCause = Schema.Error_Log__Share.RowCause.Manual),
            new Error_Log__Share(ParentId = log.Id, UserOrGroupId = support.Id, AccessLevel = 'Read', RowCause = Schema.Error_Log__Share.RowCause.Manual)
        };
        System.runAs(peer) {
            System.assertEquals(null, AEIR_GetErrorContextAction.run(
                new List<AEIR_GetErrorContextAction.Request>{ errorRequest(log.Id) })[0].contextJson,
                'A peer needs the sensitive diagnostic role as well as a shared record.');
        }
        System.runAs(support) {
            String context = AEIR_GetErrorContextAction.run(
                new List<AEIR_GetErrorContextAction.Request>{ errorRequest(log.Id) })[0].contextJson;
            System.assertNotEquals(null, context);
            System.assert(context.contains('PRIVATE-TECHNICAL-EVIDENCE'));
        }
    }

    @IsTest
    static void contextChildrenAreLimitedAtQueryTime() {
        User support = userFor('aibrole');
        Error_Log__c log = logFor(support.Id, 'BOUNDARY-CHILDREN');
        insert log;
        List<AI_Diagnosis__c> diagnoses = new List<AI_Diagnosis__c>();
        List<Error_Context__c> contexts = new List<Error_Context__c>();
        for (Integer i = 0; i < 30; i++) {
            diagnoses.add(new AI_Diagnosis__c(OwnerId = support.Id, Error_Log__c = log.Id,
                Summary__c = 'Diagnosis ' + i, Agent_Status__c = 'Deterministic Fallback', Fixability__c = 'UNKNOWN'));
            contexts.add(new Error_Context__c(OwnerId = support.Id, Error_Log__c = log.Id,
                Context_Type__c = 'Payload', Sequence__c = i, Payload_JSON__c = '{"safe":true}'));
        }
        insert diagnoses;
        insert contexts;
        for (Integer i = 0; i < 29; i++) Test.setCreatedDate(diagnoses[i].Id, Datetime.now().addDays(-1));
        System.runAs(support) {
            Test.startTest();
            Integer beforeRows = Limits.getQueryRows();
            String result = AEIR_GetErrorContextAction.run(
                new List<AEIR_GetErrorContextAction.Request>{ errorRequest(log.Id) })[0].contextJson;
            Integer fetched = Limits.getQueryRows() - beforeRows;
            Test.stopTest();
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(result);
            System.assertEquals(20, ((List<Object>) payload.get('contexts')).size());
            System.assertEquals('Diagnosis 29', ((Map<String, Object>) payload.get('latestDiagnosis')).get('Summary__c'));
            System.assert(fetched <= 30, 'Query rows must be bounded before contexts are materialized: ' + fetched);
        }
    }

    @IsTest
    static void snapshotsValidateNullIdsAndObjectTypesAndNormalizeShortIds() {
        Account accountRecord = new Account(Name = 'Snapshot boundary');
        insert accountRecord;
        AEIR_GetRecordSnapshotAction.Request wrongType = new AEIR_GetRecordSnapshotAction.Request();
        wrongType.objectApiName = 'Case'; wrongType.recordId = accountRecord.Id;
        AEIR_GetRecordSnapshotAction.Request malformed = new AEIR_GetRecordSnapshotAction.Request();
        malformed.objectApiName = 'Account'; malformed.recordId = 'not-an-id';
        AEIR_GetRecordSnapshotAction.Request valid = new AEIR_GetRecordSnapshotAction.Request();
        valid.objectApiName = 'Account'; valid.recordId = String.valueOf(accountRecord.Id).substring(0, 15);
        List<AEIR_GetRecordSnapshotAction.Response> results = AEIR_GetRecordSnapshotAction.run(
            new List<AEIR_GetRecordSnapshotAction.Request>{ null, wrongType, malformed, valid });
        System.assertEquals(4, results.size());
        for (Integer i = 0; i < 3; i++) System.assertEquals(null, results[i].snapshotJson);
        System.assertNotEquals(null, results[3].snapshotJson, 'A valid short Id must map to the normalized snapshot key.');
    }

    @IsTest
    static void malformedHelpContextIsRejectedBeforeAnySessionWrite() {
        for (String payload : new List<String>{ '[]', 'null', '42', '{"broken":', '{"recordId":123}', '{"pageReference":[]}' }) {
            Boolean rejected = false;
            try { AEIR_HelpMeController.createSession(payload, 'Need help', 'Report Issue'); }
            catch (AuraHandledException expected) { rejected = true; }
            System.assert(rejected, 'Reject invalid context instead of silently losing it.');
        }
        Boolean oversized = false;
        try { AEIR_HelpMeController.createSession('{}', repeated(32769), 'Report Issue'); }
        catch (AuraHandledException expected) { oversized = true; }
        System.assert(oversized);
        System.assertEquals(0, [SELECT count() FROM Diagnostic_Session__c]);
    }

    @IsTest
    static void browserAttributionCannotOverrideUserButTrustedServerCan() {
        User owner = userFor('aibown');
        User peer = userFor('aibpeer');
        Id browserSession;
        System.runAs(owner) {
            browserSession = AEIR_HelpMeController.createSession(JSON.serialize(new Map<String, Object>{
                'userId' => peer.Id, 'objectApiName' => 'Case'
            }), 'Help with a service process', 'Process Failed').sessionId;
        }
        Diagnostic_Session__c browser = [SELECT OwnerId, User__c FROM Diagnostic_Session__c WHERE Id = :browserSession];
        System.assertEquals(owner.Id, browser.User__c);
        System.assertEquals(owner.Id, browser.OwnerId);
        AEIR_DiagnosticSessionService.SessionInput trusted = new AEIR_DiagnosticSessionService.SessionInput();
        trusted.userId = peer.Id; trusted.objectApiName = 'Error_Feedback__c'; trusted.createdFrom = 'API';
        AEIR_DiagnosticSessionService.SessionResult result = AEIR_DiagnosticSessionService.createSession(trusted);
        System.assertNotEquals(null, result.sessionId, result.message);
        Diagnostic_Session__c server = [SELECT OwnerId, User__c FROM Diagnostic_Session__c WHERE Id = :result.sessionId];
        System.assertEquals(peer.Id, server.User__c);
        System.assertEquals(peer.Id, server.OwnerId);
    }

    @IsTest
    static void invalidSessionRowsCannotUndoOtherSalesServiceOrCustomSessions() {
        Account accountRecord = new Account(Name = 'Session batch boundary');
        insert accountRecord;
        List<AEIR_DiagnosticSessionService.SessionInput> requests = new List<AEIR_DiagnosticSessionService.SessionInput>{ null };
        AEIR_DiagnosticSessionService.SessionInput badUser = new AEIR_DiagnosticSessionService.SessionInput();
        badUser.userId = accountRecord.Id; requests.add(badUser);
        AEIR_DiagnosticSessionService.SessionInput oversized = new AEIR_DiagnosticSessionService.SessionInput();
        oversized.userDescription = repeated(32769); requests.add(oversized);
        AEIR_DiagnosticSessionService.SessionInput wrongType = new AEIR_DiagnosticSessionService.SessionInput();
        wrongType.objectApiName = 'Case'; wrongType.contextRecordId = accountRecord.Id; requests.add(wrongType);
        AEIR_DiagnosticSessionService.SessionInput badPicklist = new AEIR_DiagnosticSessionService.SessionInput();
        badPicklist.detectedIssueType = 'NOT_AN_ISSUE_TYPE'; requests.add(badPicklist);
        for (String objectName : new List<String>{ 'Account', 'Case', 'Error_Feedback__c' }) {
            AEIR_DiagnosticSessionService.SessionInput valid = new AEIR_DiagnosticSessionService.SessionInput();
            valid.objectApiName = objectName; valid.detectedIssueType = 'Report Issue'; requests.add(valid);
        }
        List<AEIR_DiagnosticSessionService.SessionResult> results = AEIR_DiagnosticSessionService.createSessions(requests);
        System.assertEquals(requests.size(), results.size());
        for (Integer i = 0; i < 5; i++) {
            System.assertEquals('Failed', results[i].status);
            System.assertEquals(null, results[i].sessionId);
            System.assertNotEquals(null, results[i].message);
        }
        for (Integer i = 5; i < results.size(); i++) {
            System.assertEquals('Open', results[i].status, results[i].message);
            System.assertNotEquals(null, results[i].sessionId);
        }
        System.assertEquals(3, [SELECT count() FROM Diagnostic_Session__c]);
    }

    @IsTest
    static void sharedForeignSessionsAndForeignLinkedLogsCannotBeDiagnosedOrEscalated() {
        User owner = userFor('aibown');
        User peer = userFor('aibpeer');
        Error_Log__c log = logFor(owner.Id, 'BOUNDARY-FOREIGN-LINK');
        insert log;
        Diagnostic_Session__c foreign = new Diagnostic_Session__c(OwnerId = owner.Id, User__c = owner.Id,
            Resolution_Status__c = 'Open', Detected_Issue_Type__c = 'Unknown', Created_From__c = 'Help Me Utility');
        Diagnostic_Session__c poisoned = new Diagnostic_Session__c(OwnerId = peer.Id, User__c = peer.Id,
            Recent_Error_Log__c = log.Id, Resolution_Status__c = 'Open', Detected_Issue_Type__c = 'Unknown', Created_From__c = 'Help Me Utility');
        insert new List<Diagnostic_Session__c>{ foreign, poisoned };
        insert new Diagnostic_Session__Share(ParentId = foreign.Id, UserOrGroupId = peer.Id,
            AccessLevel = 'Edit', RowCause = Schema.Diagnostic_Session__Share.RowCause.Manual);
        insert new Error_Log__Share(ParentId = log.Id, UserOrGroupId = peer.Id,
            AccessLevel = 'Read', RowCause = Schema.Error_Log__Share.RowCause.Manual);
        System.runAs(peer) {
            for (Id sessionId : new List<Id>{ foreign.Id, poisoned.Id }) {
                Boolean diagnosisDenied = false;
                try { AEIR_HelpMeController.diagnoseSession(sessionId); }
                catch (AuraHandledException expected) { diagnosisDenied = true; }
                System.assert(diagnosisDenied);
                Boolean escalationDenied = false;
                try { AEIR_HelpMeController.escalateSession(sessionId, 'Unauthorized description'); }
                catch (AuraHandledException expected) { escalationDenied = true; }
                System.assert(escalationDenied);
            }
            System.assertEquals(0, AEIR_HelpMeController.getRecentErrors(null, 'Account').size());
        }
        System.assertEquals(0, [SELECT count() FROM AI_Diagnosis__c]);
        System.assertEquals(0, [SELECT count() FROM Developer_Escalation__c]);
        System.assertEquals(null, [SELECT User_Description__c FROM Diagnostic_Session__c WHERE Id = :foreign.Id].User_Description__c);
    }

    @IsTest
    static void subscriberPersistsValidSessionsAndRecordsRejectedInputTelemetry() {
        Account accountRecord = new Account(Name = 'Subscriber invalid user');
        insert accountRecord;
        AEIR_DiagnosticSessionRequestHandler.handle(AEIR_EventTestData.sessions(new List<Diagnostic_Session_Requested__e>{
            null,
            new Diagnostic_Session_Requested__e(Correlation_Id__c = 'BOUNDARY-REJECTED', User_Id__c = accountRecord.Id),
            new Diagnostic_Session_Requested__e(Correlation_Id__c = 'BOUNDARY-ACCEPTED', User_Id__c = UserInfo.getUserId())
        }, UserInfo.getUserId()));
        System.assertEquals(1, [SELECT count() FROM Diagnostic_Session__c WHERE Correlation_Id__c = 'BOUNDARY-ACCEPTED']);
        System.assertEquals(1, [SELECT count() FROM Delivery_Attempt__c WHERE Correlation_Id__c = 'BOUNDARY-REJECTED' AND Status__c = 'Failed']);
    }
}
