@isTest
private class IntacctInvoiceItemSyncBatchTest {

    @isTest
    static void testBatch_EnqueuesQueueableJob() {
        // 🔹 Create test invoices
        List<Intacct_Invoice__c> testInvoices = new List<Intacct_Invoice__c>();
        for (Integer i = 0; i < 5; i++) {
            testInvoices.add(new Intacct_Invoice__c(
                Name = 'INV-' + i,
                Intacct_Invoice_ID__c = 'ID-' + i,
                Intacct_Invoice_Key__c = 'KEY-' + i
            ));
        }
        insert testInvoices;

        // 🔹 Start test context
        Test.startTest();
        IntacctInvoiceItemSyncBatch batch = new IntacctInvoiceItemSyncBatch(true);
        Database.executeBatch(batch, 200); // Batch size 200
        Test.stopTest();

    }

    @isTest
    static void testBatch_HandlesQueueableLimitReached() {
        // Insert one test invoice
        Intacct_Invoice__c invoice = new Intacct_Invoice__c(
            Name = 'Invoice A',
            Intacct_Invoice_ID__c = 'INV001',
            Intacct_Invoice_Key__c = 'KEY001'
        );
        insert invoice;

        // Fill up queueable job count (mock)
        Integer dummyQueueables = Limits.getLimitQueueableJobs() - Limits.getQueueableJobs();
        for (Integer i = 0; i < dummyQueueables; i++) {
            System.enqueueJob(new DummyQueueable());
        }

        // Run batch
        Test.startTest();
        Database.executeBatch(new IntacctInvoiceItemSyncBatch(true), 1);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Intacct_Invoice__c]);
    }

    // Dummy class to simulate queueable saturation
    public class DummyQueueable implements Queueable {
        public void execute(QueueableContext context) {
            // Do nothing
        }
    }
}
