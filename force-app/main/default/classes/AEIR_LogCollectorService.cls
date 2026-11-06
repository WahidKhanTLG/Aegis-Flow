/** Optional, same-org Tooling API reads. Debug-log bodies are never stored or shared. */
public with sharing class AEIR_LogCollectorService {
    private static final String TOOLING_PATH = '/services/data/v67.0/tooling/sobjects/ApexLog/';
    private static final Integer MAX_METADATA_BYTES = 8192;
    private static final Integer MAX_LOG_BYTES = 131072;
    @TestVisible private static Log_Connection__mdt connectionOverride;
    @TestVisible private static CredentialMetadataReader credentialReader = new CredentialMetadataReader();

    /** Read only nonsecret Named Credential routing; never authentication parameters. */
    public virtual class CredentialMetadataReader {
        public virtual String endpoint(String developerName) {
            return ConnectApi.NamedCredentials.getNamedCredential(developerName).calloutUrl;
        }
    }
    private class Connection {
        String namedCredential;
        Integer timeoutMilliseconds;
        Integer maximumBytes;
    }
    private class LogReadException extends Exception {}

    public class LogCollectionResult {
        @AuraEnabled public Boolean available = false;
        @AuraEnabled public String message;
        @AuraEnabled public String debugLogId;
        @AuraEnabled public String debugLogLink;
        @AuraEnabled public Boolean bodyRetrieved = false;
        @AuraEnabled public String debugLogBody;
        @AuraEnabled public Boolean truncated = false;
    }

    @AuraEnabled
    public static LogCollectionResult collectForError(Id errorLogId) {
        LogCollectionResult result = new LogCollectionResult();
        if (errorLogId == null || errorLogId.getSObjectType() != Error_Log__c.SObjectType) {
            result.message = 'A valid Aegis Flow error record is required.';
            return result;
        }
        if (!sensitiveReader()) {
            result.message = 'Debug-log access requires the sensitive-context permission or an administrator.';
            return result;
        }
        Error_Log__c log;
        try {
            List<Error_Log__c> visible = Database.queryWithBinds(
                'SELECT Id, Debug_Log_Id__c, Debug_Log_Link__c FROM Error_Log__c WHERE Id = :errorId LIMIT 1',
                new Map<String, Object>{'errorId' => errorLogId}, AccessLevel.USER_MODE);
            if (!visible.isEmpty()) log = visible[0];
        } catch (Exception inaccessible) {
            // Do not disclose whether an unauthorized parent or technical field exists.
        }
        if (log == null) {
            result.message = 'That diagnostic record is unavailable or you do not have access.';
            return result;
        }
        if (String.isBlank(log.Debug_Log_Id__c)) {
            result.message = 'No debug log id is available. Continue with stack trace, context, record snapshot, and user description.';
            return result;
        }
        // The browser supplies only a parent Id. Its stored log reference is the sole
        // source of the path segment; URLs, traversal, other sObjects and queries fail.
        if (!Pattern.matches('07L[A-Za-z0-9]{12}([A-Za-z0-9]{3})?', log.Debug_Log_Id__c)) {
            result.message = 'The linked debug-log reference is invalid.';
            return result;
        }
        result.available = true;
        result.debugLogId = log.Debug_Log_Id__c;
        result.debugLogLink = URL.getOrgDomainUrl().toExternalForm() + '/' + result.debugLogId;
        try {
            Connection connection = configuredConnection();
            if (connection == null) {
                result.message = 'A debug log reference is linked. Debug-log body retrieval is disabled.';
            } else if (Limits.getLimitCallouts() - Limits.getCallouts() < 2) {
                result.message = 'The debug log reference is available; retrieval requires additional callout capacity.';
            } else {
                retrieveBody(connection, result);
            }
        } catch (LogReadException rejected) {
            // Only fixed internal reason codes reach this branch, never provider text.
            if (rejected.getMessage() == 'LOG_TOO_LARGE') {
                result.message = 'The linked debug log exceeds the configured retrieval size limit. Its reference remains available.';
            } else if (rejected.getMessage() == 'INVALID_CONNECTION') {
                result.message = 'Debug-log body retrieval requires an approved Named Credential pointing to this Salesforce org.';
            } else {
                result.message = 'The linked debug-log body is unavailable or its response could not be validated.';
            }
        } catch (Exception retrievalFailure) {
            // No token, response body, credential exception, endpoint or stack is echoed.
            result.message = 'Debug-log body retrieval could not complete. Review the approved connection or retry later.';
        }
        persistReference(log, result);
        return result;
    }

    private static Boolean sensitiveReader() {
        if (FeatureManagement.checkPermission('AEIR_View_Sensitive_Context')) return true;
        // Native profile authority, not a profile name or a test authorization seam.
        List<Profile> profiles = Database.queryWithBinds(
            'SELECT PermissionsModifyAllData FROM Profile WHERE Id = :profileId LIMIT 1',
            new Map<String, Object>{'profileId' => UserInfo.getProfileId()}, AccessLevel.SYSTEM_MODE);
        return !profiles.isEmpty() && profiles[0].PermissionsModifyAllData;
    }

    private static Connection configuredConnection() {
        Log_Connection__mdt setting = connectionOverride == null
            ? Log_Connection__mdt.getInstance('DEFAULT') : connectionOverride;
        if (setting == null || setting.Active__c != true) return null;
        if (String.isBlank(setting.Named_Credential__c)
            || !Pattern.matches('[A-Za-z][A-Za-z0-9_]{0,119}', setting.Named_Credential__c)) {
            throw new LogReadException('INVALID_CONNECTION');
        }
        String endpoint;
        try { endpoint = credentialReader.endpoint(setting.Named_Credential__c); }
        catch (Exception inaccessibleCredential) { throw new LogReadException('INVALID_CONNECTION'); }
        // No wildcard domains, arbitrary paths, alternate orgs, query strings or
        // redirect targets. Verify the actual modern credential URL before HTTP.
        String orgRoot = URL.getOrgDomainUrl().toExternalForm();
        if (endpoint != orgRoot && endpoint != orgRoot + '/') throw new LogReadException('INVALID_CONNECTION');
        Connection connection = new Connection();
        connection.namedCredential = setting.Named_Credential__c;
        connection.timeoutMilliseconds = setting.Timeout_Milliseconds__c == null ? 5000
            : Math.max(1000, Math.min(10000, setting.Timeout_Milliseconds__c.intValue()));
        connection.maximumBytes = setting.Maximum_Log_Bytes__c == null ? 65536
            : Math.max(1024, Math.min(MAX_LOG_BYTES, setting.Maximum_Log_Bytes__c.intValue()));
        return connection;
    }

    private static void retrieveBody(Connection connection, LogCollectionResult result) {
        // Salesforce debug logs are immutable after creation. Inspect their byte size
        // before downloading the body, avoiding large-log heap/callout exhaustion.
        HttpResponse metadata = send(connection, result.debugLogId, false);
        requireOk(metadata);
        String metadataBody = boundedBody(metadata, MAX_METADATA_BYTES);
        Object decoded;
        try { decoded = JSON.deserializeUntyped(metadataBody); }
        catch (Exception invalidJson) { throw new LogReadException('INVALID_METADATA'); }
        if (!(decoded instanceof Map<String, Object>)) throw new LogReadException('INVALID_METADATA');
        Map<String, Object> values = (Map<String, Object>)decoded;
        Object lengthValue = values.get('LogLength');
        String returnedId = values.get('Id') instanceof String ? (String)values.get('Id') : null;
        if (returnedId == null || !Pattern.matches('07L[A-Za-z0-9]{12}([A-Za-z0-9]{3})?', returnedId)
            || returnedId.substring(0, 15) != result.debugLogId.substring(0, 15)
            || !(lengthValue instanceof Decimal || lengthValue instanceof Integer || lengthValue instanceof Long)) {
            throw new LogReadException('INVALID_METADATA');
        }
        Decimal length;
        try { length = Decimal.valueOf(String.valueOf(lengthValue)); }
        catch (Exception invalidLength) { throw new LogReadException('INVALID_METADATA'); }
        if (length < 0 || length != length.setScale(0)) throw new LogReadException('INVALID_METADATA');
        if (length > connection.maximumBytes) throw new LogReadException('LOG_TOO_LARGE');
        HttpResponse body = send(connection, result.debugLogId, true);
        requireOk(body);
        String contentType = body.getHeader('Content-Type');
        if (String.isNotBlank(contentType) && !contentType.toLowerCase().startsWith('text/plain')
            && !contentType.toLowerCase().startsWith('application/octet-stream')) {
            throw new LogReadException('INVALID_RESPONSE');
        }
        String source = boundedBody(body, connection.maximumBytes);
        if (String.isBlank(source)) throw new LogReadException('EMPTY_BODY');
        String sanitized = AEIR_SecuritySanitizerService.mask(source);
        result.truncated = Blob.valueOf(sanitized).size() > connection.maximumBytes;
        result.debugLogBody = result.truncated ? fitBytes(sanitized, connection.maximumBytes) : sanitized;
        result.bodyRetrieved = true;
        result.message = result.truncated ? 'The sanitized debug-log body was retrieved and truncated to the configured limit.'
            : 'The sanitized debug-log body was retrieved. Its contents are not stored by Aegis Flow.';
    }

    private static HttpResponse send(Connection connection, String debugLogId, Boolean body) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:' + connection.namedCredential + TOOLING_PATH + debugLogId + (body ? '/Body/' : ''));
        request.setMethod('GET');
        request.setHeader('Accept', body ? 'text/plain' : 'application/json');
        request.setTimeout(connection.timeoutMilliseconds);
        return new Http().send(request);
    }
    private static void requireOk(HttpResponse response) {
        if (response == null || response.getStatusCode() != 200) throw new LogReadException('HTTP_FAILURE');
    }
    private static String boundedBody(HttpResponse response, Integer maximumBytes) {
        String declaredLength = response.getHeader('Content-Length');
        if (String.isNotBlank(declaredLength)) {
            if (!Pattern.matches('[0-9]{1,9}', declaredLength)) throw new LogReadException('INVALID_RESPONSE');
            if (Integer.valueOf(declaredLength) > maximumBytes) throw new LogReadException('LOG_TOO_LARGE');
        }
        Blob raw = response.getBodyAsBlob();
        if (raw == null || raw.size() > maximumBytes) throw new LogReadException('LOG_TOO_LARGE');
        try { return raw.toString(); }
        catch (Exception invalidText) { throw new LogReadException('INVALID_RESPONSE'); }
    }
    private static String fitBytes(String value, Integer maximumBytes) {
        String marker = '\n... [TRUNCATED]';
        Integer low = 0, high = value.length();
        Integer budget = maximumBytes - Blob.valueOf(marker).size();
        while (low < high) {
            Integer middle = (low + high + 1) / 2;
            if (Blob.valueOf(textPrefix(value, middle)).size() <= budget) low = middle;
            else high = middle - 1;
        }
        return textPrefix(value, low) + marker;
    }
    private static String textPrefix(String value, Integer length) {
        Integer keep = Math.min(value.length(), length);
        if (keep > 0 && keep < value.length()) {
            Integer last = value.charAt(keep - 1);
            if (last >= 55296 && last <= 56319) keep--;
        }
        return value.substring(0, keep);
    }
    private static void persistReference(Error_Log__c log, LogCollectionResult result) {
        if (log.Debug_Log_Link__c == result.debugLogLink) return;
        try {
            Database.update(new Error_Log__c(Id = log.Id, Debug_Log_Link__c = result.debugLogLink), AccessLevel.USER_MODE);
        } catch (Exception linkWriteDenied) {
            result.message += ' The link could not be saved; your record permissions were preserved.';
        }
    }
}
