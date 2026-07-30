trigger AEIR_ErrorCapturedEventTrigger on Error_Captured__e (after insert) {
    AEIR_ErrorCapturedEventHandler.handle(Trigger.new);
}