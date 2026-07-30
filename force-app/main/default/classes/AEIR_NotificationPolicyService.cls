/**
 * Applies Notification_Policy__mdt before any user alert is created (spec section 9.1).
 *
 * Without this the product notifies on every captured error, so a single failing batch
 * or record-triggered Flow alerts the affected user once per failed row. The mandatory
 * scenario matrix (section 20.1) requires that a user who dismisses an alert does not
 * receive repeated alerts during the cooldown window.
 *
 * Four gates are enforced, in increasing cost order:
 *   1. Notify_Affected_User__c  - is user notification wanted at all
 *   2. Minimum_Severity__c      - is this error severe enough
 *   3. Cooldown_Minutes__c      - has this user been alerted too recently
 *   4. Maximum_Alerts_Per_Hour__c - has this user hit their hourly ceiling
 *
 * Critical_Mode__c allows severity/cooldown/cap to be bypassed so a Critical failure is
 * never suppressed by a storm of lower-severity noise.
 */
public with sharing class AEIR_NotificationPolicyService {

    private static final Map<String, Integer> SEVERITY_RANK = new Map<String, Integer>{
        'LOW' => 1, 'MEDIUM' => 2, 'HIGH' => 3, 'CRITICAL' => 4
    };
    private static final Integer DEFAULT_RANK = 2;

    private static Map<String, Notification_Policy__mdt> policyCache;

    /** How the utility bar should behave when an alert arrives (spec 9.1). */
    public class AlertBehavior {
        @AuraEnabled public Boolean autoOpenUtility;
        @AuraEnabled public Boolean allowDismissal;
        @AuraEnabled public String autoOpenMinimumSeverity;
    }

    /**
     * Auto-open interrupts the user, so it is deliberately conservative: only when the
     * policy enables it, and only at or above the configured minimum severity.
     */
    public static AlertBehavior getAlertBehavior() {
        Notification_Policy__mdt policy = resolvePolicy(null);
        AlertBehavior behavior = new AlertBehavior();
        behavior.autoOpenUtility = policy != null && policy.Auto_Open_Utility__c == true;
        behavior.allowDismissal = policy == null || policy.Allow_Dismissal__c != false;
        behavior.autoOpenMinimumSeverity = policy == null || String.isBlank(policy.Minimum_Severity__c)
            ? 'High' : policy.Minimum_Severity__c;
        return behavior;
    }

    /** Outcome for one candidate notification, including why it was suppressed. */
    public class Decision {
        public Boolean allowed;
        public String reason;
        private Decision(Boolean allowed, String reason) {
            this.allowed = allowed;
            this.reason = reason;
        }
    }

    /**
     * Evaluates a batch of candidate logs together. Recent-notification history is read
     * once for all target users rather than per log, so this stays bulk-safe inside a
     * platform event subscriber.
     *
     * @return decision keyed by Error_Log__c.Id
     */
    public static Map<Id, Decision> evaluate(List<Error_Log__c> logs) {
        Map<Id, Decision> decisions = new Map<Id, Decision>();
        if (logs == null || logs.isEmpty()) return decisions;

        if (!AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.USER_NOTIFICATIONS)) {
            for (Error_Log__c log : logs) {
                if (log != null && log.Id != null) {
                    decisions.put(log.Id, new Decision(false, 'User notifications are disabled by feature flag.'));
                }
            }
            return decisions;
        }

        Datetime nowValue = Datetime.now();
        Set<Id> userIds = new Set<Id>();
        for (Error_Log__c log : logs) {
            if (log != null && log.User__c != null) userIds.add(log.User__c);
        }

        // One query covers both the cooldown window and the hourly ceiling.
        Datetime windowStart = nowValue.addHours(-1);
        Map<Id, List<Datetime>> recentByUser = new Map<Id, List<Datetime>>();
        if (!userIds.isEmpty()) {
            for (User_Notification__c existing : [
                SELECT Target_User__c, CreatedDate
                FROM User_Notification__c
                WHERE Target_User__c IN :userIds AND CreatedDate >= :windowStart
                ORDER BY CreatedDate DESC
                LIMIT 2000
            ]) {
                if (!recentByUser.containsKey(existing.Target_User__c)) {
                    recentByUser.put(existing.Target_User__c, new List<Datetime>());
                }
                recentByUser.get(existing.Target_User__c).add(existing.CreatedDate);
            }
        }

        // Notifications created earlier in this same evaluation still count toward the caps.
        Map<Id, Integer> grantedThisRun = new Map<Id, Integer>();
        Map<Id, Datetime> lastGrantThisRun = new Map<Id, Datetime>();

        for (Error_Log__c log : logs) {
            if (log == null || log.Id == null) continue;
            Decision decision = decide(log, nowValue, recentByUser, grantedThisRun, lastGrantThisRun);
            decisions.put(log.Id, decision);
            if (decision.allowed && log.User__c != null) {
                grantedThisRun.put(log.User__c, granted(grantedThisRun, log.User__c) + 1);
                lastGrantThisRun.put(log.User__c, nowValue);
            }
        }
        return decisions;
    }

    private static Decision decide(
        Error_Log__c log,
        Datetime nowValue,
        Map<Id, List<Datetime>> recentByUser,
        Map<Id, Integer> grantedThisRun,
        Map<Id, Datetime> lastGrantThisRun
    ) {
        if (log.User__c == null) return new Decision(false, 'No affected user is associated with this error.');

        Notification_Policy__mdt policy = resolvePolicy(log.Source_Type__c);
        if (policy == null) return new Decision(true, 'No active policy configured; default allow.');
        if (policy.Notify_Affected_User__c == false) {
            return new Decision(false, 'Policy does not notify the affected user.');
        }

        Boolean isCritical = rank(log.Severity__c) >= SEVERITY_RANK.get('CRITICAL');
        Boolean bypass = isCritical && policy.Critical_Mode__c != null && policy.Critical_Mode__c != 'Suppress';
        if (bypass) return new Decision(true, 'Critical severity bypasses throttling.');

        if (policy.Minimum_Severity__c != null && rank(log.Severity__c) < rank(policy.Minimum_Severity__c)) {
            return new Decision(false, 'Severity ' + log.Severity__c + ' is below the policy minimum of ' + policy.Minimum_Severity__c + '.');
        }

        List<Datetime> recent = recentByUser.containsKey(log.User__c) ? recentByUser.get(log.User__c) : new List<Datetime>();

        if (policy.Cooldown_Minutes__c != null && policy.Cooldown_Minutes__c > 0) {
            Datetime cooldownStart = nowValue.addMinutes(-Integer.valueOf(policy.Cooldown_Minutes__c));
            if (lastGrantThisRun.containsKey(log.User__c) && lastGrantThisRun.get(log.User__c) >= cooldownStart) {
                return new Decision(false, 'Within the ' + policy.Cooldown_Minutes__c + ' minute notification cooldown.');
            }
            for (Datetime created : recent) {
                if (created >= cooldownStart) {
                    return new Decision(false, 'Within the ' + policy.Cooldown_Minutes__c + ' minute notification cooldown.');
                }
            }
        }

        if (policy.Maximum_Alerts_Per_Hour__c != null && policy.Maximum_Alerts_Per_Hour__c > 0) {
            Integer used = recent.size() + granted(grantedThisRun, log.User__c);
            if (used >= policy.Maximum_Alerts_Per_Hour__c) {
                return new Decision(false, 'Hourly alert limit of ' + policy.Maximum_Alerts_Per_Hour__c + ' reached for this user.');
            }
        }

        return new Decision(true, 'Allowed by notification policy.');
    }

    /** Source-specific policy wins over DEFAULT so one noisy surface can be tuned alone. */
    private static Notification_Policy__mdt resolvePolicy(String sourceType) {
        Map<String, Notification_Policy__mdt> policies = policies();
        if (!String.isBlank(sourceType) && policies.containsKey(sourceType.toUpperCase())) {
            return policies.get(sourceType.toUpperCase());
        }
        return policies.get('DEFAULT');
    }

    private static Map<String, Notification_Policy__mdt> policies() {
        if (policyCache == null) {
            policyCache = new Map<String, Notification_Policy__mdt>();
            for (Notification_Policy__mdt policy : [
                SELECT DeveloperName, Source_Type__c, Active__c, Notify_Affected_User__c, Notify_Admin__c, Auto_Open_Utility__c,
                       Minimum_Severity__c, Minimum_Confidence__c, Cooldown_Minutes__c,
                       Maximum_Alerts_Per_Hour__c, Critical_Mode__c, Group_By_Key__c, Allow_Dismissal__c
                FROM Notification_Policy__mdt
                WHERE Active__c = true
                LIMIT 200
            ]) {
                if (!String.isBlank(policy.Source_Type__c)) {
                    policyCache.put(policy.Source_Type__c.toUpperCase(), policy);
                }
                if (policy.DeveloperName == 'DEFAULT') policyCache.put('DEFAULT', policy);
            }
        }
        return policyCache;
    }

    private static Integer granted(Map<Id, Integer> counts, Id userId) {
        return counts.containsKey(userId) ? counts.get(userId) : 0;
    }

    private static Integer rank(String severity) {
        if (String.isBlank(severity)) return DEFAULT_RANK;
        String key = severity.toUpperCase();
        return SEVERITY_RANK.containsKey(key) ? SEVERITY_RANK.get(key) : DEFAULT_RANK;
    }
}