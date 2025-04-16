public with sharing class IntacctInvoiceItemSyncBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
    
    private Boolean isInvoice;
    
    public IntacctInvoiceItemSyncBatch(Boolean isInvoice) {
        this.isInvoice = isInvoice;
    }
    
    public Database.QueryLocator start(Database.BatchableContext context) {
        
        return Database.getQueryLocator([
                SELECT Id, Intacct_Invoice_ID__c,Intacct_Invoice_Key__c, LastModifiedDate FROM Intacct_Invoice__c
            ]);
        
    }
    
    public void execute(Database.BatchableContext context, List<SObject> records) {
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new IntacctInvoiceItemSyncQueueable(records));
        } else {
            IntacctSyncUtil.logSyncError('Invoice Item Sync', '⚠️ Limits reached. Cannot enqueue additional jobs in batch.', 'execute', 'IntacctInvoiceItemSyncBatch');
        }
    }
    
    public void finish(Database.BatchableContext context) {
        System.debug('✅ Batch execution finished.');
    }
}