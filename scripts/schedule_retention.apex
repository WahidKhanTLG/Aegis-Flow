String jobName = 'AEIR Nightly Retention Purge';
Set<String> retentionJobNames = new Set<String>{
    jobName,
    'Aegis Flow Retention Purge' // Legacy name used before the current schedule helper.
};
for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name IN :retentionJobNames]) {
    System.abortJob(ct.Id);
}
System.schedule(jobName, '0 0 2 * * ?', new AEIR_RetentionScheduler());
System.debug('Scheduled AEIR retention purge for 2:00 AM org time.');
