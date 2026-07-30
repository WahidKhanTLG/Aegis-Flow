/**
 * Coverage for AEIR_BatchApexErrorEventTrigger.
 *
 * BatchApexErrorEvent cannot be constructed and published directly (its fields are
 * not writeable), so the only way to raise one is to let a real batch that implements
 * Database.RaisesPlatformEvents fail. The intentional failure surfaces out of
 * Test.stopTest(), so it is caught, and Test.getEventBus().deliver() is then used to
 * drain the queued event into the trigger.
 */
@IsTest
private class AEIR_BatchApexErrorTriggerTest {

    @IsTest
    static void batchFailureCreatesErrorLog() {
        try {
            Test.startTest();
            Database.executeBatch(new AEIR_FailingBatchTestHelper());
            Test.stopTest();
        } catch (Exception expected) {
            // The batch crashed as designed, which queues the BatchApexErrorEvent.
        }

        Test.getEventBus().deliver();

        List<Error_Log__c> captured = [
            SELECT Id, Source_Type__c, Correlation_Id__c, Severity__c
            FROM Error_Log__c
            WHERE Source_Type__c = 'Batch'
        ];
        System.assertEquals(1, captured.size(), 'The trigger should have created one error log from the batch crash.');
        System.assertEquals('High', captured[0].Severity__c);
        System.assert(captured[0].Correlation_Id__c.startsWith('BATCH-'), 'Batch captures use a job-scoped correlation id.');
    }
}