/**
 * Resolves Feature_Flag__mdt so packaged capabilities can be enabled or disabled per
 * customer org without code changes (spec section 9). A feature is on only when its
 * record exists and both Active__c and Enabled__c are true.
 *
 * Flags are cached for the life of the transaction; capture paths consult them on
 * every error, so a per-call query would be wasteful.
 */
public with sharing class AEIR_FeatureFlagService {
    public static final String AI_DIAGNOSIS = 'AI_DIAGNOSIS';
    public static final String USER_NOTIFICATIONS = 'USER_NOTIFICATIONS';
    public static final String GOVERNED_REMEDIATION = 'GOVERNED_REMEDIATION';
    public static final String CONNECTOR_EXTENSIONS = 'CONNECTOR_EXTENSIONS';

    private static Map<String, Boolean> cache;

    /** Test-only override so suites can exercise both enabled and disabled paths. */
    @TestVisible
    private static Map<String, Boolean> overrides = new Map<String, Boolean>();

    public static Boolean isEnabled(String featureKey) {
        if (String.isBlank(featureKey)) return false;
        String key = featureKey.toUpperCase();
        if (overrides.containsKey(key)) return overrides.get(key);
        return flags().containsKey(key) ? flags().get(key) : false;
    }

    /**
     * Unknown keys resolve to false. A capability whose flag record was never packaged
     * stays off rather than silently defaulting on.
     */
    private static Map<String, Boolean> flags() {
        if (cache == null) {
            cache = new Map<String, Boolean>();
            for (Feature_Flag__mdt flag : [
                SELECT Feature_Key__c, Active__c, Enabled__c
                FROM Feature_Flag__mdt
                LIMIT 200
            ]) {
                if (String.isBlank(flag.Feature_Key__c)) continue;
                cache.put(flag.Feature_Key__c.toUpperCase(), flag.Active__c == true && flag.Enabled__c == true);
            }
        }
        return cache;
    }
}