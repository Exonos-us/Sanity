trigger SyncAccountToIntacctTrigger on Account (after insert, after update) {
    List<Id> accountIdsToProcess = new List<Id>();

    // Fields to monitor for updates
    Set<String> fieldsToCheck = new Set<String>{
        'Name', 'Phone', 'BillingStreet', 'BillingCity', 'BillingPostalCode',
        'BillingState', 'BillingCountry', 'Account_Status__c', 'Description','Intacct_Customer_ID__c', 'Intacct_Sync_Status__c'
    };

    for (Account acc : Trigger.new) {
        Account oldAcc = Trigger.oldMap != null ? Trigger.oldMap.get(acc.Id) : null;
        Boolean isNew = oldAcc == null;
        Boolean isModified = false;

        // 🔹 Skip processing if Intacct_Sync_Status__c is NOT 'Sync'
        if (acc.Intacct_Sync_Status__c != 'Sync') {
            System.debug('⚠️ Skipping Account ' + acc.Id + ' because Intacct_Sync_Status__c is not "Sync".');
            continue;
        }

        if (!isNew) {
            for (String field : fieldsToCheck) {
                if (acc.get(field) != oldAcc.get(field)) {
                    isModified = true;
                    break;
                }
            }
        }

        System.debug('🔹 Account: ' + acc.Id + ' | isNew: ' + isNew + ' | isModified: ' + isModified);

        // Add account to process only if it's new or modified
        if (isNew || isModified) {
            accountIdsToProcess.add(acc.Id);
        }
    }

    // ✅ Validate limits before enqueuing
    if (!accountIdsToProcess.isEmpty()) {
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs() && Limits.getCallouts() < Limits.getLimitCallouts()) {
            System.enqueueJob(new SalesforceAccountsSyncIntacctQueueable(accountIdsToProcess));
        } else {
            System.debug('⚠️ Queueable job or callout limit reached. Job not enqueued.');
            IntacctSyncUtil.sendErrorNotification('⚠️ Queueable job or callout limit reached. Unable to enqueue job.');
        }
    }
}
