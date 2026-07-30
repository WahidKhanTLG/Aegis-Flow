trigger AEIR_EscalationRequestedEventTrigger on Escalation_Requested__e (after insert) {
    AEIR_EscalationRequestedEventHandler.handle(Trigger.new);
}