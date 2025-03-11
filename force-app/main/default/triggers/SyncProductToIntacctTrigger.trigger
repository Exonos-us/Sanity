trigger SyncProductToIntacctTrigger on Product2 (after insert, after update) {

    List<Id> productIdsToProcess = new List<Id>();

    Set<String> fieldsToCheck = new Set<String>{
        'Name',
        'IsActive',
        'Intacct_Item_ID__c'
    };

    for (Product2 prod : Trigger.new) {

        Product2 oldProd = Trigger.oldMap != null ? Trigger.oldMap.get(prod.Id) : null;
        Boolean isNew = oldProd == null;
        Boolean isModified = false;

        // Check if monitored fields have changed in an update operation
        if (!isNew) {
            for (String field : fieldsToCheck) {
                if (prod.get(field) != oldProd.get(field)) {
                    isModified = true;
                    break;
                }
            }
        }

        System.debug('🔹 Product2 Record: ' + prod.Id + ' | isNew: ' + isNew + ' | isModified: ' + isModified);

        // Add the record Id to the processing list if it is a new record or has relevant modifications
        if (isNew || isModified) {
            productIdsToProcess.add(prod.Id);
        }
    }

    // Validate platform limits before enqueuing the Queueable job
    if (!productIdsToProcess.isEmpty()) {
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs() && Limits.getCallouts() < Limits.getLimitCallouts()) {

            // Enqueue the job to process the Product2 records for synchronization
            //System.enqueueJob(new SalesforceProductSyncIntacctQueueable(productIdsToProcess));

        } else {
            System.debug('⚠️ Queueable job or callout limit reached. Sync job not enqueued.');
            IntacctSyncUtil.sendErrorNotification('⚠️ Queueable job or callout limit reached. Unable to enqueue product sync job.');

        }
    }
}
