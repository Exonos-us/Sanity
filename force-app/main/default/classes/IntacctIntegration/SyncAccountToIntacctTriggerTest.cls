@isTest
private class SyncAccountToIntacctTriggerTest {
    
    @isTest
    static void testInsert_WithSyncStatu() {
        Test.startTest();
        Account acc = new Account(
            Name = 'Test Account',
        Intacct_Sync_Status__c = 'Sync'
            );
        insert acc;
        Test.stopTest();
        
    }
    
    @isTest
    static void testUpdate_WithFieldChangeButNonSyncStatusSync() {
        Account acc = new Account(
            Name = 'NonSync Account',
        Intacct_Sync_Status__c = 'No Sync',
        Phone = '1111'
            );
        insert acc;
        
        Test.startTest();
        acc.Phone = '9999';
        update acc;
        Test.stopTest();
    }
    
    @isTest
    static void testUpdate_WithFieldChangeAndSyncStatus() {
        Account acc = new Account(
            Name = 'Original Name',
            Intacct_Sync_Status__c = 'Sync',
            Phone = '123456'
        );
        insert acc;
        
        acc.Phone = '654321';
        
        Test.startTest();
        update acc;
        Test.stopTest();
        
    }
    
    
}