/**
 * Onboarding configuration and escalation recipient resolution (AF-15).
 *
 * Packaged Escalation_Route__mdt records ship with placeholder addresses, so a fresh
 * install would send findings nowhere. This lets an admin name their own development
 * and administrator teams during onboarding, and guarantees a safe destination when
 * they have not.
 *
 * Recipient resolution order:
 *   1. The team email captured during onboarding
 *   2. The Escalation_Route__mdt recipient, if it is not a placeholder
 *   3. Active System Administrators in this org (Fallback_To_System_Admins__c)
 *   4. The vendor support mailbox, ONLY when the customer explicitly opted in
 *
 * Step 4 is off by default on purpose. Escalation packages carry stack traces, record
 * ids and record snapshots, so routing them to the vendor without informed consent is a
 * data processing decision, not a technical default.
 */
public with sharing class AEIR_OrgSetupService {

    private static final Set<String> PLACEHOLDER_DOMAINS = new Set<String>{ 'example.com', 'example.org', 'example.invalid' };

    public class SetupConfig {
        @AuraEnabled public String companyName;
        @AuraEnabled public String developerTeamEmail;
        @AuraEnabled public String adminTeamEmail;
        @AuraEnabled public Boolean fallbackToSystemAdmins;
        @AuraEnabled public Boolean shareDiagnosticsWithVendor;
        @AuraEnabled public String vendorSupportEmail;
        @AuraEnabled public Boolean onboardingComplete;
        @AuraEnabled public Datetime onboardingCompletedAt;
    }

    public class RecipientResolution {
        @AuraEnabled public List<String> recipients;
        @AuraEnabled public String source;
        @AuraEnabled public Boolean usingFallback;
    }

    @AuraEnabled(cacheable=true)
    public static SetupConfig getConfig() {
        Aegis_Org_Setting__c setting = Aegis_Org_Setting__c.getOrgDefaults();
        SetupConfig config = new SetupConfig();
        config.companyName = setting.Company_Name__c;
        config.developerTeamEmail = setting.Developer_Team_Email__c;
        config.adminTeamEmail = setting.Admin_Team_Email__c;
        config.fallbackToSystemAdmins = setting.Fallback_To_System_Admins__c != false;
        config.shareDiagnosticsWithVendor = setting.Share_Diagnostics_With_Vendor__c == true;
        config.vendorSupportEmail = setting.Vendor_Support_Email__c;
        config.onboardingCompletedAt = setting.Onboarding_Completed_At__c;
        config.onboardingComplete = setting.Onboarding_Completed_At__c != null;
        return config;
    }

    /**
     * Saves onboarding answers. Only a user who can administer the product may call this,
     * because it changes where every future finding is sent.
     */
    @AuraEnabled
    public static SetupConfig saveConfig(String configJson) {
        if (!FeatureManagement.checkPermission('AEIR_Execute_Remediation')
            && !Schema.SObjectType.Aegis_Org_Setting__c.isCreateable()) {
            throw new AuraHandledException('You do not have permission to change Aegis Flow setup.');
        }
        SetupConfig input;
        try {
            input = (SetupConfig) JSON.deserialize(configJson, SetupConfig.class);
        } catch (Exception parseError) {
            throw new AuraHandledException('The setup payload could not be read.');
        }
        if (input == null) throw new AuraHandledException('Setup details are required.');

        List<String> invalid = new List<String>();
        invalid.addAll(invalidAddresses(input.developerTeamEmail));
        invalid.addAll(invalidAddresses(input.adminTeamEmail));
        if (!invalid.isEmpty()) {
            throw new AuraHandledException('These addresses are not valid: ' + String.join(invalid, ', '));
        }
        if (input.shareDiagnosticsWithVendor == true && String.isBlank(input.vendorSupportEmail)) {
            throw new AuraHandledException('A vendor support address is required when vendor sharing is enabled.');
        }

        Aegis_Org_Setting__c setting = Aegis_Org_Setting__c.getOrgDefaults();
        setting.SetupOwnerId = UserInfo.getOrganizationId();
        setting.Company_Name__c = input.companyName;
        setting.Developer_Team_Email__c = normalize(input.developerTeamEmail);
        setting.Admin_Team_Email__c = normalize(input.adminTeamEmail);
        setting.Fallback_To_System_Admins__c = input.fallbackToSystemAdmins != false;
        setting.Share_Diagnostics_With_Vendor__c = input.shareDiagnosticsWithVendor == true;
        setting.Vendor_Support_Email__c = normalize(input.vendorSupportEmail);
        setting.Onboarding_Completed_At__c = Datetime.now();
        setting.Onboarding_Completed_By__c = String.valueOf(UserInfo.getUserId());
        upsert setting;
        return getConfig();
    }

    /**
     * Effective recipients for an escalation. Never returns an empty list unless the org
     * has no active administrator and no configuration at all.
     *
     * @param routeType 'Developer' or 'Admin'
     * @param routeRecipient the recipient from the matched Escalation_Route__mdt
     */
    public static RecipientResolution resolveRecipients(String routeType, String routeRecipient) {
        Aegis_Org_Setting__c setting = Aegis_Org_Setting__c.getOrgDefaults();
        RecipientResolution resolution = new RecipientResolution();
        resolution.usingFallback = false;

        String configured = routeType == 'Admin' ? setting.Admin_Team_Email__c : setting.Developer_Team_Email__c;
        if (!String.isBlank(configured)) {
            resolution.recipients = split(configured);
            resolution.source = 'Configured ' + routeType.toLowerCase() + ' team';
        } else if (!String.isBlank(routeRecipient) && !isPlaceholder(routeRecipient)) {
            resolution.recipients = split(routeRecipient);
            resolution.source = 'Escalation route metadata';
        } else if (setting.Fallback_To_System_Admins__c != false) {
            resolution.recipients = systemAdminEmails();
            resolution.source = 'System administrators (no team configured)';
            resolution.usingFallback = true;
        } else {
            resolution.recipients = new List<String>();
            resolution.source = 'No recipient configured';
            resolution.usingFallback = true;
        }

        // Vendor visibility is additive and only ever when explicitly enabled.
        if (setting.Share_Diagnostics_With_Vendor__c == true && !String.isBlank(setting.Vendor_Support_Email__c)) {
            resolution.recipients.addAll(split(setting.Vendor_Support_Email__c));
            resolution.source += ' + vendor support (opted in)';
        }
        return resolution;
    }

    /** Safety net so a finding is never silently lost on a fresh install. */
    private static List<String> systemAdminEmails() {
        List<String> emails = new List<String>();
        for (User admin : [
            SELECT Email FROM User
            WHERE IsActive = true AND Profile.PermissionsModifyAllData = true AND Email != null
            ORDER BY LastLoginDate DESC NULLS LAST
            LIMIT 5
        ]) {
            emails.add(admin.Email);
        }
        return emails;
    }

    private static List<String> invalidAddresses(String value) {
        List<String> bad = new List<String>();
        for (String address : split(value)) {
            if (!Pattern.matches('^[^@\\s]+@[^@\\s.]+\\.[^@\\s]+$', address)) bad.add(address);
        }
        return bad;
    }

    public static Boolean isPlaceholder(String address) {
        if (String.isBlank(address)) return true;
        String lower = address.toLowerCase();
        for (String domain : PLACEHOLDER_DOMAINS) {
            if (lower.endsWith('@' + domain)) return true;
        }
        return false;
    }

    private static List<String> split(String value) {
        List<String> out = new List<String>();
        if (String.isBlank(value)) return out;
        for (String part : value.split(',')) {
            if (String.isNotBlank(part)) out.add(part.trim());
        }
        return out;
    }

    private static String normalize(String value) {
        List<String> parts = split(value);
        return parts.isEmpty() ? null : String.join(parts, ',');
    }
}