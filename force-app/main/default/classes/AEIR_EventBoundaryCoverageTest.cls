@IsTest
private class AEIR_EventBoundaryCoverageTest {
    private class TelemetrySecretException extends Exception {}

    @IsTest
    static void subscriberFailureEvidenceMasksExceptionCredentials() {
        AEIR_SecuritySanitizerService.setSensitiveFieldsForTest(new List<Sensitive_Field__mdt>());
        AEIR_SubscriberTelemetry telemetry = new AEIR_SubscriberTelemetry('SafeSubscriber');
        telemetry.record('TELEMETRY-MASKING', new TelemetrySecretException(
            'Recovery failed; password=TELEMETRY_PRIVATE_PASSWORD; access_token=TELEMETRY_PRIVATE_TOKEN; stage=read'));
        Test.startTest();
        telemetry.flush();
        Test.stopTest();
        Delivery_Attempt__c audit = [SELECT Status__c, Response_Body__c FROM Delivery_Attempt__c
            WHERE Correlation_Id__c = 'TELEMETRY-MASKING' LIMIT 1];
        System.assertEquals('Failed', audit.Status__c);
        System.assert(audit.Response_Body__c.contains('SafeSubscriber'));
        System.assert(audit.Response_Body__c.contains('stage=read'));
        System.assert(audit.Response_Body__c.contains('[MASKED]'));
        System.assert(!audit.Response_Body__c.contains('TELEMETRY_PRIVATE_PASSWORD'));
        System.assert(!audit.Response_Body__c.contains('TELEMETRY_PRIVATE_TOKEN'));
        System.assertEquals(false, telemetry.hasFailures());
    }
    @TestSetup
    static void limitedDiagnosisOperator() {
        User limited = new User(Alias = 'aeevent', Email = 'event-boundary@example.invalid',
            Username = 'aegis-event-boundary-' + Datetime.now().getTime() + '@example.invalid',
            LastName = 'AegisEventBoundaryOperator', ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
        insert limited;
        PermissionSet telemetry = new PermissionSet(Name = 'AEIR_Event_Telemetry_Regression', Label = 'Aegis Event Telemetry Regression');
        insert telemetry;
        insert new ObjectPermissions(ParentId = telemetry.Id, SobjectType = 'Delivery_Attempt__c',
            PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true);
        List<FieldPermissions> fields = new List<FieldPermissions>();
        for (String field : new List<String>{ 'Correlation_Id__c', 'Channel__c', 'Status__c',
            'Attempt_Count__c', 'Idempotency_Key__c', 'Response_Body__c' }) {
            fields.add(new FieldPermissions(ParentId = telemetry.Id, SobjectType = 'Delivery_Attempt__c',
                Field = 'Delivery_Attempt__c.' + field, PermissionsRead = true, PermissionsEdit = true));
        }
        insert fields;
        insert new PermissionSetAssignment(AssigneeId = limited.Id, PermissionSetId = telemetry.Id);
    }
    private static Error_Log__c error(String correlation, Id owner) {
        Error_Log__c log = new Error_Log__c(Correlation_Id__c = correlation, Source_Type__c = 'Flow',
            Source_Name__c = 'Event_Boundary_Process', Error_Category__c = 'Missing Data', Severity__c = 'Medium',
            Original_Error_Message__c = 'REQUIRED_FIELD_MISSING: Name', Normalized_Message__c = 'A required value is missing.',
            Status__c = 'New', User__c = owner, OwnerId = owner);
        insert log;
        return log;
    }
    private static Diagnostic_Session__c session(String correlation, Id owner) {
        Diagnostic_Session__c session = new Diagnostic_Session__c(Correlation_Id__c = correlation,
            User_Description__c = 'A service process could not be completed.', User__c = owner,
            OwnerId = owner, Resolution_Status__c = 'Open');
        insert session;
        return session;
    }
    private static void configureRoutes() {
        AEIR_EscalationService.cachedRoutes = new List<Escalation_Route__mdt>{
            new Escalation_Route__mdt(DeveloperName = 'BOUNDARY_CASE', Route_Key__c = 'BOUNDARY_CASE',
                Channel__c = 'Case', Active__c = true)
        };
    }

    @IsTest
    static void nullAndEmptyBatchesAreSafeAndProduceNoNoise() {
        Test.startTest();
        AEIR_AgentDiagnosisRequestedEventHandler.handle(null);
        AEIR_AgentDiagnosisRequestedEventHandler.handle(new List<Agent_Diagnosis_Requested__e>());
        AEIR_EscalationRequestedEventHandler.handle(null);
        AEIR_EscalationRequestedEventHandler.handle(new List<Escalation_Requested__e>());
        Test.stopTest();
        System.assertEquals(0, [SELECT count() FROM Delivery_Attempt__c]);
        System.assertEquals(0, [SELECT count() FROM AI_Diagnosis__c]);
        System.assertEquals(0, [SELECT count() FROM Developer_Escalation__c]);
    }

    @IsTest
    static void diagnosisKeepsValidErrorAndSessionWorkBesideMalformedEvents() {
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.USER_NOTIFICATIONS, false);
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AI_DIAGNOSIS, false);
        Error_Log__c log = error('DIAG-VALID-ERROR', UserInfo.getUserId());
        Diagnostic_Session__c help = session('DIAG-VALID-SESSION', UserInfo.getUserId());
        Account wrongType = new Account(Name = 'Wrong event reference'); insert wrongType;
        List<Agent_Diagnosis_Requested__e> events = new List<Agent_Diagnosis_Requested__e>{
            null,
            new Agent_Diagnosis_Requested__e(Correlation_Id__c = 'DIAG-MALFORMED', Error_Log_Id__c = 'not-a-record'),
            new Agent_Diagnosis_Requested__e(Correlation_Id__c = 'DIAG-WRONG-TYPE', Error_Log_Id__c = wrongType.Id),
            new Agent_Diagnosis_Requested__e(Correlation_Id__c = 'DIAG-MISSING'),
            new Agent_Diagnosis_Requested__e(Correlation_Id__c = 'DIAG-AMBIGUOUS', Error_Log_Id__c = log.Id, Session_Id__c = help.Id),
            new Agent_Diagnosis_Requested__e(Correlation_Id__c = log.Correlation_Id__c, Error_Log_Id__c = String.valueOf(log.Id).substring(0, 15)),
            new Agent_Diagnosis_Requested__e(Correlation_Id__c = log.Correlation_Id__c, Error_Log_Id__c = log.Id),
            new Agent_Diagnosis_Requested__e(Correlation_Id__c = help.Correlation_Id__c, Session_Id__c = help.Id)
        };
        Test.startTest();
        Integer beforeQueries = Limits.getQueries(), beforeDml = Limits.getDmlStatements();
        AEIR_AgentDiagnosisRequestedEventHandler.handle(events);
        Integer queries = Limits.getQueries() - beforeQueries, dml = Limits.getDmlStatements() - beforeDml;
        Test.stopTest();
        System.assert(queries <= 15, 'Both diagnosis branches must remain bulk bounded; used ' + queries);
        System.assert(dml <= 15, 'Malformed events must share a telemetry flush; used ' + dml);
        System.assertEquals(1, [SELECT count() FROM AI_Diagnosis__c WHERE Error_Log__c = :log.Id], 'Duplicate record references must not create duplicate diagnoses in one batch.');
        System.assertEquals(1, [SELECT count() FROM AI_Diagnosis__c WHERE Diagnostic_Session__c = :help.Id]);
        System.assertEquals('Diagnosed', [SELECT Status__c FROM Error_Log__c WHERE Id = :log.Id].Status__c);
        System.assertEquals('Pending User', [SELECT Resolution_Status__c FROM Diagnostic_Session__c WHERE Id = :help.Id].Resolution_Status__c);
        System.assertEquals(5, [SELECT count() FROM Delivery_Attempt__c WHERE Status__c = 'Failed']);
        System.assertEquals(1, [SELECT count() FROM Delivery_Attempt__c WHERE Correlation_Id__c = 'DIAG-MALFORMED']);
        System.assertEquals(1, [SELECT count() FROM Delivery_Attempt__c WHERE Correlation_Id__c = 'DIAG-WRONG-TYPE']);
    }

    @IsTest
    static void nativeDiagnosisAccessFailuresRecordEveryEventCorrelation() {
        User limited = [SELECT Id FROM User WHERE LastName = 'AegisEventBoundaryOperator' LIMIT 1];
        Error_Log__c log = error('DIAG-ACCESS-LOG', limited.Id);
        Diagnostic_Session__c help = session('DIAG-ACCESS-SESSION', limited.Id);
        List<Agent_Diagnosis_Requested__e> events = new List<Agent_Diagnosis_Requested__e>{
            new Agent_Diagnosis_Requested__e(Correlation_Id__c = 'DIAG-FAILED-15', Error_Log_Id__c = String.valueOf(log.Id).substring(0, 15)),
            new Agent_Diagnosis_Requested__e(Correlation_Id__c = 'DIAG-FAILED-18', Error_Log_Id__c = log.Id),
            new Agent_Diagnosis_Requested__e(Correlation_Id__c = 'DIAG-FAILED-SESSION', Session_Id__c = String.valueOf(help.Id).substring(0, 15))
        };
        Test.startTest();
        System.runAs(limited) {
            System.assert(!Schema.SObjectType.Error_Log__c.isAccessible(), 'The telemetry-only fixture must have no diagnostic record read permission.');
            System.assert(!Schema.SObjectType.Diagnostic_Session__c.isAccessible(), 'The same denial must apply to manual sessions.');
            System.assert(!Schema.SObjectType.AI_Diagnosis__c.isCreateable(), 'Telemetry permission must not grant arbitrary diagnosis creation.');
            System.assert(Schema.SObjectType.Delivery_Attempt__c.isCreateable(), 'Operational telemetry is explicitly permitted for this limited operator fixture.');
            AEIR_AgentDiagnosisRequestedEventHandler.handle(events);
        }
        Test.stopTest();
        System.assertEquals(0, [SELECT count() FROM AI_Diagnosis__c]);
        System.assertEquals(3, [SELECT count() FROM Delivery_Attempt__c WHERE Correlation_Id__c LIKE 'DIAG-FAILED-%']);
        System.assertEquals(1, [SELECT count() FROM Delivery_Attempt__c WHERE Correlation_Id__c = 'DIAG-FAILED-15']);
        System.assertEquals(1, [SELECT count() FROM Delivery_Attempt__c WHERE Correlation_Id__c = 'DIAG-FAILED-SESSION']);
        System.assertEquals('New', [SELECT Status__c FROM Error_Log__c WHERE Id = :log.Id].Status__c);
    }

    @IsTest
    static void deletedReferencesAreReportedWhileValidDiagnosisWorkContinues() {
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.USER_NOTIFICATIONS, false);
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.AI_DIAGNOSIS, false);
        Error_Log__c deletedLog = error('DIAG-DELETED-LOG', UserInfo.getUserId());
        Error_Log__c goodLog = error('DIAG-SURVIVING-LOG', UserInfo.getUserId());
        Diagnostic_Session__c deletedHelp = session('DIAG-DELETED-SESSION', UserInfo.getUserId());
        Diagnostic_Session__c goodHelp = session('DIAG-SURVIVING-SESSION', UserInfo.getUserId());
        delete deletedLog;
        delete deletedHelp;
        Test.startTest();
        AEIR_AgentDiagnosisRequestedEventHandler.handle(new List<Agent_Diagnosis_Requested__e>{
            new Agent_Diagnosis_Requested__e(Correlation_Id__c = 'DIAG-DELETED-LOG', Error_Log_Id__c = deletedLog.Id),
            new Agent_Diagnosis_Requested__e(Correlation_Id__c = 'DIAG-DELETED-SESSION', Session_Id__c = deletedHelp.Id),
            new Agent_Diagnosis_Requested__e(Correlation_Id__c = goodLog.Correlation_Id__c, Error_Log_Id__c = goodLog.Id),
            new Agent_Diagnosis_Requested__e(Correlation_Id__c = goodHelp.Correlation_Id__c, Session_Id__c = goodHelp.Id)
        });
        Test.stopTest();
        System.assertEquals(2, [SELECT count() FROM AI_Diagnosis__c]);
        System.assertEquals(1, [SELECT count() FROM AI_Diagnosis__c WHERE Error_Log__c = :goodLog.Id]);
        System.assertEquals(1, [SELECT count() FROM AI_Diagnosis__c WHERE Diagnostic_Session__c = :goodHelp.Id]);
        System.assertEquals(2, [SELECT count() FROM Delivery_Attempt__c WHERE Correlation_Id__c LIKE 'DIAG-DELETED-%']);
    }

    @IsTest
    static void escalationHandlesErrorAndSessionReferencesAndIsolatesMalformedEvents() {
        configureRoutes();
        Error_Log__c log = error('ESC-VALID-ERROR', UserInfo.getUserId());
        Diagnostic_Session__c help = session('ESC-VALID-SESSION', UserInfo.getUserId());
        Account wrongType = new Account(Name = 'Wrong escalation reference'); insert wrongType;
        List<Escalation_Requested__e> events = new List<Escalation_Requested__e>{
            null,
            new Escalation_Requested__e(Correlation_Id__c = 'ESC-MALFORMED', Error_Log_Id__c = 'not-a-record'),
            new Escalation_Requested__e(Correlation_Id__c = 'ESC-WRONG-TYPE', Session_Id__c = wrongType.Id),
            new Escalation_Requested__e(Correlation_Id__c = 'ESC-MISSING'),
            new Escalation_Requested__e(Correlation_Id__c = 'ESC-AMBIGUOUS', Error_Log_Id__c = log.Id, Session_Id__c = help.Id),
            new Escalation_Requested__e(Correlation_Id__c = log.Correlation_Id__c, Error_Log_Id__c = String.valueOf(log.Id).substring(0, 15)),
            new Escalation_Requested__e(Correlation_Id__c = log.Correlation_Id__c, Error_Log_Id__c = log.Id),
            new Escalation_Requested__e(Correlation_Id__c = help.Correlation_Id__c, Session_Id__c = help.Id, Route_Key__c = ' BOUNDARY_CASE ')
        };
        Test.startTest();
        AEIR_EscalationRequestedEventHandler.handle(events);
        Test.stopTest();
        System.assertEquals(1, [SELECT count() FROM Developer_Escalation__c WHERE Error_Log__c = :log.Id]);
        System.assertEquals(1, [SELECT count() FROM Developer_Escalation__c WHERE Diagnostic_Session__c = :help.Id]);
        System.assertEquals(2, [SELECT count() FROM Case WHERE Subject LIKE '[Aegis Flow]%']);
        System.assertEquals(2, [SELECT count() FROM Delivery_Audit__c WHERE Status__c = 'Delivered']);
        System.assertEquals(5, [SELECT count() FROM Delivery_Attempt__c WHERE Status__c = 'Failed']);
    }

    @IsTest
    static void failedRoutesPreserveCorrelationsAndDoNotAbandonOtherRouteGroups() {
        configureRoutes();
        Error_Log__c failedLog = error('ESC-FAILED-LOG', UserInfo.getUserId());
        Error_Log__c goodLog = error('ESC-GOOD-LOG', UserInfo.getUserId());
        Diagnostic_Session__c failedHelp = session('ESC-FAILED-SESSION', UserInfo.getUserId());
        Diagnostic_Session__c goodHelp = session('ESC-GOOD-SESSION', UserInfo.getUserId());
        List<Escalation_Requested__e> events = new List<Escalation_Requested__e>{
            new Escalation_Requested__e(Correlation_Id__c = 'ESC-FAILED-15', Error_Log_Id__c = String.valueOf(failedLog.Id).substring(0, 15), Route_Key__c = 'MISSING_ROUTE'),
            new Escalation_Requested__e(Correlation_Id__c = 'ESC-FAILED-18', Error_Log_Id__c = failedLog.Id, Route_Key__c = 'MISSING_ROUTE'),
            new Escalation_Requested__e(Correlation_Id__c = 'ESC-FAILED-SESSION', Session_Id__c = String.valueOf(failedHelp.Id).substring(0, 15), Route_Key__c = 'MISSING_ROUTE'),
            new Escalation_Requested__e(Correlation_Id__c = goodLog.Correlation_Id__c, Error_Log_Id__c = goodLog.Id, Route_Key__c = 'BOUNDARY_CASE'),
            new Escalation_Requested__e(Correlation_Id__c = goodHelp.Correlation_Id__c, Session_Id__c = goodHelp.Id, Route_Key__c = 'BOUNDARY_CASE')
        };
        Test.startTest();
        AEIR_EscalationRequestedEventHandler.handle(events);
        Test.stopTest();
        System.assertEquals(2, [SELECT count() FROM Developer_Escalation__c]);
        System.assertEquals(2, [SELECT count() FROM Case WHERE Subject LIKE '[Aegis Flow]%']);
        System.assertEquals('Escalated', [SELECT Status__c FROM Error_Log__c WHERE Id = :goodLog.Id].Status__c);
        System.assertEquals('New', [SELECT Status__c FROM Error_Log__c WHERE Id = :failedLog.Id].Status__c);
        System.assertEquals(3, [SELECT count() FROM Delivery_Attempt__c WHERE Correlation_Id__c LIKE 'ESC-FAILED-%']);
        System.assertEquals(1, [SELECT count() FROM Delivery_Attempt__c WHERE Correlation_Id__c = 'ESC-FAILED-15']);
        System.assertEquals(1, [SELECT count() FROM Delivery_Attempt__c WHERE Correlation_Id__c = 'ESC-FAILED-SESSION']);
        System.assertEquals('Open', [SELECT Resolution_Status__c FROM Diagnostic_Session__c WHERE Id = :failedHelp.Id].Resolution_Status__c);
    }
}
