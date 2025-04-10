@isTest
private class IntacctInvoiceItemSyncSchedulerTest {

    @isTest
    static void testScheduler_ExecutesBatchSuccessfully() {
        // 🔹 Insert dummy invoice so batch has data to process
        insert new Intacct_Invoice__c(
            Name = 'Test Invoice',
            Intacct_Invoice_ID__c = 'INV001',
            Intacct_Invoice_Key__c = 'KEY001'
        );

        // 🔹 Run the scheduler
        Test.startTest();
        String cronExp = '0 0 0 1 1 ? 2050'; // Arbitrary future date
        System.schedule('Test_InvoiceItemSyncScheduler', cronExp, new IntacctInvoiceItemSyncScheduler());
        Test.stopTest();

    }
}
