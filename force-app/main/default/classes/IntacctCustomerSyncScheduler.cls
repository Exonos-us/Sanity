global class IntacctCustomerSyncScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
        // Get the last modified date dynamically (e.g., last 48 hours)
        String lastModifiedDate = DateTime.now().addDays(-2).format('MM/dd/yyyy HH:mm:ss');

        // Start the first job with offset 0
        System.enqueueJob(new IntacctCustomerSyncQueueable(0, lastModifiedDate));

        System.debug('✅ Scheduled Job Executed: Started Sync with Last Modified Date: ' + lastModifiedDate);
    }
}
