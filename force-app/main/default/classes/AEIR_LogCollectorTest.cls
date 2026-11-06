@IsTest
private class AEIR_LogCollectorTest {
    private static final String DEBUG_ID = '07L000000000001AAA';
    private static final String CREDENTIAL = 'cust__Aegis_Tooling';
    private static final String TOOLING_PATH = '/services/data/v67.0/tooling/sobjects/ApexLog/';

    @TestSetup
    static void setupReadersAndCommittedEvidence() {
        Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id;
        List<User> readers = new List<User>();
        for (String label : new List<String>{'Sensitive', 'Ordinary'}) {
            readers.add(new User(LastName = 'AegisLogCollector' + label, Alias = label == 'Sensitive' ? 'aeglog1' : 'aeglog2',
                Username = 'aeglog.' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)) + '@example.invalid',
                Email = 'aegis-log@example.invalid', ProfileId = profileId,
                TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'));
        }
        insert readers;
        PermissionSet recordReader = new PermissionSet(Name = 'Aegis_Log_Reader_Test', Label = 'Aegis Log Reader Test');
        PermissionSet sensitiveReader = new PermissionSet(Name = 'Aegis_Log_Sensitive_Test', Label = 'Aegis Log Sensitive Test');
        insert new List<PermissionSet>{recordReader, sensitiveReader};
        insert new ObjectPermissions(ParentId = recordReader.Id, SObjectType = 'Error_Log__c',
            PermissionsRead = true, PermissionsEdit = true, PermissionsViewAllRecords = false, PermissionsModifyAllRecords = false);
        insert new List<FieldPermissions>{
            new FieldPermissions(ParentId = recordReader.Id, SObjectType = 'Error_Log__c',
                Field = 'Error_Log__c.Debug_Log_Id__c', PermissionsRead = true, PermissionsEdit = false),
            new FieldPermissions(ParentId = recordReader.Id, SObjectType = 'Error_Log__c',
                Field = 'Error_Log__c.Debug_Log_Link__c', PermissionsRead = true, PermissionsEdit = true)
        };
        Id permissionId = [SELECT Id FROM CustomPermission WHERE DeveloperName = 'AEIR_View_Sensitive_Context' LIMIT 1].Id;
        insert new SetupEntityAccess(ParentId = sensitiveReader.Id, SetupEntityId = permissionId);
        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(AssigneeId = readers[0].Id, PermissionSetId = recordReader.Id),
            new PermissionSetAssignment(AssigneeId = readers[0].Id, PermissionSetId = sensitiveReader.Id),
            new PermissionSetAssignment(AssigneeId = readers[1].Id, PermissionSetId = recordReader.Id)
        };
        System.runAs(readers[0]) {
            Database.insert(new List<Error_Log__c>{
                error('LOG-READY', readers[0].Id, DEBUG_ID),
                error('LOG-MISSING', readers[0].Id, null),
                error('LOG-WRONG-REFERENCE', readers[0].Id, '001000000000001AAA'),
                error('LOG-PATH-REFERENCE', readers[0].Id, '07L123/../Body'),
                error('LOG-FOREIGN', readers[1].Id, DEBUG_ID)
            }, true, AccessLevel.SYSTEM_MODE);
        }
    }
    private static Error_Log__c error(String correlation, Id owner, String debugId) {
        return new Error_Log__c(Correlation_Id__c = correlation, Source_Type__c = 'Queueable',
            Original_Error_Message__c = 'A committed diagnostic fixture.', OwnerId = owner, User__c = owner,
            Debug_Log_Id__c = debugId, Severity__c = 'High', Status__c = 'New');
    }
    private static User reader(Boolean sensitive) {
        String name = 'AegisLogCollector' + (sensitive ? 'Sensitive' : 'Ordinary');
        return [SELECT Id FROM User WHERE LastName = :name LIMIT 1];
    }
    private static Id errorId(String correlation) {
        return [SELECT Id FROM Error_Log__c WHERE Correlation_Id__c = :correlation LIMIT 1].Id;
    }
    private class CredentialReader extends AEIR_LogCollectorService.CredentialMetadataReader {
        String actualEndpoint = URL.getOrgDomainUrl().toExternalForm();
        public override String endpoint(String name) {
            System.assertEquals(CREDENTIAL, name, 'Accept namespace-qualified credential names without accepting a URL.');
            return actualEndpoint;
        }
    }
    private static CredentialReader configure(Integer maximumBytes) {
        AEIR_LogCollectorService.connectionOverride = new Log_Connection__mdt(Active__c = true,
            Named_Credential__c = CREDENTIAL, Timeout_Milliseconds__c = 5000, Maximum_Log_Bytes__c = maximumBytes);
        CredentialReader credential = new CredentialReader();
        AEIR_LogCollectorService.credentialReader = credential;
        return credential;
    }
    private class ToolingMock implements HttpCalloutMock {
        Integer calls = 0;
        Integer metadataStatus = 200;
        Integer bodyStatus = 200;
        String source = 'USER_DEBUG|password=TOOLING-SECRET token=TOOLING-TOKEN Authorization: Bearer TOOLING-BEARER';
        String metadataOverride;
        String declaredLength;
        String bodyType = 'text/plain;charset=UTF-8';
        Boolean failTransport = false;
        public HttpResponse respond(HttpRequest request) {
            calls++;
            System.assertEquals('GET', request.getMethod());
            System.assertEquals(null, request.getHeader('Authorization'), 'Salesforce supplies Named Credential authentication.');
            String prefix = 'callout:' + CREDENTIAL + TOOLING_PATH + DEBUG_ID;
            HttpResponse response = new HttpResponse();
            if (failTransport) throw new CalloutException('password=TRANSPORT-SECRET endpoint=https://example.invalid/private');
            if (calls == 1) {
                System.assertEquals(prefix, request.getEndpoint(), 'Metadata is read only for the server-linked log Id.');
                response.setStatusCode(metadataStatus);
                response.setHeader('Content-Type', 'application/json');
                response.setBody(metadataOverride == null ? JSON.serialize(new Map<String, Object>{
                    'Id' => DEBUG_ID, 'LogLength' => Blob.valueOf(source).size()}) : metadataOverride);
            } else {
                System.assertEquals(2, calls, 'No unbounded discovery, pagination, redirect or retry calls.');
                System.assertEquals(prefix + '/Body/', request.getEndpoint());
                System.assertEquals('text/plain', request.getHeader('Accept'));
                response.setStatusCode(bodyStatus);
                response.setHeader('Content-Type', bodyType);
                if (declaredLength != null) response.setHeader('Content-Length', declaredLength);
                response.setBody(source);
            }
            return response;
        }
    }
    private static AEIR_LogCollectorService.LogCollectionResult collect(String correlation, ToolingMock mock) {
        Test.setMock(HttpCalloutMock.class, mock);
        Id parentId = errorId(correlation);
        AEIR_LogCollectorService.LogCollectionResult result;
        System.runAs(reader(true)) {
            System.assert(FeatureManagement.checkPermission('AEIR_View_Sensitive_Context'), 'Exercise the native capability.');
            result = AEIR_LogCollectorService.collectForError(parentId);
        }
        return result;
    }
    private static void assertNoBody(AEIR_LogCollectorService.LogCollectionResult result) {
        System.assertEquals(true, result.available, 'Retain an authorized valid reference when body retrieval fails.');
        System.assertEquals(false, result.bodyRetrieved);
        System.assertEquals(null, result.debugLogBody);
        System.assertEquals(false, result.truncated);
        System.assertEquals(DEBUG_ID, result.debugLogId);
        System.assert(!JSON.serialize(result).contains('RESPONSE-SECRET'));
        System.assert(!JSON.serialize(result).contains('TRANSPORT-SECRET'));
    }

    @IsTest static void retrievesOnlySanitizedTransientBodyThroughFixedToolingEndpoints() {
        configure(65536);
        ToolingMock mock = new ToolingMock();
        Test.startTest();
        AEIR_LogCollectorService.LogCollectionResult result = collect('LOG-READY', mock);
        Test.stopTest();
        System.assertEquals(2, mock.calls);
        System.assertEquals(true, result.available);
        System.assertEquals(true, result.bodyRetrieved, result.message);
        System.assertEquals(false, result.truncated);
        System.assert(result.debugLogBody.contains('[MASKED]'));
        System.assert(!result.debugLogBody.contains('TOOLING-SECRET'));
        System.assert(!result.debugLogBody.contains('TOOLING-TOKEN'));
        System.assert(!result.debugLogBody.contains('TOOLING-BEARER'));
        Id parentId = errorId('LOG-READY');
        System.assertEquals(URL.getOrgDomainUrl().toExternalForm() + '/' + DEBUG_ID, result.debugLogLink);
        System.assertEquals(result.debugLogLink, [SELECT Debug_Log_Link__c FROM Error_Log__c WHERE Id = :parentId].Debug_Log_Link__c);
        System.assertEquals(0, [SELECT count() FROM Error_Attachment__c WHERE Error_Log__c = :parentId],
            'Log bodies must not create evidence storage or private-file retention obligations.');
    }
    @IsTest static void disabledConnectionPreservesReferenceWithoutCallingTooling() {
        AEIR_LogCollectorService.connectionOverride = new Log_Connection__mdt(Active__c = false);
        ToolingMock mock = new ToolingMock();
        Test.startTest();
        AEIR_LogCollectorService.LogCollectionResult result = collect('LOG-READY', mock);
        Test.stopTest();
        assertNoBody(result);
        System.assertEquals(0, mock.calls);
        System.assert(result.message.contains('retrieval is disabled'));
    }
    @IsTest static void nativeSensitivePermissionDoesNotBypassParentSharing() {
        configure(65536); ToolingMock mock = new ToolingMock();
        Test.startTest();
        AEIR_LogCollectorService.LogCollectionResult result = collect('LOG-FOREIGN', mock);
        Test.stopTest();
        System.assertEquals(false, result.available);
        System.assertEquals(null, result.debugLogId);
        System.assertEquals(null, result.debugLogBody);
        System.assertEquals(0, mock.calls);
        System.assert(result.message.contains('unavailable'));
    }
    @IsTest static void recordOwnershipDoesNotConferSensitiveLogAccess() {
        configure(65536); ToolingMock mock = new ToolingMock(); Test.setMock(HttpCalloutMock.class, mock);
        Id parentId = errorId('LOG-FOREIGN');
        AEIR_LogCollectorService.LogCollectionResult result;
        Test.startTest();
        System.runAs(reader(false)) {
            System.assert(!FeatureManagement.checkPermission('AEIR_View_Sensitive_Context'));
            System.assertEquals(1, [SELECT count() FROM Error_Log__c WHERE Id = :parentId WITH USER_MODE]);
            result = AEIR_LogCollectorService.collectForError(parentId);
        }
        Test.stopTest();
        System.assertEquals(false, result.available);
        System.assertEquals(null, result.debugLogId);
        System.assertEquals(null, result.debugLogLink);
        System.assertEquals(0, mock.calls);
        System.assert(result.message.contains('sensitive-context'));
    }
    @IsTest static void missingAndInvalidReferencesAreSafeAndDoNotCallOut() {
        configure(65536); ToolingMock mock = new ToolingMock();
        Test.startTest();
        AEIR_LogCollectorService.LogCollectionResult missing = collect('LOG-MISSING', mock);
        AEIR_LogCollectorService.LogCollectionResult wrong = collect('LOG-WRONG-REFERENCE', mock);
        AEIR_LogCollectorService.LogCollectionResult path = collect('LOG-PATH-REFERENCE', mock);
        AEIR_LogCollectorService.LogCollectionResult nullParent = AEIR_LogCollectorService.collectForError(null);
        AEIR_LogCollectorService.LogCollectionResult wrongParent = AEIR_LogCollectorService.collectForError((Id)'001000000000001');
        Test.stopTest();
        System.assertEquals(false, missing.available); System.assert(missing.message.contains('No debug log id'));
        System.assertEquals(false, wrong.available); System.assert(wrong.message.contains('reference is invalid'));
        System.assertEquals(false, path.available);
        System.assertEquals(false, nullParent.available); System.assertEquals(false, wrongParent.available);
        System.assertEquals(0, mock.calls);
    }
    @IsTest static void credentialMustPointToTheExactCurrentOrgRoot() {
        CredentialReader credential = configure(65536);
        credential.actualEndpoint = URL.getOrgDomainUrl().toExternalForm() + '/services/data';
        ToolingMock mock = new ToolingMock();
        Test.startTest();
        AEIR_LogCollectorService.LogCollectionResult result = collect('LOG-READY', mock);
        Test.stopTest();
        assertNoBody(result); System.assertEquals(0, mock.calls);
        System.assert(result.message.contains('this Salesforce org'));
    }
    @IsTest static void credentialNameCannotContainAUrlOrPath() {
        configure(65536); AEIR_LogCollectorService.connectionOverride.Named_Credential__c = 'https://example.invalid';
        ToolingMock mock = new ToolingMock();
        Test.startTest(); AEIR_LogCollectorService.LogCollectionResult result = collect('LOG-READY', mock); Test.stopTest();
        assertNoBody(result); System.assertEquals(0, mock.calls);
    }
    @IsTest static void malformedMetadataDoesNotDownloadOrExposeProviderText() {
        configure(65536); ToolingMock mock = new ToolingMock(); mock.metadataOverride = '["RESPONSE-SECRET"]';
        Test.startTest(); AEIR_LogCollectorService.LogCollectionResult result = collect('LOG-READY', mock); Test.stopTest();
        assertNoBody(result); System.assertEquals(1, mock.calls);
    }
    @IsTest static void metadataMustIdentifyExactlyTheLinkedLog() {
        configure(65536); ToolingMock mock = new ToolingMock();
        mock.metadataOverride = '{"Id":"07L000000000002AAA","LogLength":10}';
        Test.startTest(); AEIR_LogCollectorService.LogCollectionResult result = collect('LOG-READY', mock); Test.stopTest();
        assertNoBody(result); System.assertEquals(1, mock.calls);
    }
    @IsTest static void excessiveDeclaredLogSizePreventsBodyDownload() {
        configure(1024); ToolingMock mock = new ToolingMock();
        mock.metadataOverride = '{"Id":"' + DEBUG_ID + '","LogLength":1025}';
        Test.startTest(); AEIR_LogCollectorService.LogCollectionResult result = collect('LOG-READY', mock); Test.stopTest();
        assertNoBody(result); System.assertEquals(1, mock.calls); System.assert(result.message.contains('size limit'));
    }
    @IsTest static void actualBodySizeIsCheckedEvenWhenMetadataUnderstatesIt() {
        configure(1024); ToolingMock mock = new ToolingMock();
        mock.source = 'RESPONSE-SECRET'; while (mock.source.length() <= 1024) mock.source += mock.source;
        mock.metadataOverride = '{"Id":"' + DEBUG_ID + '","LogLength":10}';
        Test.startTest(); AEIR_LogCollectorService.LogCollectionResult result = collect('LOG-READY', mock); Test.stopTest();
        assertNoBody(result); System.assertEquals(2, mock.calls);
    }
    @IsTest static void authenticationFailureRetainsReferenceAndNeverEchoesResponse() {
        configure(65536); ToolingMock mock = new ToolingMock(); mock.metadataStatus = 401;
        mock.metadataOverride = '{"message":"token=RESPONSE-SECRET"}';
        Test.startTest(); AEIR_LogCollectorService.LogCollectionResult result = collect('LOG-READY', mock); Test.stopTest();
        assertNoBody(result); System.assertEquals(1, mock.calls);
    }
    @IsTest static void throttledBodyReadIsNotRetriedOrReportedAsSuccessful() {
        configure(65536); ToolingMock mock = new ToolingMock(); mock.bodyStatus = 429; mock.source = 'token=RESPONSE-SECRET';
        Test.startTest(); AEIR_LogCollectorService.LogCollectionResult result = collect('LOG-READY', mock); Test.stopTest();
        assertNoBody(result); System.assertEquals(2, mock.calls);
    }
    @IsTest static void serverFailureIsNotRetried() {
        configure(65536); ToolingMock mock = new ToolingMock(); mock.bodyStatus = 503; mock.source = 'password=RESPONSE-SECRET';
        Test.startTest(); AEIR_LogCollectorService.LogCollectionResult result = collect('LOG-READY', mock); Test.stopTest();
        assertNoBody(result); System.assertEquals(2, mock.calls);
    }
    @IsTest static void transportExceptionsAreSafe() {
        configure(65536); ToolingMock mock = new ToolingMock(); mock.failTransport = true;
        Test.startTest(); AEIR_LogCollectorService.LogCollectionResult result = collect('LOG-READY', mock); Test.stopTest();
        assertNoBody(result); System.assertEquals(1, mock.calls); System.assert(result.message.contains('could not complete'));
    }
    @IsTest static void htmlIsNotPresentedAsLogText() {
        configure(65536); ToolingMock mock = new ToolingMock(); mock.bodyType = 'text/html'; mock.source = '<html>RESPONSE-SECRET</html>';
        Test.startTest(); AEIR_LogCollectorService.LogCollectionResult result = collect('LOG-READY', mock); Test.stopTest();
        assertNoBody(result); System.assertEquals(2, mock.calls);
    }
    @IsTest static void malformedContentLengthIsRejected() {
        configure(65536); ToolingMock mock = new ToolingMock(); mock.declaredLength = '1.5';
        Test.startTest(); AEIR_LogCollectorService.LogCollectionResult result = collect('LOG-READY', mock); Test.stopTest();
        assertNoBody(result); System.assertEquals(2, mock.calls);
    }
    @IsTest static void emptyBodyDoesNotClaimSuccessfulRetrieval() {
        configure(65536); ToolingMock mock = new ToolingMock(); mock.source = '';
        Test.startTest(); AEIR_LogCollectorService.LogCollectionResult result = collect('LOG-READY', mock); Test.stopTest();
        assertNoBody(result); System.assertEquals(2, mock.calls);
    }
    @IsTest static void maskingExpansionIsBoundedAfterRedactionWithoutBreakingUnicode() {
        configure(1024); ToolingMock mock = new ToolingMock(); mock.source = '';
        // This test isolates the real post-redaction byte budget from native access
        // to masking metadata; missing metadata correctly redacts the whole body.
        AEIR_SecuritySanitizerService.setSensitiveFieldsForTest(new List<Sensitive_Field__mdt>{
            new Sensitive_Field__mdt(Active__c = true, Field__c = 'Password', Regex__c = '(?i)password')
        });
        for (Integer i = 0; i < 50; i++) mock.source += '漢🙂 password=x ';
        System.assert(Blob.valueOf(mock.source).size() <= 1024, 'The source must fit before masking.');
        System.assert(Blob.valueOf(AEIR_SecuritySanitizerService.mask(mock.source)).size() > 1024,
            'Real label-preserving masking must expand this fixture beyond the byte budget.');
        Test.startTest(); AEIR_LogCollectorService.LogCollectionResult result = collect('LOG-READY', mock); Test.stopTest();
        System.assertEquals(true, result.bodyRetrieved, result.message);
        System.assertEquals(true, result.truncated);
        System.assert(Blob.valueOf(result.debugLogBody).size() <= 1024);
        System.assert(result.debugLogBody.endsWith('[TRUNCATED]'));
        System.assert(result.debugLogBody.contains('漢🙂'), 'Retain valid multibyte text through the truncation boundary.');
        System.assert(!result.debugLogBody.contains('password=x'));
        System.assert(!JSON.serialize(result.debugLogBody).contains('�'));
    }
}
