public with sharing class AEIR_CorrelationIdService {
    public static String nextId() {
        String seed = UserInfo.getOrganizationId() + ':' + UserInfo.getUserId() + ':' + String.valueOf(Datetime.now().getTime()) + ':' + String.valueOf(Math.random());
        String digest = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(seed))).substring(0, 12).toUpperCase();
        return 'ERR-' + Datetime.now().formatGmt('yyyyMMdd-HHmmss') + '-' + digest;
    }
}