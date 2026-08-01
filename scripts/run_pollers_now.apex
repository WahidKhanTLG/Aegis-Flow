/**
 * Runs both Aegis pollers immediately, on demand.
 *
 * During a testing session this is almost always what you actually want instead of a faster
 * schedule: zero scheduled-job cost, and the answer arrives in seconds rather than at the
 * next tick. Run it right after triggering a failure.
 */
Integer flowCaptured  = AEIR_FlowInterviewMonitor.reconcile();
Integer asyncCaptured = AEIR_AsyncJobMonitorScheduler.monitorFailedJobs();
System.debug(LoggingLevel.ERROR,
    'Aegis poll now -> Flow interviews captured: ' + flowCaptured
    + ' | failed async jobs captured: ' + asyncCaptured);
