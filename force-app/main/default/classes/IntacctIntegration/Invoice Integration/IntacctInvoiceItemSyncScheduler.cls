global class IntacctInvoiceItemSyncScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
        Database.executeBatch(new IntacctInvoiceItemSyncBatch(true), 100);

        System.debug('✅ Scheduled Job Executed: Started Invoice Item Sync Batch');
    }
}
