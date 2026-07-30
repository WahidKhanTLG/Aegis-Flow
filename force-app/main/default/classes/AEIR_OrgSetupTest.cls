/** AF-15: onboarding configuration and escalation recipient fallback chain. */
@IsTest
private class AEIR_OrgSetupTest {

    private static String cfg(String dev, String admin, Boolean fallback, Boolean vendor, String vendorEmail) {
        AEIR_OrgSetupService.SetupConfig c = new AEIR_OrgSetupService.SetupConfig();
        c.companyName = 'Contoso';
        c.developerTeamEmail = dev;
        c.adminTeamEmail = admin;
        c.fallbackToSystemAdmins = fallback;
        c.shareDiagnosticsWithVendor = vendor;
        c.vendorSupportEmail = vendorEmail;
        return JSON.serialize(c);
    }

    @IsTest
    static void configuredTeamWinsOverPackagedPlaceholder() {
        Test.startTest();
        AEIR_OrgSetupService.saveConfig(cfg('dev@contoso.com,lead@contoso.com', 'ops@contoso.com', true, false, null));
        AEIR_OrgSetupService.RecipientResolution r =
            AEIR_OrgSetupService.resolveRecipients('Developer', 'devteam@example.com');
        Test.stopTest();

        System.assertEquals(2, r.recipients.size(), 'Both configured addresses must be used.');
        System.assert(r.recipients.contains('dev@contoso.com'));
        System.assertEquals(false, r.usingFallback);
        System.assert(!r.recipients.contains('devteam@example.com'), 'The placeholder must be replaced.');
    }

    @IsTest
    static void placeholderFallsBackToSystemAdministrators() {
        AEIR_OrgSetupService.saveConfig(cfg(null, null, true, false, null));

        Test.startTest();
        AEIR_OrgSetupService.RecipientResolution r =
            AEIR_OrgSetupService.resolveRecipients('Developer', 'devteam@example.com');
        Test.stopTest();

        System.assertEquals(true, r.usingFallback, 'A placeholder address must trigger the safety net.');
        System.assert(!r.recipients.isEmpty(), 'System administrators must receive findings by default.');
        System.assert(r.source.contains('System administrators'), r.source);
    }

    @IsTest
    static void vendorSharingIsOffByDefaultAndAdditiveWhenEnabled() {
        AEIR_OrgSetupService.saveConfig(cfg('dev@contoso.com', null, true, false, null));
        AEIR_OrgSetupService.RecipientResolution off =
            AEIR_OrgSetupService.resolveRecipients('Developer', null);
        System.assertEquals(1, off.recipients.size(), 'Vendor must not receive anything by default.');

        Test.startTest();
        AEIR_OrgSetupService.saveConfig(cfg('dev@contoso.com', null, true, true, 'support@aegisflow.com'));
        AEIR_OrgSetupService.RecipientResolution optedIn =
            AEIR_OrgSetupService.resolveRecipients('Developer', null);
        Test.stopTest();

        System.assertEquals(2, optedIn.recipients.size(), 'Opting in adds the vendor without replacing the team.');
        System.assert(optedIn.recipients.contains('support@aegisflow.com'));
        System.assert(optedIn.source.contains('opted in'), optedIn.source);
    }

    @IsTest
    static void invalidAddressesAreRejected() {
        Boolean threw = false;
        Test.startTest();
        try {
            AEIR_OrgSetupService.saveConfig(cfg('not-an-email', null, true, false, null));
        } catch (Exception ex) { threw = true; }
        Test.stopTest();
        System.assertEquals(true, threw, 'A malformed address must be rejected before it is saved.');
    }

    @IsTest
    static void vendorSharingRequiresAnAddress() {
        Boolean threw = false;
        try {
            AEIR_OrgSetupService.saveConfig(cfg('dev@contoso.com', null, true, true, null));
        } catch (Exception ex) { threw = true; }
        System.assertEquals(true, threw, 'Vendor sharing cannot be enabled without a destination.');
    }

    @IsTest
    static void onboardingStateIsReportedAndHealthCheckReflectsIt() {
        AEIR_OrgSetupService.SetupConfig before = AEIR_OrgSetupService.getConfig();
        System.assertEquals(false, before.onboardingComplete, 'A fresh org has not been onboarded.');

        Test.startTest();
        AEIR_OrgSetupService.saveConfig(cfg('dev@contoso.com', 'ops@contoso.com', true, false, null));
        AEIR_OrgSetupService.SetupConfig after = AEIR_OrgSetupService.getConfig();
        AEIR_SetupHealthCheckService.HealthReport report = AEIR_SetupHealthCheckService.run();
        Test.stopTest();

        System.assertEquals(true, after.onboardingComplete);
        System.assertEquals('Contoso', after.companyName);
        Boolean sawOnboarding = false;
        for (AEIR_SetupHealthCheckService.CheckResult c : report.checks) {
            if (c.name == 'Onboarding') {
                sawOnboarding = true;
                System.assertEquals('PASS', c.status, c.detail);
            }
        }
        System.assertEquals(true, sawOnboarding, 'The health check must report onboarding state.');
    }

    @IsTest
    static void escalationUsesTheConfiguredTeam() {
        AEIR_OrgSetupService.saveConfig(cfg('dev@contoso.com', 'ops@contoso.com', true, false, null));
        AEIR_ErrorCaptureService.ErrorInput in1 = new AEIR_ErrorCaptureService.ErrorInput();
        in1.sourceType = 'Apex Class';
        in1.sourceName = 'RoutingTest';
        in1.originalMessage = 'System.NullPointerException: routing probe';
        in1.severity = 'High';
        AEIR_ErrorCaptureService.CaptureResult captured = AEIR_ErrorCaptureService.capture(in1);

        Test.startTest();
        AEIR_EscalationService.EscalationResult res =
            AEIR_EscalationService.createForError(captured.errorLogId, null, false);
        Test.stopTest();

        Developer_Escalation__c esc = [SELECT Recipient__c FROM Developer_Escalation__c WHERE Id = :res.escalationId];
        System.assert(esc.Recipient__c.contains('contoso.com'),
            'The escalation must target the configured team, not the packaged placeholder: ' + esc.Recipient__c);
    }
}