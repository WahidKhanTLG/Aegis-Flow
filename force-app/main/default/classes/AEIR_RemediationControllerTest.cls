@IsTest
private class AEIR_RemediationControllerTest {
    @TestSetup
    static void setupUsers() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniquePart = UserInfo.getOrganizationId() + '.' + Datetime.now().getTime();
        List<User> users = new List<User>();
        for (Integer i = 0; i < 2; i++) {
            users.add(new User(
                LastName = 'AegisRemediationController', Alias = 'aegfrm' + i,
                Email = 'aegis.remediation.' + i + '@example.com',
                Username = 'aegis.remediation.' + uniquePart + '.' + i + '@example.com',
                ProfileId = standardProfile.Id, TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
            ));
        }
        insert users;
        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (PermissionSet permission : [SELECT Id FROM PermissionSet WHERE Name IN ('AEIR_Product_Admin', 'AEIR_Sample_Account_Remediation')]) {
            assignments.add(new PermissionSetAssignment(AssigneeId = users[0].Id, PermissionSetId = permission.Id));
        }
        insert assignments;
    }

    private static User testUser(Integer index) {
        String alias = 'aegfrm' + index;
        return [SELECT Id FROM User WHERE LastName = 'AegisRemediationController' AND Alias = :alias LIMIT 1];
    }

    private static AEIR_RemediationOrchestrator.RemediationRequest requestFor(Id targetId) {
        AEIR_RemediationOrchestrator.RemediationRequest request = new AEIR_RemediationOrchestrator.RemediationRequest();
        request.actionKey = 'UPDATE_ACCOUNT_DESCRIPTION';
        request.objectApiName = 'Account';
        request.recordId = targetId;
        request.fieldApiName = 'Description';
        request.newValue = 'Approved browser correction';
        request.confirmed = true;
        return request;
    }

    @IsTest
    static void authorizedConfirmedCorrectionUsesTheExistingAuditAndWhitelist() {
        System.runAs(testUser(0)) {
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
            Account target = new Account(Name = 'Remediation facade success', Description = 'Before');
            insert target;
            Test.startTest();
            AEIR_RemediationOrchestrator.RemediationResult result =
                AEIR_RemediationController.executeRemediation(JSON.serialize(requestFor(target.Id)));
            Test.stopTest();
            System.assertEquals(true, result.success, result.technicalMessage);
            System.assertEquals('Executed', result.status);
            System.assertNotEquals(null, result.remediationActionId);
            System.assertEquals('Approved browser correction', [SELECT Description FROM Account WHERE Id = :target.Id].Description);
            Remediation_Action__c audit = [SELECT Status__c, Before_Value__c, After_Value__c FROM Remediation_Action__c WHERE Id = :result.remediationActionId];
            System.assertEquals('Executed', audit.Status__c);
            System.assertEquals('Before', audit.Before_Value__c);
            System.assertEquals('Approved browser correction', audit.After_Value__c);
        }
    }

    @IsTest
    static void unauthorizedCallerCannotGainAuthorityThroughTheFacade() {
        System.runAs(testUser(1)) {
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
            Account target = new Account(Name = 'Remediation facade denied', Description = 'Before');
            insert target;
            System.assertEquals(false, FeatureManagement.checkPermission('AEIR_Execute_Remediation'));
            Test.startTest();
            Integer beforeDml = Limits.getDmlStatements();
            AEIR_RemediationOrchestrator.RemediationResult result =
                AEIR_RemediationController.executeRemediation(JSON.serialize(requestFor(target.Id)));
            System.assertEquals(beforeDml, Limits.getDmlStatements(), 'Permission denial must occur before target or audit writes.');
            Test.stopTest();
            System.assertEquals(false, result.success);
            System.assertEquals('Denied', result.status);
            System.assertEquals('Before', [SELECT Description FROM Account WHERE Id = :target.Id].Description);
        }
    }

    @IsTest
    static void featureFlagAndWhitelistRemainServerEnforced() {
        System.runAs(testUser(0)) {
            Account target = new Account(Name = 'Remediation facade gates', Description = 'Before', Phone = '123');
            insert target;
            AEIR_RemediationOrchestrator.RemediationRequest request = requestFor(target.Id);
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, false);
            System.assertEquals(false, AEIR_RemediationController.executeRemediation(JSON.serialize(request)).success);
            AEIR_FeatureFlagService.overrides.put(AEIR_FeatureFlagService.GOVERNED_REMEDIATION, true);
            request.fieldApiName = 'Phone';
            System.assertEquals(false, AEIR_RemediationController.executeRemediation(JSON.serialize(request)).success,
                'A permitted user still cannot change fields outside the registered action.');
            Account stored = [SELECT Description, Phone FROM Account WHERE Id = :target.Id];
            System.assertEquals('Before', stored.Description);
            System.assertEquals('123', stored.Phone);
        }
    }

    @IsTest
    static void registeredProposalReadsActualValueWithoutMutation() {
        System.runAs(testUser(0)) {
            Account target = new Account(Name='Proposal review', Description='Current stored value'); insert target;
            List<AEIR_RemediationController.RegisteredAction> actions = AEIR_RemediationController.getAvailableActions();
            Boolean found=false;
            for (AEIR_RemediationController.RegisteredAction action: actions) {
                if(action.actionKey=='UPDATE_ACCOUNT_DESCRIPTION') found=true;
            }
            System.assert(found, 'Offer the registered action only when its object and field are accessible.');
            Integer beforeDml=Limits.getDmlStatements();
            AEIR_RemediationController.PreparedProposal proposal = AEIR_RemediationController.prepareProposal(
                'UPDATE_ACCOUNT_DESCRIPTION', target.Id, 'User proposed value', 'PROPOSAL-1');
            System.assertEquals('Current stored value', proposal.beforeValue);
            System.assertEquals('User proposed value', proposal.newValue);
            System.assertEquals('Account',proposal.objectApiName);
            System.assertEquals('Description',proposal.fieldApiName);
            System.assertEquals(beforeDml,Limits.getDmlStatements(), 'Preparation must not execute or audit a correction.');
            System.assertEquals('Current stored value',[SELECT Description FROM Account WHERE Id=:target.Id].Description);
        }
    }

    @IsTest
    static void proposalCannotChooseUnregisteredFieldsOrWrongRecordTypes() {
        System.runAs(testUser(0)) {
            for (String actionKey: new List<String>{'UNKNOWN', 'UPDATE_ACCOUNT_DESCRIPTION'}) {
                Boolean denied=false;
                try { AEIR_RemediationController.prepareProposal(actionKey,'003000000000001','value',null); }
                catch(AuraHandledException expected) { denied=true; }
                System.assert(denied,'Only registered actions on the matching typed object can be prepared.');
            }
            Boolean invalidIdDenied=false;
            try { AEIR_RemediationController.prepareProposal('UPDATE_ACCOUNT_DESCRIPTION','not-a-record','value',null); }
            catch(AuraHandledException expected) { invalidIdDenied=true; }
            System.assert(invalidIdDenied);
        }
        System.runAs(testUser(1)) {
            System.assertEquals(0,AEIR_RemediationController.getAvailableActions().size());
            Boolean denied=false;
            try { AEIR_RemediationController.prepareProposal('UPDATE_ACCOUNT_DESCRIPTION','001000000000001','value',null); }
            catch(AuraHandledException expected) { denied=true; }
            System.assert(denied,'Preparing cannot grant correction authority to an ordinary caller.');
        }
    }

    @IsTest
    static void missingConfirmationAndMalformedRequestsFailWithoutWrites() {
        AEIR_RemediationOrchestrator.RemediationRequest request = requestFor('001000000000001');
        request.confirmed = false;
        Map<String, Object> missingValue = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(request));
        missingValue.put('confirmed', true);
        missingValue.remove('newValue');
        String oversized = 'x';
        while (oversized.length() <= 100000) oversized += oversized;
        List<String> invalidRequests = new List<String>{
            null, '', 'null', '[]', '{"secretMarker":"DO-NOT-ECHO"', oversized,
            '{}', JSON.serialize(request), JSON.serialize(missingValue), '{"actionKey":"UNKNOWN","unexpectedAuthority":true}'
        };
        Test.startTest();
        Integer beforeDml = Limits.getDmlStatements();
        for (String invalid : invalidRequests) {
            Boolean rejected = false;
            try {
                AEIR_RemediationController.executeRemediation(invalid);
            } catch (AuraHandledException expected) {
                rejected = true;
                System.assert(!expected.getMessage().contains('DO-NOT-ECHO'), 'Do not echo request contents in parse failures.');
            }
            System.assertEquals(true, rejected, 'Invalid or unconfirmed requests must be rejected.');
        }
        System.assertEquals(beforeDml, Limits.getDmlStatements());
        Test.stopTest();
    }
}
