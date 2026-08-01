/**
 * Re-schedules the Aegis Flow pollers to a faster cadence for a testing phase, and back again.
 *
 * WHY THIS EXISTS, AND WHY 1 MINUTE IS NOT OFFERED
 * ------------------------------------------------
 * Scheduled Apex fires at most once per hour per job, so "every N minutes" means scheduling
 * 60/N separate jobs. Every-1-minute would need 60 jobs per poller - 120 of the org's 100
 * scheduled-Apex slots, which is not merely wasteful, it does not fit.
 *
 * More importantly, polling is the BACKSTOP, not the main path. If a failure is arriving
 * late, the fix is almost always to add a fault path to the Flow rather than to poll harder:
 * a fault path captures in seconds AND carries the record id, which no poller can recover.
 *
 * CADENCES
 *   RAPID    - Flow every 1 min (60 jobs), async every 15 min (4 jobs)  = 64 slots  <-- see warning
 *   TESTING  - Flow every 5 min (12 jobs), async every 15 min (4 jobs)  = 16 slots
 *   NORMAL   - Flow every 15 min (4 jobs), async hourly (1 job)         =  5 slots
 *
 * RAPID WARNING: 64 of the org's 100 scheduled-Apex slots. It fits, but it leaves little room
 * for anything else and runs 60 reconciliations an hour whether or not anything failed. Use it
 * for a short demo or test window and switch back to TESTING or NORMAL afterwards. Note that
 * even at 1 minute a poller still cannot recover the record id - only a fault path can.
 *
 * Set MODE below, then run the whole file in Developer Console -> Anonymous Apex.
 * Remember to run it again with MODE = 'NORMAL' when the testing phase ends.
 */
String MODE = 'NORMAL';            // 'RAPID' | 'TESTING' | 'NORMAL'

// --- abort every existing Aegis poller so this is safely re-runnable ---
Integer aborted = 0;
for (CronTrigger ct : [
    SELECT Id, CronJobDetail.Name FROM CronTrigger
    WHERE CronJobDetail.Name LIKE 'Aegis Flow Interview Monitor%'
       OR CronJobDetail.Name LIKE 'Aegis Flow Async Job Monitor%'
]) {
    System.abortJob(ct.Id);
    aborted++;
}

List<Integer> flowMinutes = new List<Integer>();
List<Integer> asyncMinutes = new List<Integer>();

if (MODE == 'RAPID') {
    for (Integer m = 0; m < 60; m += 1) flowMinutes.add(m);    // 60 jobs
    for (Integer m = 0; m < 60; m += 15) asyncMinutes.add(m);  //  4 jobs
} else if (MODE == 'TESTING') {
    for (Integer m = 0; m < 60; m += 5) flowMinutes.add(m);    // 12 jobs
    for (Integer m = 0; m < 60; m += 15) asyncMinutes.add(m);  //  4 jobs
} else {
    for (Integer m = 0; m < 60; m += 15) flowMinutes.add(m);   //  4 jobs
    asyncMinutes.add(15);                                      //  1 job
}

for (Integer m : flowMinutes) {
    System.schedule('Aegis Flow Interview Monitor ' + m, '0 ' + m + ' * * * ?', new AEIR_FlowInterviewMonitor());
}
for (Integer m : asyncMinutes) {
    System.schedule('Aegis Flow Async Job Monitor ' + m, '0 ' + m + ' * * * ?', new AEIR_AsyncJobMonitorScheduler());
}

System.debug(LoggingLevel.ERROR, 'Aegis cadence = ' + MODE
    + ' | aborted ' + aborted
    + ' | flow jobs ' + flowMinutes.size() + ' (every ' + (60 / flowMinutes.size()) + ' min)'
    + ' | async jobs ' + asyncMinutes.size() + ' (every ' + (60 / asyncMinutes.size()) + ' min)');
