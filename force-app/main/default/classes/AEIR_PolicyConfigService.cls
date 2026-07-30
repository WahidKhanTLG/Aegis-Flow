/**
 * Resolves the remaining configuration metadata that previously shipped unused:
 * Severity_Rule__mdt, SLA_Policy__mdt, and Surface_Config__mdt (spec section 9).
 *
 * All three are cached per transaction; capture and escalation consult them on every
 * error, so per-call queries would be wasteful.
 */
public with sharing class AEIR_PolicyConfigService {

    private static List<Severity_Rule__mdt> severityCache;
    private static Map<String, SLA_Policy__mdt> slaCache;
    private static Surface_Config__mdt surfaceCache;
    private static Boolean surfaceLoaded = false;

    /** What the utility bar is allowed to do on each surface. */
    public class SurfaceSettings {
        @AuraEnabled public Boolean utilityEnabled;
        @AuraEnabled public Boolean mobileEnabled;
        @AuraEnabled public Boolean experienceEnabled;
        @AuraEnabled public String appName;
    }

    // ---------- Severity_Rule__mdt ----------

    /**
     * Returns a metadata-driven severity, or null when no rule matches so the caller
     * keeps whatever the deterministic classifier decided. Source-specific rules are
     * evaluated before generic ones, and the highest impact score wins a tie.
     */
    public static String resolveSeverity(String sourceType, String message) {
        if (String.isBlank(message)) return null;
        String best = null;
        Decimal bestScore = -1;
        for (Severity_Rule__mdt rule : severityRules()) {
            if (String.isBlank(rule.Pattern__c) || String.isBlank(rule.Severity__c)) continue;
            if (!String.isBlank(rule.Source_Type__c) && !rule.Source_Type__c.equalsIgnoreCase(sourceType)) continue;
            Boolean matched = false;
            try {
                matched = Pattern.compile('(?i)' + rule.Pattern__c).matcher(message).find();
            } catch (Exception badPattern) {
                matched = message.containsIgnoreCase(rule.Pattern__c);
            }
            if (!matched) continue;
            Decimal score = rule.Impact_Score__c == null ? 0 : rule.Impact_Score__c;
            // A source-specific rule outranks a generic rule of equal score.
            if (!String.isBlank(rule.Source_Type__c)) score += 0.5;
            if (score > bestScore) {
                bestScore = score;
                best = rule.Severity__c;
            }
        }
        return best;
    }

    private static List<Severity_Rule__mdt> severityRules() {
        if (severityCache == null) {
            severityCache = [
                SELECT Pattern__c, Severity__c, Source_Type__c, Impact_Score__c, Active__c
                FROM Severity_Rule__mdt WHERE Active__c = true LIMIT 200
            ];
        }
        return severityCache;
    }

    // ---------- SLA_Policy__mdt ----------

    /** Response target for a severity, or null when no policy is configured. */
    public static SLA_Policy__mdt resolveSla(String severity) {
        Map<String, SLA_Policy__mdt> policies = slaPolicies();
        if (String.isBlank(severity)) return policies.get('MEDIUM');
        SLA_Policy__mdt match = policies.get(severity.toUpperCase());
        return match == null ? policies.get('MEDIUM') : match;
    }

    /** Due date derived from the SLA policy; falls back to the previous hardcoded behaviour. */
    public static Datetime resolveSlaDueAt(String severity) {
        SLA_Policy__mdt policy = resolveSla(severity);
        if (policy != null && policy.Response_Minutes__c != null && policy.Response_Minutes__c > 0) {
            return Datetime.now().addMinutes(Integer.valueOf(policy.Response_Minutes__c));
        }
        return Datetime.now().addHours(severity == 'Critical' ? 4 : 24);
    }

    public static String resolveOwnerTeam(String severity) {
        SLA_Policy__mdt policy = resolveSla(severity);
        return policy == null ? null : policy.Owner_Team__c;
    }

    private static Map<String, SLA_Policy__mdt> slaPolicies() {
        if (slaCache == null) {
            slaCache = new Map<String, SLA_Policy__mdt>();
            for (SLA_Policy__mdt policy : [
                SELECT DeveloperName, Severity__c, Response_Minutes__c, Escalation_Minutes__c, Owner_Team__c, Active__c
                FROM SLA_Policy__mdt WHERE Active__c = true LIMIT 200
            ]) {
                if (!String.isBlank(policy.Severity__c)) slaCache.put(policy.Severity__c.toUpperCase(), policy);
            }
        }
        return slaCache;
    }

    // ---------- Surface_Config__mdt ----------

    /** Defaults to enabled when nothing is configured, so an unconfigured org still works. */
    public static SurfaceSettings resolveSurface() {
        if (!surfaceLoaded) {
            List<Surface_Config__mdt> rows = [
                SELECT App_Name__c, Utility_Enabled__c, Mobile_Enabled__c, Experience_Enabled__c, Active__c
                FROM Surface_Config__mdt WHERE Active__c = true LIMIT 1
            ];
            surfaceCache = rows.isEmpty() ? null : rows[0];
            surfaceLoaded = true;
        }
        SurfaceSettings settings = new SurfaceSettings();
        settings.utilityEnabled = surfaceCache == null ? true : surfaceCache.Utility_Enabled__c == true;
        settings.mobileEnabled = surfaceCache == null ? true : surfaceCache.Mobile_Enabled__c == true;
        settings.experienceEnabled = surfaceCache == null ? false : surfaceCache.Experience_Enabled__c == true;
        settings.appName = surfaceCache == null ? null : surfaceCache.App_Name__c;
        return settings;
    }
}