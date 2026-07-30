public with sharing class AEIR_ErrorNormalizationService {
    private static List<Error_Rule__mdt> activeRules;
    public class Classification {
        @AuraEnabled public String category;
        @AuraEnabled public String severity;
        @AuraEnabled public String fixability;
        @AuraEnabled public String userMessage;
        @AuraEnabled public String recommendedAction;
        @AuraEnabled public Boolean retryEligible;
        @AuraEnabled public String matchedPattern;
        public String remediationActionKey;
    }

    public static Classification classify(String message) {
        Classification c = new Classification();
        c.category = 'Unknown';
        c.severity = 'Medium';
        c.fixability = 'UNKNOWN';
        c.userMessage = 'The system captured an error and created a diagnostic package.';
        c.recommendedAction = 'Review the captured context and escalate if no safe fix is available.';
        c.retryEligible = false;
        String lower = String.isBlank(message) ? '' : message.toLowerCase();
        for (Error_Rule__mdt rule : getActiveRules()) {
            if (!String.isBlank(rule.Pattern__c) && lower.contains(rule.Pattern__c.toLowerCase())) {
                c.category = safeCategory(rule.Category__c);
                c.severity = safeSeverity(rule.Severity__c);
                c.fixability = String.isBlank(rule.Fixability__c) ? 'UNKNOWN' : rule.Fixability__c;
                c.userMessage = rule.User_Message__c;
                c.remediationActionKey = rule.Remediation_Action_Key__c;
                c.recommendedAction = rule.Recommended_Action__c;
                c.retryEligible = c.fixability == 'RETRYABLE' || c.category == 'Locking';
                c.matchedPattern = rule.Pattern__c;
                return c;
            }
        }
        if (lower.contains('required_field_missing')) { c.category = 'Missing Data'; c.fixability = 'USER_FIXABLE'; }
        else if (lower.contains('validation')) { c.category = 'Validation Rule'; c.fixability = 'ADMIN_FIXABLE'; }
        else if (lower.contains('unable_to_lock_row')) { c.category = 'Locking'; c.fixability = 'RETRYABLE'; c.retryEligible = true; c.severity = 'Low'; }
        else if (lower.contains('nullpointer')) { c.category = 'Null Pointer'; c.fixability = 'DEVELOPER_ONLY'; c.severity = 'High'; }
        else if (lower.contains('cpu') || lower.contains('limit_exceeded')) { c.category = 'Governor Limit'; c.fixability = 'DEVELOPER_ONLY'; c.severity = 'High'; }
        return c;
    }

    public static void applyClassification(Error_Log__c log) {
        Classification c = classify(log.Original_Error_Message__c + '\n' + log.Stack_Trace__c);
        log.Error_Category__c = c.category;
        if (String.isBlank(log.Severity__c)) log.Severity__c = c.severity;
        else log.Severity__c = safeSeverity(log.Severity__c);
        log.Normalized_Message__c = c.userMessage;
        log.Retry_Eligible__c = c.retryEligible;
        if (String.isBlank(log.Error_Type__c)) log.Error_Type__c = inferErrorType(log.Source_Type__c, log.Original_Error_Message__c);
        if (String.isBlank(log.Status__c)) log.Status__c = 'New';
        if (String.isBlank(log.Agentforce_Status__c)) log.Agentforce_Status__c = 'Not Invoked';
        if (log.First_Seen_At__c == null) log.First_Seen_At__c = Datetime.now();
    }


    private static List<Error_Rule__mdt> getActiveRules() {
        if (activeRules == null) {
            activeRules = [SELECT Remediation_Action_Key__c, Pattern__c, Category__c, User_Message__c, Fixability__c, Severity__c, Recommended_Action__c, Active__c
                           FROM Error_Rule__mdt WHERE Active__c = true ORDER BY DeveloperName];
        }
        return activeRules;
    }
    private static String inferErrorType(String sourceType, String message) {
        if (!String.isBlank(sourceType)) {
            if (sourceType.contains('Flow')) return 'Flow';
            if (sourceType.contains('LWC')) return 'LWC';
            if (sourceType.contains('Batch')) return 'Batch';
            if (sourceType.contains('Queueable')) return 'Queueable';
            if (sourceType.contains('API')) return 'API';
            if (sourceType.contains('Integration')) return 'Integration';
            if (sourceType.contains('Apex') || sourceType.contains('Trigger')) return 'Apex';
        }
        String m = String.isBlank(message) ? '' : message.toLowerCase();
        if (m.contains('validation')) return 'Validation';
        if (m.contains('access') || m.contains('permission')) return 'Permission';
        return 'Unknown';
    }
    private static String safeSeverity(String s) {
        return new Set<String>{'Low','Medium','High','Critical'}.contains(s) ? s : 'Medium';
    }
    private static String safeCategory(String s) {
        Set<String> vals = new Set<String>{'Missing Data','Validation Rule','Permission','Governor Limit','Null Pointer','Integration','Locking','Configuration','Code Defect','Automation Failure','Unknown'};
        return vals.contains(s) ? s : 'Unknown';
    }
}