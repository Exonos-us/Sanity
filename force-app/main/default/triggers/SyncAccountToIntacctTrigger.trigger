trigger SyncAccountToIntacctTrigger on Account (after insert, after update) {
    List<Id> accountIdsToProcess = new List<Id>();

    // Fields to monitor for updates
    Set<String> fieldsToCheck = new Set<String>{
        'Name', 'Phone', 'BillingStreet', 'BillingCity', 'BillingPostalCode',
        'BillingState', 'BillingCountry', 'Account_Status__c', 'Description'
    };

    for (Account acc : Trigger.new) {
        Account oldAcc = Trigger.oldMap != null ? Trigger.oldMap.get(acc.Id) : null;
        Boolean isNew = oldAcc == null;
        Boolean isModified = false;

        if (!isNew) {
            for (String field : fieldsToCheck) {
                if (acc.get(field) != oldAcc.get(field)) {
                    isModified = true;
                    break;
                }
            }
        }

        System.debug('🔹 Account: ' + acc.Id + ' | isNew: ' + isNew + ' | isModified: ' + isModified);

        // Add account to process if it's a new record or if key fields changed
        if (isNew || isModified) {
            accountIdsToProcess.add(acc.Id);
        }
    }

    // 🔹 Enqueue queueable job for upsert operation (Insert or Update in Intacct)
    if (!accountIdsToProcess.isEmpty() && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
        System.enqueueJob(new SalesforceAccountsSyncIntacctQueueable(accountIdsToProcess));
    }
}
