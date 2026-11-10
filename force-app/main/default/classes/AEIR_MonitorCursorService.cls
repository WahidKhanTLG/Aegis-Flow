/** Org-level keyset cursors; settings for notifications and onboarding are preserved. */
public without sharing class AEIR_MonitorCursorService {
    public class State {
        public Id settingsId;
        public Datetime at;
        public Id lastId;
    }
    public static State read(Boolean flow) {
        Id orgId = UserInfo.getOrganizationId();
        List<Aegis_Org_Setting__c> rows = Database.queryWithBinds(
            'SELECT Id, Flow_Monitor_At__c, Flow_Monitor_Id__c, Async_Monitor_At__c, Async_Monitor_Id__c '
            + 'FROM Aegis_Org_Setting__c WHERE SetupOwnerId = :orgId LIMIT 1',
            new Map<String, Object>{'orgId' => orgId}, AccessLevel.SYSTEM_MODE);
        State state = new State();
        if (rows.isEmpty()) return state;
        state.settingsId = rows[0].Id;
        state.at = flow ? rows[0].Flow_Monitor_At__c : rows[0].Async_Monitor_At__c;
        String last = flow ? rows[0].Flow_Monitor_Id__c : rows[0].Async_Monitor_Id__c;
        try { state.lastId = String.isBlank(last) ? null : (Id)last; }
        catch (Exception invalidCursor) { state.at = null; }
        if (state.at == null || state.lastId == null) { state.at = null; state.lastId = null; }
        return state;
    }
    public static void save(State state, Boolean flow, Datetime at, Id lastId) {
        Aegis_Org_Setting__c settings = new Aegis_Org_Setting__c(Id = state.settingsId);
        if (settings.Id == null) settings.SetupOwnerId = UserInfo.getOrganizationId();
        if (flow) {
            settings.Flow_Monitor_At__c = at;
            settings.Flow_Monitor_Id__c = lastId == null ? null : String.valueOf(lastId);
        } else {
            settings.Async_Monitor_At__c = at;
            settings.Async_Monitor_Id__c = lastId == null ? null : String.valueOf(lastId);
        }
        // Concurrent scans may revisit a page, which capture deduplication handles.
        // Each write touches only its own cursor, never the other monitor or setup.
        if (settings.Id == null) Database.insert(settings, AccessLevel.SYSTEM_MODE);
        else Database.update(settings, AccessLevel.SYSTEM_MODE);
    }
}
