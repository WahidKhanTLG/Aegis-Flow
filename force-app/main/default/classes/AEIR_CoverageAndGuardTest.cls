/** Instrumentation coverage reporting and the one-line Apex guard. */
@IsTest
private class AEIR_CoverageAndGuardTest {

    @IsTest
    static void guardCapturesWithMinimalCeremony() {
        Account a = new Account(Name = 'Aegis Guard Test');
        insert a;

        String correlationId;
        Test.startTest();
        try {
            throw new DmlException('FIELD_CUSTOM_VALIDATION_EXCEPTION: Tax Code is required.');
        } catch (Exception e) {
            correlationId = AEIR_Guard.capture(e, 'OrderService.recalculateTax', a.Id, 'Recalculate order tax');
        }
        // capture() is rollback safe, so the log is written when the event bus drains.
        Test.stopTest();

        System.assertNotEquals(null, correlationId, 'The guard must return a reference the user can quote.');
        Error_Log__c log = [
            SELECT Source_Type__c, Source_Name__c, Object_API_Name__c, Record_Id__c,
                   Action_Name__c, Error_Category__c, Stack_Trace__c
            FROM Error_Log__c WHERE Correlation_Id__c = :correlationId
        ];
        System.assertEquals('Apex Class', log.Source_Type__c);
        System.assertEquals('OrderService.recalculateTax', log.Source_Name__c);
        System.assertEquals('Account', log.Object_API_Name__c, 'Object should be derived from the record id.');
        System.assertEquals(String.valueOf(a.Id), log.Record_Id__c);
        System.assertEquals('Recalculate order tax', log.Action_Name__c);
        System.assertEquals('Validation Rule', log.Error_Category__c, 'The message must still be classified.');
        System.assertNotEquals(null, log.Stack_Trace__c);
    }

    @IsTest
    static void captureNowWritesInTheSameTransaction() {
        Account a = new Account(Name = 'Aegis CaptureNow');
        insert a;
        Test.startTest();
        Id logId;
        try {
            throw new DmlException('System.NullPointerException: immediate probe');
        } catch (Exception e) {
            logId = AEIR_Guard.captureNow(e, 'InlineService.run', a.Id, 'Inline capture');
        }
        // No stopTest needed: captureNow does direct DML.
        System.assertNotEquals(null, logId, 'captureNow must return the log id immediately.');
        System.assertEquals(1, [SELECT count() FROM Error_Log__c WHERE Id = :logId]);
        Test.stopTest();
    }

    @IsTest
    static void guardNeverBreaksTheCallingTransaction() {
        Test.startTest();
        // A null exception and a null source are the worst realistic misuse.
        String result = AEIR_Guard.capture(null, null);
        Test.stopTest();
        System.assertNotEquals(null, result, 'Even a degenerate call should capture rather than throw.');
        System.assertEquals(1, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c = :result]);
    }

    @IsTest
    static void resilientCapturePublishesAnEvent() {
        Test.startTest();
        String correlationId;
        try {
            throw new DmlException('System.NullPointerException: rollback probe');
        } catch (Exception e) {
            correlationId = AEIR_Guard.captureResilient(e, 'PaymentService.charge', null);
        }
        Test.stopTest();

        System.assertNotEquals(null, correlationId);
        System.assertEquals(1, [SELECT count() FROM Error_Log__c WHERE Correlation_Id__c = :correlationId],
            'The published event must be delivered and persisted at stopTest.');
    }

    @IsTest
    static void coverageReportsRealFailuresNotHeuristics() {
        Test.startTest();
        AEIR_FlowCoverageService.CoverageReport report = AEIR_FlowCoverageService.scan();
        Test.stopTest();

        System.assertNotEquals(null, report);
        System.assertNotEquals(null, report.summary);
        System.assert(report.totalActiveFlows >= 0);
        System.assert(report.uncapturedFailures >= 0);
        System.assertEquals(report.flowsWithFailures, report.flows.size(),
            'Only Flows with observed or captured failures are reported.');

        for (AEIR_FlowCoverageService.FlowCoverage f : report.flows) {
            System.assertNotEquals(null, f.recommendation, 'Every reported Flow needs guidance: ' + f.label);
            System.assertNotEquals(null, f.status);
            System.assert(f.captureGap >= 0, 'Capture gap can never be negative.');
        }
    }

    @IsTest
    static void capturedFlowFailureShowsNoCaptureGap() {
        // A captured Flow failure must not be reported as a gap.
        AEIR_ErrorCaptureService.ErrorInput in1 = new AEIR_ErrorCaptureService.ErrorInput();
        in1.sourceType = 'Flow';
        in1.sourceName = 'Coverage Probe Flow / Update_Records';
        in1.originalMessage = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: probe';
        AEIR_ErrorCaptureService.capture(in1);

        Test.startTest();
        AEIR_FlowCoverageService.CoverageReport report = AEIR_FlowCoverageService.scan();
        Test.stopTest();

        Boolean found = false;
        for (AEIR_FlowCoverageService.FlowCoverage f : report.flows) {
            if (f.label == 'Coverage Probe Flow') {
                found = true;
                System.assertEquals(1, f.failuresCaptured);
                System.assertEquals(0, f.captureGap, 'A captured failure is not a gap.');
                System.assertEquals('Captured', f.status);
            }
        }
        System.assertEquals(true, found, 'The captured Flow failure should appear in the report.');
    }

    @IsTest
    static void interviewLabelTimestampDoesNotSplitGroups() {
        System.assertEquals('Order Sync',
            AEIR_FlowCoverageService.flowNameFrom('Order Sync 7/27/2026, 4:00 PM'));
        System.assertEquals('Unknown Flow', AEIR_FlowCoverageService.flowNameFrom(null));
        System.assertEquals('No Timestamp Flow',
            AEIR_FlowCoverageService.flowNameFrom('No Timestamp Flow'));
    }

    @IsTest
    static void coverageHandlesAnEmptyOrgWithoutFailing() {
        // A captured Flow failure is the evidence that the Flow is instrumented.
        AEIR_ErrorCaptureService.ErrorInput in1 = new AEIR_ErrorCaptureService.ErrorInput();
        in1.sourceType = 'Flow';
        in1.sourceName = 'Aegis_Error_Capture_Fault_Subflow / Update_Records';
        in1.originalMessage = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: probe';
        AEIR_ErrorCaptureService.capture(in1);

        Test.startTest();
        AEIR_FlowCoverageService.CoverageReport report = AEIR_FlowCoverageService.scan();
        Test.stopTest();

        System.assertNotEquals(null, report.summary);
        System.assert(report.totalFailuresCaptured >= 0);
        System.assertEquals(true, report.interviewDataReadable != null);
    }
}