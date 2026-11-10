trigger AEIR_ErrorLogLifecycleTrigger on Error_Log__c (before insert, before update) {
    AEIR_ErrorLifecycleService.stamp(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
}
