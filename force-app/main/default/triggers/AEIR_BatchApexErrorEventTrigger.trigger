trigger AEIR_BatchApexErrorEventTrigger on BatchApexErrorEvent (after insert) {
    AEIR_BatchApexErrorEventHandler.handle(Trigger.new);
}