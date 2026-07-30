/**
 * Captures the Get Help feedback loop (spec section 7.4) and links file evidence to an
 * error log (section 12). Both objects shipped in the data model but had no code path,
 * so neither the feedback questions nor the attachment manifest were reachable.
 */
public with sharing class AEIR_FeedbackService {

    public class FeedbackInput {
        @AuraEnabled public String correlationId;
        @AuraEnabled public Id errorLogId;
        @AuraEnabled public Id diagnosticSessionId;
        @AuraEnabled public Boolean helpful;
        @AuraEnabled public String outcome;
        @AuraEnabled public String comments;
    }

    /**
     * Records one feedback response. The caller must own or be the target of the related
     * diagnostic, which sharing on Error_Log__c and Diagnostic_Session__c already enforces.
     */
    @AuraEnabled
    public static Id submitFeedback(FeedbackInput input) {
        if (input == null) throw new AuraHandledException('Feedback details are required.');
        if (input.errorLogId == null && input.diagnosticSessionId == null) {
            throw new AuraHandledException('Feedback must reference an error log or a diagnostic session.');
        }
        Error_Feedback__c feedback = new Error_Feedback__c(
            Error_Log__c = input.errorLogId,
            Diagnostic_Session__c = input.diagnosticSessionId,
            Helpful__c = input.helpful == true,
            Outcome__c = input.outcome,
            Comments__c = AEIR_SecuritySanitizerService.safeTruncate(
                AEIR_SecuritySanitizerService.mask(input.comments), 4000),
            Submitted_By__c = UserInfo.getUserId()
        );
        insert feedback;
        return feedback.Id;
    }

    @AuraEnabled
    public static Id submitFeedbackJson(String inputJson) {
        return submitFeedback((FeedbackInput) JSON.deserialize(inputJson, FeedbackInput.class));
    }

    /**
     * Registers a Salesforce File against an error log so the escalation package can
     * reference evidence without embedding it. Retention mirrors the error log policy.
     */
    public static Id attachEvidence(Id errorLogId, String contentDocumentId, String fileName, String attachmentType, Boolean sanitized) {
        if (errorLogId == null || String.isBlank(contentDocumentId)) return null;
        List<Error_Attachment__c> existing = [
            SELECT Id FROM Error_Attachment__c
            WHERE Error_Log__c = :errorLogId AND Content_Document_Id__c = :contentDocumentId
            LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0].Id;

        Error_Attachment__c attachment = new Error_Attachment__c(
            Error_Log__c = errorLogId,
            Content_Document_Id__c = contentDocumentId,
            File_Name__c = fileName,
            Attachment_Type__c = String.isBlank(attachmentType) ? 'Other' : attachmentType,
            Sanitized__c = sanitized == true,
            Retention_Expires_At__c = Date.today().addDays(365)
        );
        insert attachment;
        return attachment.Id;
    }

    /** Attachment manifest for the escalation package (spec section 12, Debug Evidence). */
    public static List<Error_Attachment__c> evidenceFor(Id errorLogId) {
        if (errorLogId == null) return new List<Error_Attachment__c>();
        return [
            SELECT Id, File_Name__c, Attachment_Type__c, Content_Document_Id__c, Sanitized__c, Retention_Expires_At__c
            FROM Error_Attachment__c WHERE Error_Log__c = :errorLogId
            ORDER BY CreatedDate DESC LIMIT 50
        ];
    }
}