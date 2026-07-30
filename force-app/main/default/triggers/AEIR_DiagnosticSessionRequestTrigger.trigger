trigger AEIR_DiagnosticSessionRequestTrigger on Diagnostic_Session_Requested__e (after insert) {
    AEIR_DiagnosticSessionRequestHandler.handle(Trigger.new);
}