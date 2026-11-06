public with sharing class AEIR_RemediationOrchestrator {
    @TestVisible private static Map<String, Remediation_Action_Setting__mdt> actionOverrides;
    public class RemediationRequest {
        @AuraEnabled public String correlationId;
        @AuraEnabled public String actionKey;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String recordId;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String newValue;
        @AuraEnabled public Boolean confirmed;
        @AuraEnabled public Id errorLogId;
        @AuraEnabled public Id diagnosticSessionId;
    }
    public class RemediationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String correlationId;
        @AuraEnabled public Id remediationActionId;
        @AuraEnabled public String status;
        @AuraEnabled public String userMessage;
        @AuraEnabled public String technicalMessage;
        @AuraEnabled public Boolean retryRecommended;
        @AuraEnabled public Boolean escalationRecommended;
    }
    public static RemediationResult execute(RemediationRequest req) {
        if (req == null) req = new RemediationRequest();
        RemediationResult res = new RemediationResult();
        res.success = false;
        res.correlationId = String.isBlank(req.correlationId) ? AEIR_CorrelationIdService.nextId() : req.correlationId;

        // Gate before building or writing the audit row. An unauthorized caller may not
        // have rights to insert Remediation_Action__c either, and execute() must return a
        // failed result rather than throwing out of its documented contract.
        if (!AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.GOVERNED_REMEDIATION)) {
            return denied(res, 'Governed remediation is disabled for this org.');
        }
        if (!FeatureManagement.checkPermission('AEIR_Execute_Remediation')) {
            return denied(res, 'You do not have the Aegis Execute Remediation permission.');
        }
        // Reserve the worst case: savepoint, update, rejected success audit, rollback,
        // savepoint release, and failure audit. Release also consumes a DML statement.
        // Deny before any write when a caller has used the budget.
        // Customer automation on the target record needs additional, org-specific headroom.
        if (Limits.getLimitDmlStatements() - Limits.getDmlStatements() < 6
            || Limits.getLimitQueries() - Limits.getQueries() < 2) {
            return denied(res, 'Insufficient transaction capacity to execute and audit this remediation safely.');
        }
        Remediation_Action__c audit = new Remediation_Action__c(Correlation_Id__c = res.correlationId, Error_Log__c = req.errorLogId, Diagnostic_Session__c = req.diagnosticSessionId, Action_Key__c = req.actionKey, Target_Record_Id__c = req.recordId, Object_API_Name__c = req.objectApiName, Field_API_Name__c = req.fieldApiName, After_Value__c = auditValue(req.objectApiName, req.fieldApiName, req.newValue), Requested_By__c = UserInfo.getUserId(), Status__c = 'Proposed', Requires_Confirmation__c = true);
        Savepoint changeBoundary;
        Boolean successAuditAttempted = false;
        try {
            Remediation_Action_Setting__mdt cfg = findAction(req.actionKey);
            if (cfg == null || cfg.Active__c != true) throw new AEIR_RemediationException('No active remediation action configured for key: ' + req.actionKey);
            audit.Requires_Confirmation__c = cfg.Requires_Confirmation__c;
            if (cfg.Requires_Confirmation__c == true && req.confirmed != true) throw new AEIR_RemediationException('User confirmation is required before executing this remediation.');
            if (cfg.Object__c != req.objectApiName || cfg.Field__c != req.fieldApiName) throw new AEIR_RemediationException('Requested object/field does not match remediation whitelist.');
            Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
            if (!gd.containsKey(req.objectApiName)) throw new AEIR_RemediationException('Unknown object: ' + req.objectApiName);
            Id targetId;
            try { targetId = (Id)req.recordId; } catch (Exception invalidId) { throw new AEIR_RemediationException('A valid Salesforce record Id is required.'); }
            if (targetId.getSObjectType() != gd.get(req.objectApiName)) throw new AEIR_RemediationException('The record Id does not belong to the configured object.');
            Schema.DescribeSObjectResult od = gd.get(req.objectApiName).getDescribe();
            if (!od.isUpdateable()) throw new AEIR_RemediationException('Current user cannot update object: ' + req.objectApiName);
            Map<String, Schema.SObjectField> fmap = od.fields.getMap();
            if (!fmap.containsKey(req.fieldApiName)) throw new AEIR_RemediationException('Unknown field: ' + req.fieldApiName);
            Schema.DescribeFieldResult fd = fmap.get(req.fieldApiName).getDescribe();
            if (!fd.isUpdateable()) throw new AEIR_RemediationException('Current user cannot update field: ' + req.fieldApiName);
            Id rid = targetId;
            SObject existing = Database.query('SELECT Id,' + req.fieldApiName + ' FROM ' + req.objectApiName + ' WHERE Id = :rid LIMIT 1');
            Object beforeVal = existing.get(req.fieldApiName);
            audit.Before_Value__c = auditValue(req.objectApiName, req.fieldApiName, beforeVal);
            SObject updateRow = gd.get(req.objectApiName).newSObject(targetId);
            updateRow.put(req.fieldApiName, convertValue(req.newValue, fd));
            changeBoundary = Database.setSavepoint();
            update updateRow;
            audit.Status__c = 'Executed'; audit.Approved_By__c = UserInfo.getUserId(); audit.Executed_By__c = UserInfo.getUserId(); audit.Result_Message__c = 'Field updated successfully.';
            successAuditAttempted = true;
            insert audit;
            Database.releaseSavepoint(changeBoundary);
            changeBoundary = null;
            res.success = true; res.status = 'Executed'; res.userMessage = 'The approved remediation was executed successfully.'; res.technicalMessage = audit.Result_Message__c; res.remediationActionId = audit.Id; return res;
        } catch (Exception ex) {
            if (changeBoundary != null) {
                // An update is never successful without its audit. A caught insert
                // exception alone does not undo the preceding customer-record update.
                Database.rollback(changeBoundary);
                Database.releaseSavepoint(changeBoundary);
            }
            String failureMessage = AEIR_SecuritySanitizerService.mask(ex.getMessage());
            audit.Id = null;
            audit.Status__c = 'Failed';
            audit.Approved_By__c = null;
            audit.Executed_By__c = null;
            audit.Result_Message__c = AEIR_SecuritySanitizerService.safeTruncate(failureMessage, 32768);
            // An audit rejection can be caused by invalid caller-supplied diagnostic
            // links. Preserve correlation/target evidence without retrying those links.
            if (successAuditAttempted) {
                audit.Error_Log__c = null;
                audit.Diagnostic_Session__c = null;
            }
            boundAudit(audit);
            try {
                insert audit;
            } catch (Exception auditFailure) {
                if (!successAuditAttempted) {
                    audit.Error_Log__c = null;
                    audit.Diagnostic_Session__c = null;
                    try { insert audit; } catch (Exception detachedAuditFailure) {
                        System.debug(LoggingLevel.WARN, 'Aegis Flow: remediation failed; failure audit could not be persisted.');
                    }
                } else {
                    System.debug(LoggingLevel.WARN, 'Aegis Flow: remediation rolled back; failure audit could not be persisted.');
                }
            }
            res.status = 'Failed'; res.userMessage = 'The requested remediation could not be completed safely. No correction was applied.'; res.technicalMessage = failureMessage; res.escalationRecommended = true; res.remediationActionId = audit.Id; return res;
        }
    }
    private static void boundAudit(Remediation_Action__c audit) {
        audit.Correlation_Id__c = AEIR_SecuritySanitizerService.safeTruncate(audit.Correlation_Id__c, 80);
        audit.Action_Key__c = AEIR_SecuritySanitizerService.safeTruncate(audit.Action_Key__c, 120);
        audit.Target_Record_Id__c = AEIR_SecuritySanitizerService.safeTruncate(audit.Target_Record_Id__c, 18);
        audit.Object_API_Name__c = AEIR_SecuritySanitizerService.safeTruncate(audit.Object_API_Name__c, 100);
        audit.Field_API_Name__c = AEIR_SecuritySanitizerService.safeTruncate(audit.Field_API_Name__c, 100);
        audit.Before_Value__c = AEIR_SecuritySanitizerService.safeTruncate(audit.Before_Value__c, 32768);
        audit.After_Value__c = AEIR_SecuritySanitizerService.safeTruncate(audit.After_Value__c, 32768);
    }
    private static Remediation_Action_Setting__mdt findAction(String actionKey) {
        if (Test.isRunningTest() && actionOverrides != null && actionOverrides.containsKey(actionKey)) {
            return actionOverrides.get(actionKey);
        }
        List<Remediation_Action_Setting__mdt> rows = [SELECT Action_Key__c, Object__c, Field__c, Requires_Confirmation__c, Active__c FROM Remediation_Action_Setting__mdt WHERE Action_Key__c = :actionKey LIMIT 1];
        return rows.isEmpty() ? null : rows[0];
    }

    private static String auditValue(String objectName, String fieldName, Object value) {
        try {
            Map<String, Schema.SObjectType> objects = Schema.getGlobalDescribe();
            if (objects.containsKey(objectName)) {
                Map<String, Schema.SObjectField> fields = objects.get(objectName).getDescribe().fields.getMap();
                if (fields.containsKey(fieldName)
                    && fields.get(fieldName).getDescribe().getType() == Schema.DisplayType.EncryptedString) {
                    return '[MASKED]';
                }
            }
            if (value == null) return null;
            // A naked value loses the metadata field-name match. Preserve the qualified
            // field as a JSON key while masking, then store only its sanitized value.
            String key = (String.isBlank(objectName) ? 'record' : objectName) + '.'
                + (String.isBlank(fieldName) ? 'value' : fieldName);
            String sanitized = AEIR_SecuritySanitizerService.mask(JSON.serialize(
                new Map<String, Object>{ key => String.valueOf(value) }));
            Map<String, Object> envelope = (Map<String, Object>) JSON.deserializeUntyped(sanitized);
            Object masked = envelope == null ? null : envelope.get(key);
            return masked instanceof String ? (String) masked : '[MASKED]';
        } catch (Exception maskingFailure) {
            System.debug(LoggingLevel.WARN, 'Aegis Flow: remediation audit value was redacted because masking could not be completed.');
            return '[MASKED]';
        }
    }

    private static Object convertValue(String val, Schema.DescribeFieldResult fd) {
        Schema.DisplayType t = fd.getType();
        if (t == Schema.DisplayType.Boolean) {
            String normalized = val == null ? null : val.trim().toLowerCase();
            if (normalized == 'true') return true;
            if (normalized == 'false') return false;
            throw new AEIR_RemediationException('A Boolean value must be true or false.');
        }
        if (val == null) return null;
        if (t == Schema.DisplayType.Date) return Date.valueOf(val);
        if (t == Schema.DisplayType.DateTime) return Datetime.valueOf(val);
        if (t == Schema.DisplayType.Integer) return Integer.valueOf(val);
        if (t == Schema.DisplayType.Double || t == Schema.DisplayType.Currency || t == Schema.DisplayType.Percent) return Decimal.valueOf(val);
        if (t == Schema.DisplayType.Picklist || t == Schema.DisplayType.MultiPicklist) {
            Set<String> allowed = new Set<String>();
            for (Schema.PicklistEntry entry : fd.getPicklistValues()) if (entry.isActive()) allowed.add(entry.getValue());
            if (t == Schema.DisplayType.Picklist && !allowed.contains(val)) throw new AEIR_RemediationException('The value is not an active picklist option.');
            if (t == Schema.DisplayType.MultiPicklist) for (String item : val.split(';')) if (!allowed.contains(item)) throw new AEIR_RemediationException('The value contains an inactive or invalid multi-select option.');
        }
        if (fd.getLength() > 0 && val.length() > fd.getLength()) throw new AEIR_RemediationException('The value exceeds the configured field length.');
        return val;
    }
    public class AEIR_RemediationException extends Exception {}

    /** Authorization failure: no DML, no audit row, contract preserved. */
    private static RemediationResult denied(RemediationResult res, String reason) {
        res.success = false;
        res.status = 'Denied';
        res.userMessage = 'You are not authorized to run this correction.';
        res.technicalMessage = reason;
        res.escalationRecommended = true;
        return res;
    }
}
