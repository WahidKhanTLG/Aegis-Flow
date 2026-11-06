/** AF-11: setup readiness and health check (spec 14.1). */
@IsTest
private class AEIR_SetupHealthCheckTest {

    private static CronTrigger scheduled(String name, String state) {
        return (CronTrigger)JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'State' => state, 'CronJobDetail' => new Map<String, Object>{ 'Name' => name }
        }), CronTrigger.class);
    }

    @IsTest
    static void acquiredAndExecutingSchedulesRemainHealthy() {
        List<CronTrigger> jobs = new List<CronTrigger>{
            scheduled('Aegis Flow Interview Monitor 0', 'WAITING'),
            scheduled('Aegis Flow Interview Monitor 15', 'ACQUIRED'),
            scheduled('Aegis Flow Interview Monitor 30', 'EXECUTING'),
            scheduled('Aegis Flow Interview Monitor 45', 'WAITING'),
            scheduled('Aegis Flow Async Job Monitor 15', 'EXECUTING'),
            scheduled('AEIR Nightly Retention Purge', 'WAITING')
        };
        AEIR_SetupHealthCheckService.CheckResult result = AEIR_SetupHealthCheckService.evaluateScheduledJobs(jobs);
        System.assertEquals('PASS', result.status);
        System.assert(result.detail.contains('6 Aegis schedules active'));
    }

    @IsTest
    static void pausedOrFailedSchedulesDoNotHideAMissingMonitor() {
        AEIR_SetupHealthCheckService.CheckResult result = AEIR_SetupHealthCheckService.evaluateScheduledJobs(
            new List<CronTrigger>{ scheduled('Aegis Flow Interview Monitor 0', 'WAITING'),
                scheduled('Aegis Flow Async Job Monitor 15', 'PAUSED'),
                scheduled('Aegis Flow Async Job Monitor 30', 'ERROR'),
                scheduled('AEIR Nightly Retention Purge', 'COMPLETE') });
        System.assertEquals('WARNING', result.status);
        System.assert(result.detail.contains('0 async, and 0 retention'));
    }

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
        Integer incidentsBefore = [SELECT count() FROM Incident__c];
        Integer attemptsBefore = [SELECT count() FROM Delivery_Attempt__c];
        Integer diagnosesBefore = [SELECT count() FROM AI_Diagnosis__c];

        Test.startTest();
        AEIR_SetupHealthCheckService.HealthReport report = AEIR_SetupHealthCheckService.runWithProbe();
        Test.stopTest();

        System.assertEquals(11, report.checks.size(), 'The probe adds one more check.');
        System.assertNotEquals(null, report.testCorrelationId, 'A test correlation id must be returned.');
        System.assert(report.testCorrelationId.startsWith('HEALTHCHECK-'), report.testCorrelationId);

        System.assertEquals(logsBefore, [SELECT count() FROM Error_Log__c],
            'Spec 14.1 forbids production data mutation: the probe must clean up after itself.');
        System.assertEquals(0, [SELECT count() FROM User_Notification__c WHERE Correlation_Id__c = :report.testCorrelationId]);
        System.assertEquals(incidentsBefore, [SELECT count() FROM Incident__c], 'The savepoint restores incident grouping writes.');
        System.assertEquals(attemptsBefore, [SELECT count() FROM Delivery_Attempt__c], 'Probe suppresses follow-up notification and diagnosis work.');
        System.assertEquals(diagnosesBefore, [SELECT count() FROM AI_Diagnosis__c]);
    }

    @IsTest
    static void defaultCheckDoesNotWriteAndOptionalFlagsAreInformational() {
        Integer beforeDml = Limits.getDmlStatements();
        AEIR_SetupHealthCheckService.run();
        System.assertEquals(beforeDml, Limits.getDmlStatements(), 'Default health checks must be read-only.');
        AEIR_SetupHealthCheckService.CheckResult flags = AEIR_SetupHealthCheckService.evaluateFlags(new List<Feature_Flag__mdt>{
            new Feature_Flag__mdt(Feature_Key__c='USER_NOTIFICATIONS', Active__c=true, Enabled__c=true),
            new Feature_Flag__mdt(Feature_Key__c='AI_DIAGNOSIS', Active__c=true, Enabled__c=false),
            new Feature_Flag__mdt(Feature_Key__c='GOVERNED_REMEDIATION', Active__c=true, Enabled__c=false)
        });
        System.assertEquals('PASS', flags.status, 'Intentionally disabled optional capabilities are not setup failures.');
        System.assert(flags.detail.contains('AI_DIAGNOSIS'));
        System.assertEquals('FAIL', AEIR_SetupHealthCheckService.evaluateFlags(new List<Feature_Flag__mdt>()).status);
        System.assertEquals('FAIL', AEIR_SetupHealthCheckService.evaluateFlags(new List<Feature_Flag__mdt>{
            new Feature_Flag__mdt(Feature_Key__c='USER_NOTIFICATIONS', Active__c=false, Enabled__c=true),
            new Feature_Flag__mdt(Feature_Key__c='AI_DIAGNOSIS', Active__c=true, Enabled__c=true)
        }).status, 'An enabled optional flag cannot conceal missing required notices.');
    }

    @IsTest
    static void routingUsesEffectiveEmailAndChannelSpecificConfiguration() {
        insert new Aegis_Org_Setting__c(SetupOwnerId=UserInfo.getOrganizationId(),
            Developer_Team_Email__c='developer@customer.test', Admin_Team_Email__c='admin@customer.test',
            Fallback_To_System_Admins__c=false);
        Escalation_Route__mdt email = new Escalation_Route__mdt(Route_Key__c='EMAIL', Channel__c='Email', Active__c=true,
            Recipient__c='placeholder@example.com');
        System.assertEquals('PASS', AEIR_SetupHealthCheckService.evaluateRoutes(new List<Escalation_Route__mdt>{email}).status,
            'Configured teams replace placeholder metadata exactly as real delivery does.');
        Escalation_Route__mdt localRoute = new Escalation_Route__mdt(Route_Key__c='LOCAL_CASE', Channel__c='Case', Active__c=true);
        System.assertEquals('PASS', AEIR_SetupHealthCheckService.evaluateRoutes(new List<Escalation_Route__mdt>{localRoute}).status);
        localRoute.Channel__c='None';
        System.assertEquals('PASS', AEIR_SetupHealthCheckService.evaluateRoutes(new List<Escalation_Route__mdt>{localRoute}).status);
        Escalation_Route__mdt connector = new Escalation_Route__mdt(Route_Key__c='SLACK', Channel__c='Slack', Active__c=true);
        System.assertEquals('WARNING', AEIR_SetupHealthCheckService.evaluateRoutes(new List<Escalation_Route__mdt>{connector}).status);
        connector.Named_Credential__c='Aegis_Slack';
        connector.Target__c='{"channelId":"C12345"}';
        System.assertEquals('PASS', AEIR_SetupHealthCheckService.evaluateRoutes(new List<Escalation_Route__mdt>{connector}).status,
            'A connector needs validated destination metadata, not an email Recipient.');
        System.assertEquals('FAIL', AEIR_SetupHealthCheckService.evaluateRoutes(new List<Escalation_Route__mdt>()).status);
        Aegis_Org_Setting__c config=Aegis_Org_Setting__c.getOrgDefaults();
        config.Developer_Team_Email__c=null; config.Admin_Team_Email__c=null; update config;
        System.assertEquals('FAIL', AEIR_SetupHealthCheckService.evaluateRoutes(new List<Escalation_Route__mdt>{email}).status,
            'No configured team, real recipient or fallback is a genuine delivery configuration failure.');
    }
}
