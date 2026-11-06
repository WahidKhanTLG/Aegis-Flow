@IsTest
private class AEIR_HeadlessApiTest {
    @TestSetup
    static void setupAccess() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User unprivileged = new User(Alias = 'aeirapi', Email = 'aegis-api@example.invalid',
            EmailEncodingKey = 'UTF-8', LastName = 'Aegis API Boundary', LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US', TimeZoneSidKey = 'America/Los_Angeles', ProfileId = standardProfile.Id,
            Username = 'aegis.api.' + UserInfo.getOrganizationId() + '.' + Datetime.now().getTime() + '@example.invalid');
        insert unprivileged;
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        List<User> scopedUsers = new List<User>();
        for (String alias : new List<String>{'aeirhead', 'aeirfld', 'aeirend', 'aeirpos'}) {
            scopedUsers.add(new User(Alias = alias, Email = alias + '@example.invalid',
                EmailEncodingKey = 'UTF-8', LastName = 'Aegis ' + alias, LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US', TimeZoneSidKey = 'America/Los_Angeles', ProfileId = alias == 'aeirpos' ? adminProfile.Id : standardProfile.Id,
                Username = alias + '.' + UserInfo.getOrganizationId() + '.' + Datetime.now().getTime() + '@example.invalid'));
        }
        insert scopedUsers;
        Id headlessRole = [SELECT Id FROM PermissionSet WHERE Name = 'AEIR_Headless_User' LIMIT 1].Id;
        Id endUserRole = [SELECT Id FROM PermissionSet WHERE Name = 'AEIR_End_User' LIMIT 1].Id;
        PermissionSet restrictedRole = new PermissionSet(Name = 'Aegis_Headless_Fields_Test', Label = 'Aegis Headless Fields Test');
        insert restrictedRole;
        insert new ObjectPermissions(ParentId = restrictedRole.Id, SObjectType = 'Error_Log__c', PermissionsRead = true);
        List<FieldPermissions> fields = new List<FieldPermissions>();
        for (String fieldName : new List<String>{'Correlation_Id__c', 'Source_Type__c', 'Source_Name__c',
            'Object_API_Name__c', 'Record_Id__c', 'Error_Category__c', 'Severity__c', 'Status__c', 'User__c'}) {
            fields.add(new FieldPermissions(ParentId = restrictedRole.Id, SObjectType = 'Error_Log__c',
                Field = 'Error_Log__c.' + fieldName, PermissionsRead = true));
        }
        insert fields;
        List<PermissionSetAssignment> scopedAssignments = new List<PermissionSetAssignment>();
        for (User scopedUser : scopedUsers) {
            scopedAssignments.add(new PermissionSetAssignment(AssigneeId = scopedUser.Id, PermissionSetId = headlessRole));
        }
        scopedAssignments.add(new PermissionSetAssignment(AssigneeId = scopedUsers[1].Id, PermissionSetId = restrictedRole.Id));
        scopedAssignments.add(new PermissionSetAssignment(AssigneeId = scopedUsers[2].Id, PermissionSetId = endUserRole));
        Id productAdminRole = [SELECT Id FROM PermissionSet WHERE Name = 'AEIR_Product_Admin' LIMIT 1].Id;
        scopedAssignments.add(new PermissionSetAssignment(AssigneeId = scopedUsers[3].Id, PermissionSetId = productAdminRole));
        insert scopedAssignments;
    }

    private static void request(String method, String resource, String body) {
        RestRequest req = new RestRequest();
        req.httpMethod = method;
        req.requestURI = '/services/apexrest/aegis-flow/v1/operations/' + resource;
        if (body != null) req.requestBody = Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }
    private static Map<String, Object> response() {
        return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }
    private static Error_Log__c logFor(Id userId, String correlation, String objectName) {
        return new Error_Log__c(User__c = userId, OwnerId = userId, Correlation_Id__c = correlation,
            Source_Type__c = 'API', Source_Name__c = 'Business integration', Object_API_Name__c = objectName,
            Error_Category__c = 'Unknown', Severity__c = 'Medium', Status__c = 'New',
            Normalized_Message__c = 'An integration could not complete.');
    }

    @IsTest static void authenticatedCallerWithoutHeadlessPermissionIsDenied() {
        User user = [SELECT Id FROM User WHERE LastName = 'Aegis API Boundary' LIMIT 1];
        System.runAs(user) {
            request('GET', 'capabilities', null);
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(403, RestContext.response.statusCode);
            System.assertEquals(false, response().get('success'));
            request('POST', 'help', '{"description":"Need help"}');
            AEIR_HeadlessRestService.postOperation();
            System.assertEquals(403, RestContext.response.statusCode);
        }
    }
    @IsTest static void capabilitiesAndInvalidResourcesAreExplicit() {
        System.runAs(scopedUser('aeirpos')) {
            System.assert(FeatureManagement.checkPermission('AEIR_Headless_Access'), 'The positive fixture must execute with the actual Headless permission.');
            request('GET', 'capabilities', null);
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(200, RestContext.response.statusCode);
            System.assertEquals('1', response().get('apiVersion'));
            request('GET', 'unsupported', null);
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(404, RestContext.response.statusCode);
            request('POST', 'delete-record', '{}');
            AEIR_HeadlessRestService.postOperation();
            System.assertEquals(404, RestContext.response.statusCode);
        }
    }
    @IsTest static void errorsAreScopedAndPaginatedAcrossBusinessObjects() {
        System.runAs(scopedUser('aeirpos')) {
            System.assert(FeatureManagement.checkPermission('AEIR_Headless_Access'), 'The positive fixture must execute with the actual Headless permission.');
            User other = [SELECT Id FROM User WHERE LastName = 'Aegis API Boundary' LIMIT 1];
            insert new List<Error_Log__c>{
                logFor(UserInfo.getUserId(), 'API-SALES', 'Opportunity'),
                logFor(UserInfo.getUserId(), 'API-SERVICE', 'Case'),
                logFor(UserInfo.getUserId(), 'API-CUSTOM', Incident__c.SObjectType.getDescribe().getName()),
                logFor(other.Id, 'API-OTHER-USER', 'Account')
            };
            request('GET', 'errors', null);
            RestContext.request.addParameter('limit', '2');
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(200, RestContext.response.statusCode);
            List<Object> first = (List<Object>) response().get('items');
            System.assertEquals(2, first.size());
            String cursor = (String) response().get('nextCursor');
            System.assertNotEquals(null, cursor);
            Set<String> ids = new Set<String>();
            for (Object item : first) ids.add((String) ((Map<String, Object>) item).get('correlationId'));
            request('GET', 'errors', null);
            RestContext.request.addParameter('limit', '2');
            RestContext.request.addParameter('cursor', cursor);
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(200, RestContext.response.statusCode);
            List<Object> second = (List<Object>) response().get('items');
            System.assertEquals(1, second.size());
            for (Object item : second) {
                String correlation = (String) ((Map<String, Object>) item).get('correlationId');
                System.assert(!ids.contains(correlation), 'Cursor must not repeat the previous page.');
                ids.add(correlation);
            }
            System.assertEquals(new Set<String>{'API-SALES', 'API-SERVICE', 'API-CUSTOM'}, ids);
            request('GET', 'errors', null);
            RestContext.request.addParameter('objectApiName', 'Case');
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(1, ((List<Object>) response().get('items')).size());
        }
    }
    @IsTest static void invalidFiltersAndInjectionStayBounded() {
        System.runAs(scopedUser('aeirpos')) {
            System.assert(FeatureManagement.checkPermission('AEIR_Headless_Access'), 'The positive fixture must execute with the actual Headless permission.');
            request('GET', 'errors', null);
            RestContext.request.addParameter('limit', '101');
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(400, RestContext.response.statusCode);
            request('GET', 'errors', null);
            RestContext.request.addParameter('cursor', 'not-a-cursor');
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(400, RestContext.response.statusCode);
            request('GET', 'errors', null);
            RestContext.request.addParameter('objectApiName', 'Account\' OR User__c != null');
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(200, RestContext.response.statusCode);
            System.assertEquals(0, ((List<Object>) response().get('items')).size());
        }
    }
    @IsTest static void manualHelpAndMalformedActionsHaveRealOutcomes() {
        System.runAs(scopedUser('aeirpos')) {
            System.assert(FeatureManagement.checkPermission('AEIR_Headless_Access'), 'The positive fixture must execute with the actual Headless permission.');
            request('POST', 'help', '{"description":"The service process did not complete","objectApiName":"Case"}');
            AEIR_HeadlessRestService.postOperation();
            System.assertEquals(201, RestContext.response.statusCode);
            Id sessionId = (Id) (String) response().get('sessionId');
            Diagnostic_Session__c session = [SELECT User__c, Object_API_Name__c FROM Diagnostic_Session__c WHERE Id = :sessionId];
            System.assertEquals(UserInfo.getUserId(), session.User__c);
            System.assertEquals('Case', session.Object_API_Name__c);
            request('POST', 'help', '[]');
            AEIR_HeadlessRestService.postOperation();
            System.assertEquals(400, RestContext.response.statusCode);
            request('POST', 'help', '{"description":""}');
            AEIR_HeadlessRestService.postOperation();
            System.assertEquals(400, RestContext.response.statusCode);
            request('POST', 'dismiss', '{"correlationId":"UNKNOWN-OR-FOREIGN"}');
            AEIR_HeadlessRestService.postOperation();
            System.assertEquals(404, RestContext.response.statusCode);
        }
    }
    @IsTest static void onlyCanonicalOwnActiveNotificationCanBeDismissed() {
        System.runAs(scopedUser('aeirpos')) {
            System.assert(FeatureManagement.checkPermission('AEIR_Headless_Access'), 'The positive fixture must execute with the actual Headless permission.');
            Error_Log__c log = logFor(UserInfo.getUserId(), 'API-DISMISS', 'Case');
            insert log;
            insert new User_Notification__c(Correlation_Id__c = log.Correlation_Id__c,
                Target_User__c = UserInfo.getUserId(), OwnerId = UserInfo.getUserId(), Error_Log__c = log.Id,
                Dedupe_Key__c = 'API-DISMISS-TEST', Status__c = 'New', Notification_Type__c = 'Detected',
                Expires_At__c = Datetime.now().addHours(1), Severity__c = 'Medium', Headline__c = 'Issue detected');
            request('GET', 'notifications', null);
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(200, RestContext.response.statusCode);
            System.assertEquals(1, ((List<Object>) response().get('items')).size());
            request('POST', 'dismiss', '{"correlationId":"API-DISMISS"}');
            AEIR_HeadlessRestService.postOperation();
            System.assertEquals(200, RestContext.response.statusCode);
            System.assertEquals('Dismissed', [SELECT Status__c FROM User_Notification__c WHERE Correlation_Id__c = 'API-DISMISS'].Status__c);
            request('POST', 'dismiss', '{"correlationId":"API-DISMISS"}');
            AEIR_HeadlessRestService.postOperation();
            System.assertEquals(404, RestContext.response.statusCode);
        }
    }
    @IsTest static void incidentsAreBoundedAndEmptyIsValid() {
        System.runAs(scopedUser('aeirpos')) {
            System.assert(FeatureManagement.checkPermission('AEIR_Headless_Access'), 'The positive fixture must execute with the actual Headless permission.');
            request('GET', 'incidents', null);
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(200, RestContext.response.statusCode);
            System.assertEquals(0, ((List<Object>) response().get('items')).size());
        }
    }

    private static User scopedUser(String alias) {
        String expectedLastName = 'Aegis ' + alias;
        return [SELECT Id FROM User WHERE Alias = :alias AND LastName = :expectedLastName LIMIT 1];
    }
    private static User_Notification__c noticeFor(Id userId, String correlation, Id errorLogId) {
        return new User_Notification__c(Correlation_Id__c = correlation,
            Target_User__c = userId, OwnerId = userId, Error_Log__c = errorLogId,
            Dedupe_Key__c = correlation + ':' + userId, Status__c = 'New', Notification_Type__c = 'Detected',
            Expires_At__c = Datetime.now().addHours(1), Severity__c = 'Medium', Headline__c = 'Issue detected');
    }

    @IsTest static void headlessCapabilityDoesNotGrantDiagnosticObjectRights() {
        User user = scopedUser('aeirhead');
        Error_Log__c log = logFor(user.Id, 'HEADLESS-NO-ROLE', 'Case');
        insert log;
        User_Notification__c notice = noticeFor(user.Id, log.Correlation_Id__c, log.Id);
        insert notice;
        System.runAs(user) {
            System.assertEquals(true, FeatureManagement.checkPermission('AEIR_Headless_Access'));
            System.assertEquals(false, Error_Log__c.SObjectType.getDescribe().isAccessible());
            System.assertEquals(false, Diagnostic_Session__c.SObjectType.getDescribe().isCreateable());
            request('GET', 'capabilities', null);
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(200, RestContext.response.statusCode, 'Capability discovery contains no diagnostic records.');
            for (String resource : new List<String>{'errors', 'incidents', 'notifications'}) {
                request('GET', resource, null);
                AEIR_HeadlessRestService.getOperation();
                System.assertEquals(403, RestContext.response.statusCode, resource + ' needs diagnostic access.');
            }
            request('POST', 'help', '{"description":"A service process failed"}');
            AEIR_HeadlessRestService.postOperation();
            System.assertEquals(403, RestContext.response.statusCode);
            for (String action : new List<String>{'dismiss', 'escalate'}) {
                request('POST', action, '{"correlationId":"HEADLESS-NO-ROLE"}');
                AEIR_HeadlessRestService.postOperation();
                System.assertEquals(403, RestContext.response.statusCode, action + ' cannot gain adapter authority.');
            }
        }
        System.assertEquals('New', [SELECT Status__c FROM User_Notification__c WHERE Id = :notice.Id].Status__c);
        System.assertEquals(0, [SELECT count() FROM Diagnostic_Session__c WHERE User__c = :user.Id]);
    }

    @IsTest static void readableObjectWithoutRequiredFieldAccessStillReturnsForbidden() {
        System.runAs(scopedUser('aeirfld')) {
            System.assertEquals(true, Error_Log__c.SObjectType.getDescribe().isAccessible());
            System.assertEquals(false, Error_Log__c.Normalized_Message__c.getDescribe().isAccessible());
            request('GET', 'errors', null);
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(403, RestContext.response.statusCode, 'USER_MODE must enforce projected field permissions.');
        }
    }

    @IsTest static void endUserCannotSelectVisibleScopeOrEditReadOnlyNotices() {
        User user = scopedUser('aeirend');
        User_Notification__c notice = noticeFor(user.Id, 'HEADLESS-READ-ONLY', null);
        insert notice;
        System.runAs(user) {
            System.assertEquals(false, FeatureManagement.checkPermission('AEIR_View_Sensitive_Context'));
            request('GET', 'errors', null);
            RestContext.request.addParameter('scope', 'visible');
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(403, RestContext.response.statusCode);
            request('GET', 'notifications', null);
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(200, RestContext.response.statusCode);
            System.assertEquals(1, ((List<Object>) response().get('items')).size());
            System.assertEquals(false, User_Notification__c.SObjectType.getDescribe().isUpdateable());
            request('POST', 'dismiss', '{"correlationId":"HEADLESS-READ-ONLY"}');
            AEIR_HeadlessRestService.postOperation();
            System.assertEquals(403, RestContext.response.statusCode);
        }
        System.assertEquals('New', [SELECT Status__c FROM User_Notification__c WHERE Id = :notice.Id].Status__c);
    }

    @IsTest static void foreignNoticeAndExpiredNoticeCannotBeMutated() {
        System.runAs(scopedUser('aeirpos')) {
            System.assert(FeatureManagement.checkPermission('AEIR_Headless_Access'), 'The positive fixture must execute with the actual Headless permission.');
            User other = scopedUser('aeirhead');
            Error_Log__c log = logFor(other.Id, 'HEADLESS-FOREIGN', 'Opportunity');
            insert log;
            User_Notification__c foreignNotice = noticeFor(other.Id, log.Correlation_Id__c, log.Id);
            User_Notification__c expired = noticeFor(UserInfo.getUserId(), 'HEADLESS-EXPIRED', null);
            expired.Expires_At__c = Datetime.now().addMinutes(-1);
            insert new List<User_Notification__c>{foreignNotice, expired};
            for (String action : new List<String>{'dismiss', 'escalate'}) {
                request('POST', action, '{"correlationId":"HEADLESS-FOREIGN"}');
                AEIR_HeadlessRestService.postOperation();
                System.assertEquals(404, RestContext.response.statusCode);
                request('POST', action, '{"correlationId":"HEADLESS-EXPIRED"}');
                AEIR_HeadlessRestService.postOperation();
                System.assertEquals(404, RestContext.response.statusCode);
            }
            System.assertEquals('New', [SELECT Status__c FROM User_Notification__c WHERE Id = :foreignNotice.Id].Status__c);
            System.assertEquals(0, [SELECT count() FROM Developer_Escalation__c]);
        }
    }

    @IsTest static void incidentPagesTraverseEqualTimestampsAndNullObservationsWithoutRepeats() {
        System.runAs(scopedUser('aeirpos')) {
            System.assert(FeatureManagement.checkPermission('AEIR_Headless_Access'), 'The positive fixture must execute with the actual Headless permission.');
            Datetime observedAt = Datetime.now().addMinutes(-5);
            List<Incident__c> incidents = new List<Incident__c>();
            for (Integer i = 0; i < 5; i++) {
                incidents.add(new Incident__c(Incident_Key__c = 'HEADLESS-PAGE-' + i,
                    Highest_Severity__c = 'Medium', Status__c = 'Open', Occurrence_Count__c = 1,
                    First_Seen_At__c = observedAt, Last_Seen_At__c = i == 4 ? null : observedAt));
            }
            insert incidents;
            List<Error_Log__c> logs = new List<Error_Log__c>();
            for (Integer i = 0; i < incidents.size(); i++) {
                Error_Log__c log = logFor(UserInfo.getUserId(), 'HEADLESS-INCIDENT-' + i, i == 0 ? 'Opportunity' : 'Case');
                log.Incident__c = incidents[i].Id;
                logs.add(log);
            }
            insert logs;
            Set<String> returnedIds = new Set<String>();
            String cursor;
            Integer pages = 0;
            do {
                request('GET', 'incidents', null);
                RestContext.request.addParameter('limit', '2');
                if (cursor != null) RestContext.request.addParameter('cursor', cursor);
                AEIR_HeadlessRestService.getOperation();
                System.assertEquals(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());
                for (Object item : (List<Object>) response().get('items')) {
                    String returnedId = (String) ((Map<String, Object>) item).get('id');
                    System.assert(!returnedIds.contains(returnedId), 'Incident cursor must not repeat equal-timestamp rows.');
                    returnedIds.add(returnedId);
                }
                cursor = (String) response().get('nextCursor');
                pages++;
                System.assert(pages <= 3, 'Pagination must make progress through the null Last Seen row.');
            } while (cursor != null);
            System.assertEquals(3, pages);
            System.assertEquals(5, returnedIds.size());
            System.assert(returnedIds.contains(String.valueOf(incidents[4].Id)), 'Null observations remain retrievable.');
        }
    }

    @IsTest static void errorCursorsFreezeTheirWindowAndRejectTamperedOrMismatchedRequests() {
        System.runAs(scopedUser('aeirpos')) {
            System.assert(FeatureManagement.checkPermission('AEIR_Headless_Access'), 'The positive fixture must execute with the actual Headless permission.');
            insert new List<Error_Log__c>{
                logFor(UserInfo.getUserId(), 'HEADLESS-WINDOW-1', 'Case'),
                logFor(UserInfo.getUserId(), 'HEADLESS-WINDOW-2', 'Opportunity'),
                logFor(UserInfo.getUserId(), 'HEADLESS-WINDOW-3', 'Account')
            };
            request('GET', 'errors', null);
            RestContext.request.addParameter('limit', '1');
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(200, RestContext.response.statusCode);
            String firstCursor = (String) response().get('nextCursor');
            Map<String, Object> firstState = (Map<String, Object>) JSON.deserializeUntyped(EncodingUtil.base64Decode(firstCursor).toString());
            request('GET', 'errors', null);
            RestContext.request.addParameter('limit', '1');
            RestContext.request.addParameter('cursor', firstCursor);
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(200, RestContext.response.statusCode);
            Map<String, Object> secondState = (Map<String, Object>) JSON.deserializeUntyped(
                EncodingUtil.base64Decode((String) response().get('nextCursor')).toString());
            System.assertEquals(firstState.get('since'), secondState.get('since'), 'Keep the original lower time bound.');
            System.assertEquals(firstState.get('untilAt'), secondState.get('untilAt'), 'Keep the original upper time bound.');
            Account wrongType = new Account(Name = 'Cursor wrong object');
            insert wrongType;
            List<Map<String, Object>> invalidStates = new List<Map<String, Object>>();
            Map<String, Object> invalidId = firstState.clone();
            invalidId.put('lastId', wrongType.Id);
            invalidStates.add(invalidId);
            Map<String, Object> invalidWindow = firstState.clone();
            invalidWindow.put('since', Datetime.now().addDays(-40));
            invalidStates.add(invalidWindow);
            Map<String, Object> invalidFuture = firstState.clone();
            invalidFuture.put('untilAt', Datetime.now().addMinutes(5));
            invalidStates.add(invalidFuture);
            Map<String, Object> expired = firstState.clone();
            expired.put('untilAt', Datetime.now().addMinutes(-61));
            invalidStates.add(expired);
            Map<String, Object> extraKey = firstState.clone();
            extraKey.put('systemMode', true);
            invalidStates.add(extraKey);
            for (Map<String, Object> state : invalidStates) {
                request('GET', 'errors', null);
                RestContext.request.addParameter('limit', '1');
                RestContext.request.addParameter('cursor', EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(state))));
                AEIR_HeadlessRestService.getOperation();
                System.assertEquals(400, RestContext.response.statusCode, 'Reject cursor tampering before querying records.');
            }
            request('GET', 'errors', null);
            RestContext.request.addParameter('limit', '2');
            RestContext.request.addParameter('cursor', firstCursor);
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(400, RestContext.response.statusCode, 'A cursor cannot silently change page size.');
            request('GET', 'incidents', null);
            RestContext.request.addParameter('limit', '1');
            RestContext.request.addParameter('cursor', firstCursor);
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(400, RestContext.response.statusCode, 'Cursors are resource-specific.');
        }
    }

    @IsTest static void strictLimitsAndActionTypesCannotChangeScopeOrAuthority() {
        System.runAs(scopedUser('aeirpos')) {
            System.assert(FeatureManagement.checkPermission('AEIR_Headless_Access'), 'The positive fixture must execute with the actual Headless permission.');
            for (String invalidLimit : new List<String>{'', '0', '-1', '1.5', '+1', ' 1', '101', '9999999999'}) {
                request('GET', 'errors', null);
                RestContext.request.addParameter('limit', invalidLimit);
                AEIR_HeadlessRestService.getOperation();
                System.assertEquals(400, RestContext.response.statusCode);
            }
            request('POST', 'help', '{"description":42}');
            AEIR_HeadlessRestService.postOperation();
            System.assertEquals(400, RestContext.response.statusCode);
            request('POST', 'help', '{"description":"Need help","userId":"005000000000001"}');
            AEIR_HeadlessRestService.postOperation();
            System.assertEquals(400, RestContext.response.statusCode, 'Caller attribution is not an accepted input.');
            request('POST', 'dismiss', '{"correlationId":"X","scope":"visible"}');
            AEIR_HeadlessRestService.postOperation();
            System.assertEquals(400, RestContext.response.statusCode, 'Mutation scope cannot be broadened.');
        }
    }

    @IsTest static void contextUsesOwnedUserModeScopeAndOmitsTechnicalDataWithoutPermission() {
        User owner = scopedUser('aeirend');
        Error_Log__c ownLog = logFor(owner.Id, 'HEADLESS-CONTEXT-OWN', 'Case');
        ownLog.Original_Error_Message__c = 'TECHNICAL-CONTEXT-MARKER';
        ownLog.Stack_Trace__c = 'STACK-MARKER';
        Error_Log__c foreignLog = logFor(UserInfo.getUserId(), 'HEADLESS-CONTEXT-FOREIGN', 'Opportunity');
        insert new List<Error_Log__c>{ownLog, foreignLog};
        System.runAs(owner) {
            request('GET', 'context', null);
            RestContext.request.addParameter('errorLogId', ownLog.Id);
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());
            System.assertEquals('HEADLESS-CONTEXT-OWN', response().get('correlationId'));
            Map<String, Object> context = (Map<String, Object>) response().get('context');
            System.assert(context.containsKey('errorLog'));
            System.assertEquals(false, context.containsKey('technicalError'));
            System.assertEquals(false, context.containsKey('stackTrace'));
            System.assertEquals(false, context.containsKey('contexts'));
            System.assert(!RestContext.response.responseBody.toString().contains('TECHNICAL-CONTEXT-MARKER'));
            request('GET', 'context', null);
            RestContext.request.addParameter('errorLogId', foreignLog.Id);
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(404, RestContext.response.statusCode);
            request('GET', 'context', null);
            RestContext.request.addParameter('errorLogId', foreignLog.Id);
            RestContext.request.addParameter('scope', 'visible');
            AEIR_HeadlessRestService.getOperation();
            System.assertEquals(403, RestContext.response.statusCode);
        }
    }

    @IsTest static void contextRejectsMalformedAndWrongTypeIds() {
        System.runAs(scopedUser('aeirpos')) {
            System.assert(FeatureManagement.checkPermission('AEIR_Headless_Access'), 'The positive fixture must execute with the actual Headless permission.');
            Account accountRecord = new Account(Name = 'Context invalid type');
            insert accountRecord;
            for (String invalidId : new List<String>{null, 'not-an-id', String.valueOf(accountRecord.Id)}) {
                request('GET', 'context', null);
                if (invalidId != null) RestContext.request.addParameter('errorLogId', invalidId);
                AEIR_HeadlessRestService.getOperation();
                System.assertEquals(400, RestContext.response.statusCode);
            }
        }
    }
}
