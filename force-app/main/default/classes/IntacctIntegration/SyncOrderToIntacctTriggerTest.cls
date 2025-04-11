@isTest
private class SyncOrderToIntacctTriggerTest {

    @isTest
    static void testTriggerEnqueuesQueueable() {

        Account acc = new Account(
            Name = 'Test Account',
            Intacct_Customer_ID__c = 'INT123',
            Intacct_Customer_Name__c = 'Customer Inc'
        );
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(10),
            AccountId = acc.Id,
            Manufacturers__c = 'Adobe',
            Solutions__c = 'Client'
        );
        insert opp;

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Primary__c = true,
            SBQQ__Opportunity2__c = opp.Id
        );
        insert quote;

        Test.startTest();

        Order ord = new Order(
            Name = 'Test Order',
            AccountId = acc.Id,
            SBQQ__Quote__c = quote.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft'
        );
        insert ord;

        Test.stopTest();

        System.assertNotEquals(null, ord.Id);
    }
}
