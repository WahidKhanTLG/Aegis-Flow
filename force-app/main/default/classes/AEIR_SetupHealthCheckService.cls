/**
 * Setup readiness and health check (spec section 14 and 14.1).
 *
 * The default check is read-only. The separately requested capture probe creates
 * temporary Aegis diagnostics with follow-up notices/diagnosis suppressed, then reports its
 * cleanup outcome. It does not verify browser delivery or external destinations.
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
        return pass('Onboarding', 'Setup answers have been saved. Effective destinations are checked under Escalation routing; non-email channels do not require a team mailbox.');
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
        return evaluateRoutes([
            SELECT Route_Key__c, Recipient__c, Channel__c, Active__c, Named_Credential__c,
                Endpoint_Path__c, Target__c FROM Escalation_Route__mdt WHERE Active__c = true LIMIT 50
        ]);
    }

    @TestVisible private static CheckResult evaluateRoutes(List<Escalation_Route__mdt> routes) {
        if (routes.isEmpty()) {
            return fail('Escalation routing', 'No active escalation route is configured.',
                        'Create an active Escalation_Route__mdt record for the intended delivery channel.');
        }
        Set<String> channels = new Set<String>();
        Boolean hasEmailRoute = false;
        for (Escalation_Route__mdt route : routes) {
            if (String.isBlank(route.Channel__c) || route.Channel__c == 'Email') hasEmailRoute = true;
        }
        Map<String, AEIR_OrgSetupService.RecipientResolution> defaultRecipients = new Map<String, AEIR_OrgSetupService.RecipientResolution>();
        if (hasEmailRoute) {
            // Administrator fallback can query User. Resolve once per role, not once
            // per route; a large route library must not exhaust the query budget.
            defaultRecipients.put('Developer', AEIR_OrgSetupService.resolveRecipients('Developer', null));
            defaultRecipients.put('Admin', AEIR_OrgSetupService.resolveRecipients('Admin', null));
        }
        for (Escalation_Route__mdt route : routes) {
            String channel = String.isBlank(route.Channel__c) ? 'Email' : route.Channel__c;
            channels.add(channel);
            if (channel == 'Email') {
                // Error escalations use Developer; manual-only sessions use Admin.
                // Both use the same effective-recipient resolver as real dispatch.
                for (String role : new List<String>{ 'Developer', 'Admin' }) {
                    AEIR_OrgSetupService.RecipientResolution effective =
                        String.isBlank(route.Recipient__c) || AEIR_OrgSetupService.isPlaceholder(route.Recipient__c)
                        ? defaultRecipients.get(role)
                        : AEIR_OrgSetupService.resolveRecipients(role, route.Recipient__c);
                    if (effective.recipients.isEmpty()) {
                        return fail('Escalation routing', 'Route ' + route.Route_Key__c + ' cannot resolve a ' + role + ' recipient.',
                            'Configure the corresponding team email, a real route recipient, or administrator fallback.');
                    }
                }
            } else if (channel != 'Case' && channel != 'None') {
                String problem = AEIR_ConnectorDeliveryJob.routeConfigurationError(route);
                if (problem != null) return warn('Escalation routing', 'Route ' + route.Route_Key__c + ': ' + problem,
                    'Configure the channel-specific Named Credential, relative endpoint and non-secret Target metadata.');
            }
        }
        return pass('Escalation routing', routes.size() + ' active route(s); configured channels: '
            + String.join(new List<String>(channels), ', ') + '. Email uses effective team/route/fallback recipients. '
            + 'Configuration only: delivery, Named Credential authentication and Case access require a live channel test.');
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
        return evaluateFlags([SELECT Feature_Key__c, Active__c, Enabled__c FROM Feature_Flag__mdt LIMIT 200]);
    }

    @TestVisible private static CheckResult evaluateFlags(List<Feature_Flag__mdt> flags) {
        List<String> enabled = new List<String>();
        List<String> disabled = new List<String>();
        Boolean notificationsEnabled = false;
        for (Feature_Flag__mdt flag : flags) {
            if (flag.Active__c == true && flag.Enabled__c == true) enabled.add(flag.Feature_Key__c);
            else disabled.add(flag.Feature_Key__c);
            if (flag.Feature_Key__c != null && flag.Feature_Key__c.equalsIgnoreCase('USER_NOTIFICATIONS')) {
                notificationsEnabled = flag.Active__c == true && flag.Enabled__c == true;
            }
        }
        if (!notificationsEnabled) {
            return fail('Feature flags', 'Required USER_NOTIFICATIONS is missing, inactive or disabled.',
                        'Enable and activate USER_NOTIFICATIONS to deliver user notices. Optional features can remain disabled.');
        }
        return pass('Feature flags', 'Enabled: ' + String.join(enabled, ', ') + '. Optional features disabled: '
            + (disabled.isEmpty() ? 'none' : String.join(disabled, ', ')) + '. Enable optional capabilities only after configuring them.');
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
        // A scheduled monitor briefly leaves WAITING when Salesforce acquires or
        // executes it. That normal transition must not recommend duplicate jobs.
        return evaluateScheduledJobs([
            SELECT State, CronJobDetail.Name FROM CronTrigger
            WHERE (CronJobDetail.Name LIKE 'Aegis Flow Interview Monitor%'
                OR CronJobDetail.Name LIKE 'Aegis Flow Async Job Monitor%'
                OR CronJobDetail.Name = 'AEIR Nightly Retention Purge')
                AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING') LIMIT 100
        ]);
    }

    @TestVisible private static CheckResult evaluateScheduledJobs(List<CronTrigger> jobs) {
        Integer flowJobs = 0, asyncJobs = 0, retentionJobs = 0;
        Set<String> activeStates = new Set<String>{ 'WAITING', 'ACQUIRED', 'EXECUTING' };
        for (CronTrigger job : jobs) {
            if (job == null || !activeStates.contains(job.State) || job.CronJobDetail == null) continue;
            String name = job.CronJobDetail.Name;
            if (name != null && name.startsWith('Aegis Flow Interview Monitor')) flowJobs++;
            else if (name != null && name.startsWith('Aegis Flow Async Job Monitor')) asyncJobs++;
            else if (name == 'AEIR Nightly Retention Purge') retentionJobs++;
        }
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
            + ' Aegis schedules active (waiting, acquired or executing): ' + flowJobs
            + ' flow, ' + asyncJobs + ' async, and nightly retention.');
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
     * Opt-in capture probe only; no follow-up notices or diagnosis requests are sent.
     */
    private static CheckResult runEndToEndProbe() {
        String correlationId = 'HEALTHCHECK-' + AEIR_CorrelationIdService.nextId();
        Savepoint probeBoundary;
        CheckResult result;
        try {
            probeBoundary = Database.setSavepoint();
            AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
            input.correlationId = correlationId;
            input.sourceType = 'Manual';
            input.sourceName = 'Aegis Flow Health Check';
            input.originalMessage = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: health check probe';
            input.severity = 'Low';
            AEIR_ErrorCaptureService.CaptureOptions options = new AEIR_ErrorCaptureService.CaptureOptions();
            options.notifyUser = false;
            options.requestDiagnosis = false;
            AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(input, options);
            if (captured.success != true || captured.errorLogId == null) {
                result = fail('Capture probe', correlationId, 'Capture failed: ' + captured.message);
            } else {
                Error_Log__c stored = [SELECT Id, Error_Category__c, Incident__c FROM Error_Log__c WHERE Id = :captured.errorLogId LIMIT 1];
                if (String.isBlank(stored.Error_Category__c)) {
                    result = warn('Capture probe', correlationId, 'Capture worked but no classification was assigned. Check Error_Rule__mdt.');
                } else if (stored.Incident__c == null) {
                    result = warn('Capture probe', correlationId, 'Capture and classification worked but no incident was assigned.');
                } else {
                    result = pass('Capture probe', correlationId);
                    result.remediation = 'Capture, classification and incident grouping verified. Browser notices, asynchronous diagnosis and external delivery were not verified.';
                }
            }
        } catch (Exception ex) {
            result = fail('Capture probe', correlationId, 'Probe failed: ' + AEIR_SecuritySanitizerService.mask(ex.getMessage()));
        } finally {
            if (probeBoundary != null) {
                try {
                    // Restore every probe write, including counters on an existing incident.
                    Database.rollback(probeBoundary);
                    Database.releaseSavepoint(probeBoundary);
                } catch (Exception cleanupFailure) {
                    result = fail('Capture probe', correlationId,
                        'Probe cleanup failed. Temporary diagnostics may remain for this reference; review them before rerunning the probe.');
                    System.debug(LoggingLevel.WARN, 'Aegis Flow: capture-probe rollback/cleanup failed.');
                }
            }
        }
        return result;
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
