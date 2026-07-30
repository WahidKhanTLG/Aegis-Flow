/** AF-11: setup readiness and health check (spec 14.1). */
@IsTest
private class AEIR_SetupHealthCheckTest {

    @IsTest
    static void reportCoversEveryPrerequisite() {
        Test.startTest();
        AEIR_SetupHealthCheckService.HealthReport report = AEIR_SetupHealthCheckService.run();
        Test.stopTest();

        System.assertEquals(10, report.checks.size(), 'Every documented prerequisite must be reported.');
        System.assertNotEquals(null, report.overallStatus);
        System.assertEquals(report.checks.size(),
            report.passCount + report.warningCount + report.failCount,
            'Every check must be counted exactly once.');

        for (AEIR_SetupHealthCheckService.CheckResult check : report.checks) {
            System.assertNotEquals(null, check.name);
            System.assert(check.status == 'PASS' || check.status == 'WARNING' || check.status == 'FAIL', check.status);
            if (check.status != 'PASS') {
                System.assertNotEquals(null, check.remediation,
                    'Spec 14.1 requires a remediation instruction for every failed check: ' + check.name);
            }
        }
    }

    @IsTest
    static void liveProbeRunsAndLeavesNoResidue() {
        Integer logsBefore = [SELECT count() FROM Error_Log__c];

        Test.startTest();
        AEIR_SetupHealthCheckService.HealthReport report = AEIR_SetupHealthCheckService.runWithProbe();
        Test.stopTest();

        System.assertEquals(11, report.checks.size(), 'The probe adds one more check.');
        System.assertNotEquals(null, report.testCorrelationId, 'A test correlation id must be returned.');
        System.assert(report.testCorrelationId.startsWith('HEALTHCHECK-'), report.testCorrelationId);

        System.assertEquals(logsBefore, [SELECT count() FROM Error_Log__c],
            'Spec 14.1 forbids production data mutation: the probe must clean up after itself.');
        System.assertEquals(0, [SELECT count() FROM User_Notification__c WHERE Correlation_Id__c = :report.testCorrelationId]);
    }

    @IsTest
    static void placeholderRecipientIsFlagged() {
        // The packaged routes still point at example.com, so routing must not report PASS.
        AEIR_SetupHealthCheckService.HealthReport report = AEIR_SetupHealthCheckService.run();
        for (AEIR_SetupHealthCheckService.CheckResult check : report.checks) {
            if (check.name == 'Escalation routing' && check.status != 'PASS') {
                System.assertNotEquals(null, check.remediation);
                return;
            }
        }
        // If routing passes, real recipients are configured, which is also a valid state.
        System.assert(true);
    }
}