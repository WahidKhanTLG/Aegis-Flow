public with sharing class AEIR_SecuritySanitizerService {
    private static final String MASK = '[MASKED]';
    private static final Integer MAX_DEPTH = 40;
    private static final Set<String> SECRET_KEYS = new Set<String>{
        'password', 'passwd', 'pwd', 'secret', 'clientsecret', 'token', 'accesstoken',
        'refreshtoken', 'authorization', 'sessionid', 'apikey', 'privatekey', 'credentials'
    };
    // Match assignments as a unit so their labels are preserved. Quoted values may
    // contain escaped quotes and spaces; unquoted credentials stop at a delimiter.
    private static final Pattern ASSIGNMENT = Pattern.compile(
        '(?i)(["\']?([a-z_][a-z0-9_.-]*)["\']?\\s*[:=]\\s*)'
        + '("(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\'|(?:(?:bearer|basic)\\s+)?[^,;\\s}&\\]]+)');
    private static final Pattern LONG_DIGITS = Pattern.compile('\\b[0-9]{13,19}\\b');

    private class MaskingRule {
        String field;
        Pattern expression;
    }

    private static List<Sensitive_Field__mdt> cachedSensitiveFields;
    private static List<MaskingRule> cachedRules;
    private static Boolean unsafeConfiguration = false;

    private static List<MaskingRule> rules() {
        if (cachedRules != null) return cachedRules;
        cachedRules = new List<MaskingRule>();
        if (cachedSensitiveFields == null) {
            try {
                cachedSensitiveFields = [
                    SELECT Field__c, Regex__c, Active__c
                    FROM Sensitive_Field__mdt WHERE Active__c = true LIMIT 100
                ];
            } catch (Exception unavailable) {
                unsafeConfiguration = true;
                System.debug(LoggingLevel.WARN,
                    'Aegis Flow: masking configuration could not be read; diagnostic content was redacted.');
                return cachedRules;
            }
        }
        for (Sensitive_Field__mdt setting : cachedSensitiveFields) {
            if (setting.Active__c == false) continue;
            MaskingRule rule = new MaskingRule();
            rule.field = setting.Field__c;
            try {
                if (!String.isBlank(setting.Regex__c)) rule.expression = Pattern.compile(setting.Regex__c);
            } catch (Exception invalidPattern) {
                // Never echo a configured pattern or exception: either can contain a
                // secret. Returning the original evidence would be a fail-open leak.
                unsafeConfiguration = true;
                System.debug(LoggingLevel.WARN,
                    'Aegis Flow: invalid masking configuration; diagnostic content was redacted.');
                return cachedRules;
            }
            cachedRules.add(rule);
        }
        return cachedRules;
    }

    public static String mask(String input) {
        if (String.isBlank(input)) return input;
        rules();
        if (unsafeConfiguration) return MASK;
        try {
            return maskString(input, 0);
        } catch (Exception maskingFailure) {
            System.debug(LoggingLevel.WARN,
                'Aegis Flow: diagnostic masking failed; diagnostic content was redacted.');
            return MASK;
        }
    }

    private static String maskString(String input, Integer depth) {
        if (String.isBlank(input)) return input;
        if (depth >= MAX_DEPTH) return MASK;
        String trimmed = input.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[') || trimmed.startsWith('"')) {
            Object parsed;
            Boolean validJson = false;
            try {
                parsed = JSON.deserializeUntyped(input);
                validJson = true;
            } catch (JSONException malformedJson) {
                // Logs often contain JSON fragments. Continue through label-aware text
                // masking rather than allowing malformed JSON to bypass sanitization.
            }
            if (validJson) return JSON.serialize(maskValue(parsed, depth + 1));
        }
        return maskText(input, depth + 1);
    }

    private static Object maskValue(Object value, Integer depth) {
        if (value == null) return null;
        if (depth >= MAX_DEPTH) return MASK;
        if (value instanceof Map<String, Object>) {
            Map<String, Object> source = (Map<String, Object>) value;
            Map<String, Object> sanitized = new Map<String, Object>();
            for (String key : source.keySet()) {
                sanitized.put(key, sensitiveKey(key) ? MASK : maskValue(source.get(key), depth + 1));
            }
            return sanitized;
        }
        if (value instanceof List<Object>) {
            List<Object> sanitized = new List<Object>();
            for (Object item : (List<Object>) value) sanitized.add(maskValue(item, depth + 1));
            return sanitized;
        }
        if (value instanceof String) return maskString((String) value, depth + 1);
        if (LONG_DIGITS.matcher(String.valueOf(value)).matches()) return MASK;
        return value;
    }

    private static Boolean sensitiveKey(String key) {
        if (String.isBlank(key)) return false;
        String normalized = key.toLowerCase().replaceAll('[^a-z0-9]', '');
        if (SECRET_KEYS.contains(normalized)) return true;
        for (MaskingRule rule : rules()) {
            if (!String.isBlank(rule.field)) {
                String configured = rule.field.toLowerCase();
                String unqualified = configured.substring(configured.lastIndexOf('.') + 1);
                if (key.equalsIgnoreCase(configured) || key.equalsIgnoreCase(unqualified)
                    || key.toLowerCase().endsWith('.' + unqualified)) return true;
            }
            // A regex may identify field names (the packaged Password rule does) or
            // sensitive value patterns. Keys are used for matching, never rewritten.
            if (rule.expression != null && rule.expression.matcher(key).find()) return true;
        }
        return false;
    }

    private static String maskText(String input, Integer depth) {
        if (depth >= MAX_DEPTH) return MASK;
        Matcher assignments = ASSIGNMENT.matcher(input);
        List<String> output = new List<String>();
        Integer position = 0;
        while (assignments.find()) {
            output.add(maskUnlabelled(input.substring(position, assignments.start())));
            output.add(assignments.group(1));
            String value = assignments.group(3);
            if (sensitiveKey(assignments.group(2))) {
                if (value.startsWith('"') && value.endsWith('"')) output.add('"' + MASK + '"');
                else if (value.startsWith('\'') && value.endsWith('\'')) output.add('\'' + MASK + '\'');
                else output.add(MASK);
            } else {
                // A non-sensitive assignment may itself contain a URL or serialized
                // payload with credentials. Do not let its outer label hide those.
                output.add(maskString(value, depth + 1));
            }
            position = assignments.end();
        }
        output.add(maskUnlabelled(input.substring(position)));
        return String.join(output, '');
    }

    private static String maskUnlabelled(String input) {
        String output = LONG_DIGITS.matcher(input).replaceAll(MASK);
        for (MaskingRule rule : rules()) {
            if (rule.expression != null) output = rule.expression.matcher(output).replaceAll(MASK);
        }
        return output;
    }

    @TestVisible
    private static void setSensitiveFieldsForTest(List<Sensitive_Field__mdt> settings) {
        cachedSensitiveFields = settings;
        cachedRules = null;
        unsafeConfiguration = false;
    }

    public static String safeTruncate(String input, Integer maxLen) {
        if (input == null || maxLen == null || input.length() <= maxLen) return input;
        return input.substring(0, Math.max(0, maxLen - 32)) + '... [TRUNCATED]';
    }
}
