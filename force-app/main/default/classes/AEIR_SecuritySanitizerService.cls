public with sharing class AEIR_SecuritySanitizerService {
    private static final String MASK = '[MASKED]';

    /**
     * Patterns that KEEP a leading label and mask only the value after it. Every one of
     * these must contain exactly one capture group, because the replacement is '$1'.
     */
    private static final List<String> LABELLED_SECRET_PATTERNS = new List<String>{
        '(?i)(authorization\\s*[:=]\\s*bearer\\s+)[A-Za-z0-9._\\-+/=]+',
        '(?i)(sessionid\\s*[:=]\\s*)[A-Za-z0-9._\\-+/=]+',
        '(?i)(password\\s*[:=]\\s*)[^,;\\s}]+',
        '(?i)(refresh_token\\s*[:=]\\s*)[^,;\\s}]+',
        '(?i)(access_token\\s*[:=]\\s*)[^,;\\s}]+',
        '(?i)(secret\\s*[:=]\\s*)[^,;\\s}]+'
    };

    /**
     * Patterns with NO capture group, replaced wholesale.
     *
     * This list exists because of a real defect: the long-digit rule used to live in the
     * labelled list, so replaceAll() was called with '$1' against a pattern that has no
     * group. Any message containing a 13-19 digit run - an order number, a record id, a
     * card number - threw "Index out of Bounds: No group 1" and took the whole capture
     * down with it. mask() runs on every capture, so that was a broad outage.
     */
    private static final List<String> BARE_SECRET_PATTERNS = new List<String>{
        '\\b[0-9]{13,19}\\b'
    };

    /**
     * Configured sensitive fields, cached for the life of the transaction. mask() is
     * called several times per captured error, so querying per call meant a bulk
     * subscriber batch re-read this metadata hundreds of times.
     */
    private static List<Sensitive_Field__mdt> cachedSensitiveFields;

    private static List<Sensitive_Field__mdt> sensitiveFields() {
        if (cachedSensitiveFields == null) {
            try {
                cachedSensitiveFields = [
                    SELECT Field__c, Regex__c, Active__c
                    FROM Sensitive_Field__mdt
                    WHERE Active__c = true
                    LIMIT 100
                ];
            } catch (Exception noAccess) {
                // A user without read access to the custom metadata type must still get
                // built-in secret masking rather than an exception that breaks capture.
                // Fail safe, not fail open: BUILT_IN_PATTERNS still run.
                System.debug(LoggingLevel.WARN,
                    'Aegis Flow: Sensitive_Field__mdt unreadable for this user; '
                    + 'built-in masking only. Grant custom metadata read via an Aegis permission set.');
                cachedSensitiveFields = new List<Sensitive_Field__mdt>();
            }
        }
        return cachedSensitiveFields;
    }

    public static String mask(String input) {
        if (String.isBlank(input)) return input;
        String output = input;
        for (String rx : LABELLED_SECRET_PATTERNS) {
            output = output.replaceAll(rx, '$1' + MASK);
        }
        for (String rx : BARE_SECRET_PATTERNS) {
            output = output.replaceAll(rx, MASK);
        }
        for (Sensitive_Field__mdt sf : sensitiveFields()) {
            if (!String.isBlank(sf.Regex__c)) {
                try { output = output.replaceAll(sf.Regex__c, MASK); } catch (Exception ignored) {}
            }
            if (!String.isBlank(sf.Field__c)) {
                String f = sf.Field__c;
                output = output.replaceAll('(?i)("' + f + '"\\s*:\\s*")[^"]*(")', '$1' + MASK + '$2');
            }
        }
        return output;
    }

    public static String safeTruncate(String input, Integer maxLen) {
        if (input == null || maxLen == null || input.length() <= maxLen) return input;
        return input.substring(0, Math.max(0, maxLen - 32)) + '... [TRUNCATED]';
    }
}