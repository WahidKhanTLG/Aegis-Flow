public with sharing class AEIR_RemediationController {
    private static final Integer MAX_REQUEST_LENGTH = 100000;

    public class RegisteredAction {
        @AuraEnabled public String actionKey;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String label;
        @AuraEnabled public String risk;
    }
    public class PreparedProposal {
        @AuraEnabled public String actionKey;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String recordId;
        @AuraEnabled public String beforeValue;
        @AuraEnabled public String newValue;
        @AuraEnabled public String correlationId;
        @AuraEnabled public String risk;
    }

    /** Only registered actions for fields this caller can read and update are offered. */
    @AuraEnabled(cacheable=true)
    public static List<RegisteredAction> getAvailableActions() {
        List<RegisteredAction> result = new List<RegisteredAction>();
        if (!FeatureManagement.checkPermission('AEIR_Execute_Remediation')) return result;
        for (Remediation_Action_Setting__mdt setting : actionSettings()) {
            if (!isAccessibleAction(setting)) continue;
            RegisteredAction action = new RegisteredAction();
            action.actionKey = setting.Action_Key__c;
            action.objectApiName = setting.Object__c;
            action.fieldApiName = setting.Field__c;
            action.label = setting.MasterLabel + ' (' + setting.Object__c + '.' + setting.Field__c + ')';
            action.risk = setting.Risk_Level__c;
            result.add(action);
        }
        return result;
    }

    /** Read-only proposal preparation. Confirmation and all execution gates remain separate. */
    @AuraEnabled
    public static PreparedProposal prepareProposal(String actionKey, String recordId, String newValue, String correlationId) {
        if (!FeatureManagement.checkPermission('AEIR_Execute_Remediation')) throw invalidRequest('You do not have permission to prepare a correction.');
        if (String.isBlank(actionKey) || actionKey.length() > 120 || String.isBlank(recordId)
            || recordId.length() > 18 || (correlationId != null && correlationId.length() > 80)
            || (newValue != null && newValue.length() > 32768)) {
            throw invalidRequest('Provide a registered action, valid record and bounded proposed value/reference.');
        }
        Remediation_Action_Setting__mdt selected;
        for (Remediation_Action_Setting__mdt setting : actionSettings()) {
            if (setting.Action_Key__c == actionKey) {
                if (selected != null) throw invalidRequest('The registered action is ambiguous. Contact your administrator.');
                selected = setting;
            }
        }
        if (selected == null || !isAccessibleAction(selected)) throw invalidRequest('That action or target field is not available to you.');
        Id targetId;
        try { targetId = (Id)recordId; }
        catch (Exception invalidId) { throw invalidRequest('Provide a valid record Id for the registered object.'); }
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(selected.Object__c);
        if (targetId.getSObjectType() != objectType) throw invalidRequest('The record does not belong to the registered object.');
        List<SObject> records;
        try {
            records = Database.queryWithBinds('SELECT Id,' + selected.Field__c + ' FROM ' + selected.Object__c
                + ' WHERE Id = :targetId LIMIT 1', new Map<String,Object>{ 'targetId' => targetId }, AccessLevel.USER_MODE);
        } catch (Exception noAccess) { throw invalidRequest('The target record or field is unavailable to you.'); }
        if (records.isEmpty()) throw invalidRequest('The target record or field is unavailable to you.');
        PreparedProposal proposal = new PreparedProposal();
        proposal.actionKey = selected.Action_Key__c;
        proposal.objectApiName = selected.Object__c;
        proposal.fieldApiName = selected.Field__c;
        proposal.recordId = recordId;
        proposal.correlationId = correlationId;
        proposal.newValue = newValue;
        proposal.risk = String.isBlank(selected.Risk_Level__c) ? 'Registered field correction' : selected.Risk_Level__c;
        Object beforeValue = records[0].get(selected.Field__c);
        String qualifiedField = selected.Object__c + '.' + selected.Field__c;
        String safeJson = AEIR_SecuritySanitizerService.mask(JSON.serialize(new Map<String,Object>{ qualifiedField => beforeValue }));
        Object safeValue = ((Map<String,Object>)JSON.deserializeUntyped(safeJson)).get(qualifiedField);
        proposal.beforeValue = safeValue == null ? null : String.valueOf(safeValue);
        return proposal;
    }

    private static List<Remediation_Action_Setting__mdt> actionSettings() {
        return [SELECT Action_Key__c, Object__c, Field__c, MasterLabel, Risk_Level__c, Active__c
            FROM Remediation_Action_Setting__mdt WHERE Active__c = true ORDER BY MasterLabel LIMIT 200];
    }

    private static Boolean isAccessibleAction(Remediation_Action_Setting__mdt setting) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(setting.Object__c);
        if (objectType == null) return false;
        Schema.DescribeSObjectResult objectDescription = objectType.getDescribe();
        if (!objectDescription.isAccessible() || !objectDescription.isUpdateable()) return false;
        Schema.SObjectField field = objectDescription.fields.getMap().get(setting.Field__c);
        return field != null && field.getDescribe().isAccessible() && field.getDescribe().isUpdateable()
            && field.getDescribe().getType() != Schema.DisplayType.EncryptedString;
    }

    /** Browser adapter only. All authority and writes remain in the orchestrator. */
    @AuraEnabled
    public static AEIR_RemediationOrchestrator.RemediationResult executeRemediation(String requestJson) {
        if (String.isBlank(requestJson) || requestJson.length() > MAX_REQUEST_LENGTH) {
            throw invalidRequest('Provide a remediation request of at most 100,000 characters.');
        }
        AEIR_RemediationOrchestrator.RemediationRequest request;
        Boolean hasProposedValue = false;
        try {
            Map<String, Object> envelope = (Map<String, Object>) JSON.deserializeUntyped(requestJson);
            hasProposedValue = envelope != null && envelope.containsKey('newValue');
            request = (AEIR_RemediationOrchestrator.RemediationRequest) JSON.deserializeStrict(
                requestJson, AEIR_RemediationOrchestrator.RemediationRequest.class);
        } catch (Exception invalidJson) {
            throw invalidRequest('The remediation request is not valid JSON for an approved field correction.');
        }
        if (request == null || String.isBlank(request.actionKey) || String.isBlank(request.objectApiName)
            || String.isBlank(request.fieldApiName) || String.isBlank(request.recordId) || !hasProposedValue) {
            throw invalidRequest('A registered action, object, field, record, and explicit proposed value are required.');
        }
        if (request.confirmed != true) {
            throw invalidRequest('Confirm the proposed correction before requesting execution.');
        }
        // Do not set permissions, enable feature flags, elevate DML, or change consent.
        // The orchestrator checks the flag/custom permission, registered whitelist,
        // record type, CRUD/FLS/sharing and audit persistence in the caller's context.
        return AEIR_RemediationOrchestrator.execute(request);
    }

    private static AuraHandledException invalidRequest(String message) {
        AuraHandledException failure = new AuraHandledException(message);
        failure.setMessage(message);
        return failure;
    }
}
