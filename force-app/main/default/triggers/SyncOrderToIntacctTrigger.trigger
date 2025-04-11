trigger SyncOrderToIntacctTrigger on Order (after insert) {

    List<Id> orderIdsToProcess = new List<Id>();

    for (Order ord : Trigger.new) {
        orderIdsToProcess.add(ord.Id);
    }

    // Validate platform limits before enqueuing the Queueable job
    if (!orderIdsToProcess.isEmpty()) {
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs() && Limits.getCallouts() < Limits.getLimitCallouts()) {

            // Enqueue the job to process the Order records for synchronization
            System.enqueueJob(new SalesforceOrderSyncIntacctQueueable(orderIdsToProcess));

        } else {
            System.debug('⚠️ Queueable job or callout limit reached. Sync job not enqueued.');
            IntacctSyncUtil.sendErrorNotification('⚠️ Queueable job or callout limit reached. Unable to enqueue order sync job.');
        }
    }
}
