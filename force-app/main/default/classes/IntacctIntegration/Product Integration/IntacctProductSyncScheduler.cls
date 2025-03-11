global class IntacctProductSyncScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
        // 🔹 Get the last modified date dynamically (e.g., last 48 hours)
        String lastModifiedDate = DateTime.now().addDays(-2).format('MM/dd/yyyy HH:mm:ss');

        // 🔹 Start the first job with offset 0
        System.enqueueJob(new IntacctItemSyncQueueable(0, lastModifiedDate));

        System.debug('✅ Scheduled Job Executed: Started Product Sync with Last Modified Date: ' + lastModifiedDate);
    }
}
