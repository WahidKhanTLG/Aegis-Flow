/**
 * Test-only batch that fails on purpose so the platform raises BatchApexErrorEvent.
 * Must be top level: Apex does not allow inner classes to implement Database.Batchable.
 */
@IsTest
public class AEIR_FailingBatchTestHelper implements Database.Batchable<SObject>, Database.RaisesPlatformEvents {
    public Iterable<SObject> start(Database.BatchableContext context) {
        return new List<Account>{ new Account(Name = 'AegisFlowBatchCoverage') };
    }
    public void execute(Database.BatchableContext context, List<SObject> scope) {
        Integer zero = 0;
        Integer crash = 1 / zero;
        System.debug(crash);
    }
    public void finish(Database.BatchableContext context) {}
}