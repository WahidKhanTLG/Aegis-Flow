@IsTest
private class AEIR_CrossBusinessScenarioTest {
    @IsTest static void registeredRecoveryWorksForServiceAndCustomRecords() {
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
        PermissionSet role = [SELECT Id FROM PermissionSet WHERE Name = 'AEIR_Product_Admin' LIMIT 1];
        if ([SELECT count() FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :role.Id] == 0) {
            insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = role.Id);
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Case serviceRecord = new Case(Subject = 'Service recovery test', Description = 'Before');
            insert serviceRecord;
            Error_Feedback__c customRecord = new Error_Feedback__c(Comments__c = 'Before');
            insert customRecord;
            AEIR_RemediationOrchestrator.actionOverrides = new Map<String, Remediation_Action_Setting__mdt>{
                'TEST_SERVICE' => new Remediation_Action_Setting__mdt(Active__c = true, Requires_Confirmation__c = true,
                    Object__c = 'Case', Field__c = 'Description'),
                'TEST_CUSTOM' => new Remediation_Action_Setting__mdt(Active__c = true, Requires_Confirmation__c = true,
                    Object__c = Error_Feedback__c.SObjectType.getDescribe().getName(),
                    Field__c = Error_Feedback__c.Comments__c.getDescribe().getName())
            };
            AEIR_RemediationOrchestrator.RemediationRequest request = new AEIR_RemediationOrchestrator.RemediationRequest();
            request.confirmed = true;
            request.actionKey = 'TEST_SERVICE'; request.objectApiName = 'Case';
            request.fieldApiName = 'Description'; request.recordId = serviceRecord.Id; request.newValue = 'Confirmed service correction';
            Test.startTest();
            AEIR_RemediationOrchestrator.RemediationResult serviceResult = AEIR_RemediationOrchestrator.execute(request);
            System.assertEquals(true, serviceResult.success, serviceResult.technicalMessage);
            request.actionKey = 'TEST_CUSTOM'; request.objectApiName = Error_Feedback__c.SObjectType.getDescribe().getName();
            request.fieldApiName = Error_Feedback__c.Comments__c.getDescribe().getName(); request.recordId = customRecord.Id;
            request.newValue = 'Confirmed custom-object correction';
            AEIR_RemediationOrchestrator.RemediationResult customResult = AEIR_RemediationOrchestrator.execute(request);
            System.assertEquals(true, customResult.success, customResult.technicalMessage);
            System.assertEquals('Confirmed service correction', [SELECT Description FROM Case WHERE Id = :serviceRecord.Id].Description);
            System.assertEquals('Confirmed custom-object correction', [SELECT Comments__c FROM Error_Feedback__c WHERE Id = :customRecord.Id].Comments__c);
            Set<Id> auditIds = new Set<Id>{serviceResult.remediationActionId, customResult.remediationActionId};
            System.assertEquals(2, [SELECT count() FROM Remediation_Action__c WHERE Id IN :auditIds]);
            Test.stopTest();
        }
    }
    @IsTest static void standardBusinessFailuresHaveActionableClassifications() {
        Map<String, String> categories = new Map<String, String>{
            'DUPLICATES_DETECTED' => 'Validation Rule',
            'DUPLICATE_VALUE' => 'Validation Rule',
            'INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST' => 'Missing Data',
            'STRING_TOO_LONG' => 'Validation Rule',
            'INVALID_CROSS_REFERENCE_KEY' => 'Configuration',
            'CANNOT_EXECUTE_FLOW_TRIGGER' => 'Automation Failure',
            'REQUEST_LIMIT_EXCEEDED' => 'Integration',
            'INVALID_SESSION_ID' => 'Permission',
            'CALLOUT_EXCEPTION' => 'Integration',
            'Read timed out' => 'Integration',
            'HTTP 429' => 'Integration',
            'HTTP 503' => 'Integration',
            'Too many SOQL queries' => 'Governor Limit',
            'Too many DML statements' => 'Governor Limit',
            'heap size too large' => 'Governor Limit',
            'STORAGE_LIMIT_EXCEEDED' => 'Configuration'
        };
        for (String message : categories.keySet()) {
            AEIR_ErrorNormalizationService.Classification result = AEIR_ErrorNormalizationService.classify(message + ': representative business-process failure');
            System.assertEquals(categories.get(message), result.category, message);
            System.assert(!String.isBlank(result.recommendedAction), 'Every known failure needs a next step: ' + message);
            System.assert(!String.isBlank(result.userMessage), 'Every known failure needs user guidance: ' + message);
            System.assertEquals(null, result.remediationActionKey, 'Generic rules must not propose customer-specific writes.');
        }
        System.assertEquals(false, AEIR_ErrorNormalizationService.classify('INVALID_SESSION_ID').retryEligible,
            'Expired credentials require reconnection, not repeated automatic retries.');
        System.assertEquals(true, AEIR_ErrorNormalizationService.classify('HTTP 429').retryEligible);
        System.assertEquals(false, AEIR_ErrorNormalizationService.classify('Too many SOQL queries').retryEligible);
        System.assertEquals('Missing Data', AEIR_ErrorNormalizationService.classify(
            'CANNOT_EXECUTE_FLOW_TRIGGER: Order creation failed: REQUIRED_FIELD_MISSING: [AccountId]').category,
            'A generic Flow wrapper must not hide the actionable missing-data cause.');
        System.assertEquals('Validation Rule', AEIR_ErrorNormalizationService.classify(
            'CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY: trigger caused FIELD_CUSTOM_VALIDATION_EXCEPTION: service policy').category);
    }

    @IsTest static void bulkCapturePreservesSalesServiceCustomAndIntegrationEvidence() {
        AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.USER_NOTIFICATIONS, false);
        List<AEIR_ErrorCaptureService.ErrorInput> requests = new List<AEIR_ErrorCaptureService.ErrorInput>();
        List<String> objects = new List<String>{'Opportunity', 'Case', Incident__c.SObjectType.getDescribe().getName(), 'Account'};
        List<String> sources = new List<String>{'Flow', 'LWC', 'Apex Class', 'API'};
        List<String> messages = new List<String>{'REQUIRED_FIELD_MISSING', 'DUPLICATES_DETECTED', 'Too many SOQL queries', 'HTTP 503'};
        for (Integer i = 0; i < 200; i++) {
            Integer scenario = Math.mod(i, 4);
            AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
            input.correlationId = 'CROSS-BUSINESS-' + i;
            input.sourceType = sources[scenario];
            input.sourceName = 'Cross-business process ' + scenario;
            input.objectApiName = objects[scenario];
            input.originalMessage = messages[scenario] + ': captured failure';
            input.contextJson = '{"password":"PRIVATE_DEMO_VALUE","businessArea":"scenario-' + scenario + '"}';
            input.userId = UserInfo.getUserId();
            requests.add(input);
        }
        Test.startTest();
        Integer beforeQueries = Limits.getQueries();
        Integer beforeWrites = Limits.getDmlStatements();
        List<AEIR_ErrorCaptureService.CaptureResult> results = AEIR_ErrorCaptureService.captureFromEvents(requests);
        Integer queryCost = Limits.getQueries() - beforeQueries;
        Integer writeCost = Limits.getDmlStatements() - beforeWrites;
        System.assertEquals(200, results.size());
        for (Integer i = 0; i < results.size(); i++) {
            System.assertEquals(true, results[i].success, 'Each business surface must persist independently.');
            System.assertEquals(requests[i].correlationId, results[i].correlationId, 'Bulk results preserve request order.');
        }
        System.assert(queryCost <= 12, 'Bulk capture query cost must be bounded, actual=' + queryCost);
        System.assert(writeCost <= 12, 'Bulk capture write cost must be bounded, actual=' + writeCost);
        List<Error_Log__c> stored = [SELECT Correlation_Id__c, Object_API_Name__c, Context_JSON__c, User__c FROM Error_Log__c WHERE Source_Name__c LIKE 'Cross-business process%'];
        System.assertEquals(200, stored.size());
        Set<String> capturedObjects = new Set<String>();
        for (Error_Log__c log : stored) {
            capturedObjects.add(log.Object_API_Name__c);
            System.assertEquals(UserInfo.getUserId(), log.User__c);
            System.assert(!log.Context_JSON__c.contains('PRIVATE_DEMO_VALUE'), 'Secrets must be absent in every business context.');
            System.assert(log.Context_JSON__c.contains('businessArea'), 'Safe evidence must remain useful.');
        }
        System.assertEquals(new Set<String>(objects), capturedObjects);
        Test.stopTest();
    }

    @IsTest static void unknownBusinessFailuresAreCapturedWithoutInventingAFix() {
        AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
        input.sourceType = 'API';
        input.sourceName = 'Customer-owned process';
        input.originalMessage = 'CUSTOM_PROCESS_UNRECOGNIZED: the operation did not complete';
        Test.startTest();
        AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(input);
        AEIR_AgentforceGatewayService.DiagnosisResult diagnosis = AEIR_AgentforceGatewayService.diagnoseError(captured.errorLogId);
        System.assertEquals(true, captured.success);
        System.assertEquals('Unknown', captured.category);
        System.assertEquals('UNKNOWN', diagnosis.fixability);
        System.assertEquals(null, diagnosis.safeRemediationActionKey);
        System.assertEquals(true, diagnosis.escalationRequired);
        Test.stopTest();
    }
}
