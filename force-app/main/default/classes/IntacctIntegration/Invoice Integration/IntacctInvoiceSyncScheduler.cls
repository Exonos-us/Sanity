global class IntacctInvoiceSyncScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
        String lastModifiedDate = DateTime.now().addDays(-2).format('MM/dd/yyyy HH:mm:ss');

        System.enqueueJob(new IntacctInvoiceSyncQueueable(0, lastModifiedDate));

        System.debug('✅ Scheduled Job Executed: Started Invoice Sync with Last Modified Date: ' + lastModifiedDate);
    }
}
