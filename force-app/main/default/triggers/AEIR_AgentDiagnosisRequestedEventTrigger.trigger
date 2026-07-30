trigger AEIR_AgentDiagnosisRequestedEventTrigger on Agent_Diagnosis_Requested__e (after insert) {
    AEIR_AgentDiagnosisRequestedEventHandler.handle(Trigger.new);
}