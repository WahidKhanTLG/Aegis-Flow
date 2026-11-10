@IsTest
private class AEIR_NamespaceContractTest {
    @IsTest static void alertChannelUsesActualSchemaNamespace() {
        System.assertEquals('/event/' + Aegis_User_Alert__e.SObjectType.getDescribe().getName(),
            AEIR_AegisHeadlessMonitorController.getAlertChannel());
    }
    @IsTest static void packageRetryHandlersUseTypeTokens() {
        System.assertEquals(AEIR_ApprovedFlowRetryHandler.class,
            AEIR_RetryOrchestrationService.resolveHandlerType('AEIR_ApprovedFlowRetryHandler'));
        System.assertEquals(AEIR_SampleTaxRetryHandler.class,
            AEIR_RetryOrchestrationService.resolveHandlerType('AEIR_SampleTaxRetryHandler'));
        for (String invalidName : new List<String>{null, '', 'MissingAegisHandler', '../Handler', 'Bad Name'}) {
            System.assertEquals(null, AEIR_RetryOrchestrationService.resolveHandlerType(invalidName));
        }
    }
    @IsTest static void retentionPoliciesUseStableLogicalKeys() {
        Set<String> keys = new Set<String>{ AEIR_RetentionScheduler.ERROR_LOG, AEIR_RetentionScheduler.DIAGNOSTIC_SESSION };
        Integer policies = 0;
        for (Retention_Policy__mdt policy : Retention_Policy__mdt.getAll().values()) {
            if (policy.Active__c == true) {
                System.assert(keys.contains(policy.Object_Name__c), 'Policy keys are logical identifiers, not namespace-prefixed API names.');
                policies++;
            }
        }
        System.assert(policies >= 2, 'Both packaged retention policies must remain available.');
    }
    @IsTest static void subscriberActionDtosHaveUsableConstructors() {
        System.assertNotEquals(null, new AEIR_GetErrorContextAction.Request());
        System.assertNotEquals(null, new AEIR_GetRecordSnapshotAction.Request());
        System.assertNotEquals(null, new AEIR_FindRecentErrorsAction.Request());
        System.assertNotEquals(null, new AEIR_UpdateMissingFieldAction.Request());
        System.assertNotEquals(null, new AEIR_ExecuteRemediationAction.Request());
        System.assertNotEquals(null, new AEIR_InvokeDiagnosisAction.Request());
        System.assertNotEquals(null, new AEIR_CreateEscalationAction.Request());
        System.assertNotEquals(null, new AEIR_CaptureFlowFaultAction.Request());
        AEIR_RetryOrchestrationService.RetryRequest request = new AEIR_RetryOrchestrationService.RetryRequest();
        request.handlerKey = 'NOT_REGISTERED';
        System.assertEquals('NOT_REGISTERED', request.handlerKey);
    }
}
