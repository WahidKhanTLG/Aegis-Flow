@IsTest
private class AEIR_UiSaveErrorControllerTest {
    @IsTest
    static void reportUiSaveErrorCapturesValidationFailure() {
        Test.startTest();
        AEIR_ErrorCaptureService.CaptureResult result = AEIR_UiSaveErrorController.reportUiSaveError(
            null,
            'Opportunity',
            '006000000000001AAA',
            'Test Opportunity',
            'Record save via Aegis UI Save Capture',
            'FIELD_CUSTOM_VALIDATION_EXCEPTION: Tax Code is required.',
            '{"Amount":[{"message":"Amount must be positive"}]}',
            '/lightning/r/Opportunity/006000000000001AAA/view'
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Capture should succeed');
        System.assertNotEquals(null, result.errorLogId, 'An Error_Log__c should be created');
        System.assert(!String.isBlank(result.correlationId), 'A correlation id should be assigned');

        Error_Log__c log = [
            SELECT Id, Source_Type__c, Source_Name__c, Error_Category__c, Action_Name__c, Record_Id__c
            FROM Error_Log__c WHERE Id = :result.errorLogId LIMIT 1
        ];
        System.assertEquals('LWC', log.Source_Type__c);
        System.assertEquals('Opportunity / Test Opportunity', log.Source_Name__c);
        System.assertEquals('Validation Rule', log.Error_Category__c);
        System.assertEquals('006000000000001AAA', log.Record_Id__c);
    }

    @IsTest
    static void reportScreenIssueCapturesManualReport() {
        Test.startTest();
        AEIR_ErrorCaptureService.CaptureResult result = AEIR_UiSaveErrorController.reportScreenIssue(
            'A validation message blocked my save but I do not see an Aegis alert.',
            '/lightning/o/Account/home',
            null,
            'Account',
            'Mozilla/5.0'
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Manual screen capture should succeed');
        System.assert(!String.isBlank(result.correlationId), 'A correlation id should be assigned');

        Error_Log__c log = [
            SELECT Id, Source_Type__c, Source_Name__c, Action_Name__c
            FROM Error_Log__c WHERE Id = :result.errorLogId LIMIT 1
        ];
        System.assertEquals('LWC', log.Source_Type__c);
        System.assertEquals('User reported screen issue', log.Action_Name__c);
    }
}
