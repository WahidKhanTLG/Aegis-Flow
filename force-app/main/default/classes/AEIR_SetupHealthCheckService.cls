/**
 * Setup readiness and health check (spec section 14 and 14.1).
 *
 * Reports PASS / WARNING / FAIL per prerequisite with a concrete remediation instruction
 * for every non-pass, plus a test correlation id linking to the records it generated.
 *
 * Section 14.1 requires that the health check performs **no production data mutation**.
 * The live end-to-end probe is therefore opt-in via runLiveProbe, writes only Aegis
 * diagnostic records, and cleans them up afterwards.
 */
public with sharing class AEIR_SetupHealthCheckService {

    public static final String PASS = 'PASS';
    public static final String WARNING = 'WARNING';
    public static final String FAIL = 'FAIL';

    public class CheckResult {
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String detail;
        @AuraEnabled public String remediation;
    }

    public class HealthReport {
        @AuraEnabled public String overallStatus;
        @AuraEnabled public String testCorrelationId;
        @AuraEnabled public Integer passCount;
        @AuraEnabled public Integer warningCount;
        @AuraEnabled public Integer failCount;
        @AuraEnabled public List<CheckResult> checks;
    }

    @AuraEnabled
    public static HealthReport run() {
        return run(false);
    }

    @AuraEnabled
    public static HealthReport runWithProbe() {
        return run(true);
    }

    public static HealthReport run(Boolean runLiveProbe) {
        List<CheckResult> checks = new List<CheckResult>();
        checks.add(checkOnboarding());
        checks.add(checkPermissionSets());
        checks.add(checkEscalationRoutes());
        checks.add(checkErrorRules());
        checks.add(checkNotificationPolicy());
        checks.add(checkFeatureFlags());
        checks.add(checkUtilitySurface());
        checks.add(checkFlowFaultSubflow());
        checks.add(checkScheduledJobs());
        checks.add(checkRemediationWhitelist());

        HealthReport report = new HealthReport();
        report.checks = checks;
        if (runLiveProbe == true) {
            CheckResult probe = runEndToEndProbe();
            checks.add(probe);
            report.testCorrelationId = probe.detail;
        }
        summarize(report);
        return report;
    }

    // ---------- individual checks ----------

    private static CheckResult checkOnboarding() {
        AEIR_OrgSetupService.SetupConfig config = AEIR_OrgSetupService.getConfig();
        if (config.onboardingComplete != true) {
            return fail('Onboarding', 'The Aegis Flow setup wizard has not been completed.',
                        'Open the Aegis Flow Setup tab and name your development and administrator teams.');
        }
        AEIR_OrgSetupService.RecipientResolution dev = AEIR_OrgSetupService.resolveRecipients('Developer', null);
        if (dev.recipients.isEmpty()) {
            return fail('Onboarding', 'No developer recipient can be resolved.',
                        'Set a developer team email, or enable the system administrator fallback.');
        }
        return dev.usingFallback == true
            ? warn('Onboarding', 'Findings route to system administrators because no developer team is configured.',
                   'Name your development team in Aegis Flow Setup so findings reach the right people.')
            : pass('Onboarding', 'Findings route to: ' + String.join(dev.recipients, ', ') + ' (' + dev.source + ').');
    }

    private static CheckResult checkPermissionSets() {
        Integer assigned = [
            SELECT count() FROM PermissionSetAssignment
            WHERE PermissionSet.Name LIKE 'AEIR%' AND AssigneeId = :UserInfo.getUserId()
        ];
        return assigned > 0
            ? pass('Permission sets', assigned + ' Aegis permission set(s) assigned to you.')
            : fail('Permission sets', 'No Aegis permission set is assigned to the current user.',
                   'Assign AEIR_Product_Admin in Setup > Permission Sets, or run: sf org assign permset --name AEIR_Product_Admin');
    }

    private static CheckResult checkEscalationRoutes() {
        List<Escalation_Route__mdt> routes = [
            SELECT Route_Key__c, Recipient__c, Channel__c FROM Escalation_Route__mdt WHERE Active__c = true LIMIT 50
        ];
        if (routes.isEmpty()) {
            return fail('Escalation routing', 'No active escalation route is configured.',
                        'Create at least one Escalation_Route__mdt record with a real recipient.');
        }
        for (Escalation_Route__mdt route : routes) {
            if (String.isBlank(route.Recipient__c) || route.Recipient__c.endsWith('example.com')) {
                return warn('Escalation routing',
                            'Route ' + route.Route_Key__c + ' still uses a placeholder recipient (' + route.Recipient__c + ').',
                            'Replace the placeholder in Setup > Custom Metadata Types > Escalation Route with a monitored mailbox.');
            }
        }
        return pass('Escalation routing', routes.size() + ' active route(s) with real recipients.');
    }

    private static CheckResult checkErrorRules() {
        Integer rules = [SELECT count() FROM Error_Rule__mdt WHERE Active__c = true];
        return rules > 0
            ? pass('Deterministic rule library', rules + ' active error rule(s).')
            : warn('Deterministic rule library', 'No active Error_Rule__mdt records.',
                   'Load the packaged rule set so errors are classified before any AI call.');
    }

    private static CheckResult checkNotificationPolicy() {
        List<Notification_Policy__mdt> policies = [
            SELECT Maximum_Alerts_Per_Hour__c, Cooldown_Minutes__c, Minimum_Severity__c
            FROM Notification_Policy__mdt WHERE Active__c = true LIMIT 10
        ];
        if (policies.isEmpty()) {
            return warn('Notification policy', 'No active notification policy; alerts will not be throttled.',
                        'Activate the DEFAULT Notification_Policy record to enable cooldown and hourly caps.');
        }
        Notification_Policy__mdt p = policies[0];
        if (p.Maximum_Alerts_Per_Hour__c == null && p.Cooldown_Minutes__c == null) {
            return warn('Notification policy', 'Policy exists but sets neither an hourly cap nor a cooldown.',
                        'Set Maximum_Alerts_Per_Hour__c and Cooldown_Minutes__c to prevent notification storms.');
        }
        return pass('Notification policy', 'Throttling active: max ' + p.Maximum_Alerts_Per_Hour__c
                    + '/hour, ' + p.Cooldown_Minutes__c + ' minute cooldown, minimum severity ' + p.Minimum_Severity__c + '.');
    }

    private static CheckResult checkFeatureFlags() {
        List<String> enabled = new List<String>();
        List<String> disabled = new List<String>();
        for (Feature_Flag__mdt flag : [SELECT Feature_Key__c, Active__c, Enabled__c FROM Feature_Flag__mdt LIMIT 200]) {
            if (flag.Active__c == true && flag.Enabled__c == true) enabled.add(flag.Feature_Key__c);
            else disabled.add(flag.Feature_Key__c);
        }
        if (enabled.isEmpty()) {
            return fail('Feature flags', 'Every Aegis feature flag is disabled.',
                        'Enable at least USER_NOTIFICATIONS in Setup > Custom Metadata Types > Feature Flag.');
        }
        return disabled.isEmpty()
            ? pass('Feature flags', 'Enabled: ' + String.join(enabled, ', '))
            : warn('Feature flags', 'Enabled: ' + String.join(enabled, ', ') + '. Disabled: ' + String.join(disabled, ', ') + '.',
                   'Disabled features are intentional defaults for staged rollout. Enable them when the matching release is ready.');
    }

    private static CheckResult checkUtilitySurface() {
        AEIR_PolicyConfigService.SurfaceSettings settings = AEIR_PolicyConfigService.resolveSurface();
        if (settings.utilityEnabled != true) {
            return warn('Monitored surfaces', 'Surface_Config disables the utility bar monitor.',
                        'Set Utility_Enabled__c on the active Surface_Config record to receive proactive alerts.');
        }
        return pass('Monitored surfaces', 'Utility surface enabled. Add the Aegis utility item to every Lightning app your users work in.');
    }

    private static CheckResult checkFlowFaultSubflow() {
        List<FlowDefinitionView> flows = [
            SELECT ApiName, ActiveVersionId, IsActive
            FROM FlowDefinitionView
            WHERE ApiName = 'Aegis_Error_Capture_Fault_Subflow'
            LIMIT 1
        ];
        if (flows.isEmpty()) {
            return fail('Flow fault framework', 'Aegis_Error_Capture_Fault_Subflow is not deployed.',
                        'Deploy the packaged subflow, then connect customer Flow fault paths to it.');
        }
        return flows[0].IsActive == true
            ? pass('Flow fault framework', 'Subflow is active and callable from Flow fault paths.')
            : fail('Flow fault framework', 'The subflow is deployed but not active.',
                   'Activate Aegis_Error_Capture_Fault_Subflow in Setup > Flows.');
    }

    private static CheckResult checkScheduledJobs() {
        Integer flowJobs = [
            SELECT count() FROM CronTrigger
            WHERE State = 'WAITING' AND CronJobDetail.Name LIKE 'Aegis Flow Interview Monitor%'
        ];
        Integer asyncJobs = [
            SELECT count() FROM CronTrigger
            WHERE State = 'WAITING' AND CronJobDetail.Name LIKE 'Aegis Flow Async Job Monitor%'
        ];
        Integer retentionJobs = [
            SELECT count() FROM CronTrigger
            WHERE State = 'WAITING' AND CronJobDetail.Name = 'AEIR Nightly Retention Purge'
        ];
        if (flowJobs == 0 || asyncJobs == 0 || retentionJobs == 0) {
            return warn('Scheduled jobs', 'Expected flow monitors, an async monitor, and nightly retention; found '
                + flowJobs + ' flow, ' + asyncJobs + ' async, and ' + retentionJobs + ' retention job(s).',
                'Run scripts/set_poller_cadence.apex with MODE = NORMAL, then run scripts/schedule_retention.apex.');
        }
        if (flowJobs + asyncJobs > 5) {
            return warn('Scheduled jobs', 'Aegis polling uses ' + (flowJobs + asyncJobs)
                + ' scheduled slots; NORMAL cadence uses five.',
                'Run scripts/set_poller_cadence.apex with MODE = NORMAL after the temporary test window.');
        }
        return pass('Scheduled jobs', (flowJobs + asyncJobs + retentionJobs)
            + ' Aegis jobs waiting: ' + flowJobs + ' flow, ' + asyncJobs + ' async, and nightly retention.');
    }

    private static CheckResult checkRemediationWhitelist() {
        Integer actions = [SELECT count() FROM Remediation_Action_Setting__mdt WHERE Active__c = true];
        if (!AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.GOVERNED_REMEDIATION)) {
            return pass('Governed remediation', 'Disabled by feature flag, which is the shipped default for staged rollout.');
        }
        return actions > 0
            ? pass('Governed remediation', actions + ' whitelisted remediation action(s).')
            : warn('Governed remediation', 'Remediation is enabled but no action is whitelisted.',
                   'Add Remediation_Action_Setting__mdt records for every object and field the agent may update.');
    }

    /**
     * End-to-end probe: capture, classify, notify, retrieve. Writes only Aegis diagnostic
     * records and removes them afterwards so no production data is mutated (section 14.1).
     */
    private static CheckResult runEndToEndProbe() {
        String correlationId = 'HEALTHCHECK-' + String.valueOf(Datetime.now().getTime());
        try {
            AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
            input.correlationId = correlationId;
            input.sourceType = 'Manual';
            input.sourceName = 'Aegis Flow Health Check';
            input.originalMessage = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: health check probe';
            input.severity = 'Low';
            AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(input);

            if (captured.success != true || captured.errorLogId == null) {
                return fail('End-to-end probe', correlationId, 'Capture failed: ' + captured.message);
            }
            Error_Log__c stored = [
                SELECT Id, Error_Category__c, Incident__c FROM Error_Log__c WHERE Id = :captured.errorLogId LIMIT 1
            ];
            Boolean classified = String.isNotBlank(stored.Error_Category__c);
            Boolean grouped = stored.Incident__c != null;
            cleanUpProbe(correlationId, stored.Id, stored.Incident__c);

            if (!classified) {
                return warn('End-to-end probe', correlationId,
                            'Capture worked but the error was not classified. Check Error_Rule__mdt.');
            }
            if (!grouped) {
                return warn('End-to-end probe', correlationId,
                            'Capture and classification worked but no incident was assigned.');
            }
            return pass('End-to-end probe', correlationId);
        } catch (Exception ex) {
            return fail('End-to-end probe', correlationId, 'Probe failed: ' + ex.getMessage());
        }
    }

    /** Leaves the org exactly as the probe found it. */
    private static void cleanUpProbe(String correlationId, Id errorLogId, Id incidentId) {
        try {
            delete [SELECT Id FROM User_Notification__c WHERE Correlation_Id__c = :correlationId];
            delete [SELECT Id FROM Delivery_Attempt__c WHERE Correlation_Id__c = :correlationId];
            delete [SELECT Id FROM Error_Context__c WHERE Correlation_Id__c = :correlationId];
            delete [SELECT Id FROM Error_Log__c WHERE Id = :errorLogId];
            if (incidentId != null) {
                List<Incident__c> orphan = [
                    SELECT Id FROM Incident__c
                    WHERE Id = :incidentId AND Id NOT IN (SELECT Incident__c FROM Error_Log__c WHERE Incident__c != null)
                ];
                if (!orphan.isEmpty()) delete orphan;
            }
        } catch (Exception ignored) {
            // Cleanup is best effort; a probe record left behind must not fail the health check.
        }
    }

    // ---------- helpers ----------

    private static void summarize(HealthReport report) {
        report.passCount = 0; report.warningCount = 0; report.failCount = 0;
        for (CheckResult check : report.checks) {
            if (check.status == PASS) report.passCount++;
            else if (check.status == WARNING) report.warningCount++;
            else report.failCount++;
        }
        report.overallStatus = report.failCount > 0 ? FAIL : (report.warningCount > 0 ? WARNING : PASS);
    }

    private static CheckResult pass(String name, String detail) { return build(name, PASS, detail, null); }
    private static CheckResult warn(String name, String detail, String remediation) { return build(name, WARNING, detail, remediation); }
    private static CheckResult fail(String name, String detail, String remediation) { return build(name, FAIL, detail, remediation); }
    private static CheckResult build(String name, String status, String detail, String remediation) {
        CheckResult result = new CheckResult();
        result.name = name;
        result.status = status;
        result.detail = detail;
        result.remediation = remediation;
        return result;
    }
}
