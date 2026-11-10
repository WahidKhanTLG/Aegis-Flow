@IsTest
public class AEIR_EventTestData {
    /** Read-only envelope fields are populated by the transport, not event constructors. */
    public static List<Diagnostic_Session_Requested__e> sessions(
        List<Diagnostic_Session_Requested__e> events, Id publisher) {
        List<Diagnostic_Session_Requested__e> output = new List<Diagnostic_Session_Requested__e>();
        for (Diagnostic_Session_Requested__e event : events) {
            if (event == null) { output.add(null); continue; }
            Map<String, Object> envelope = (Map<String, Object>)JSON.deserializeUntyped(JSON.serialize(event));
            envelope.put('CreatedById', publisher);
            output.add((Diagnostic_Session_Requested__e)JSON.deserialize(JSON.serialize(envelope), Diagnostic_Session_Requested__e.class));
        }
        return output;
    }
}
