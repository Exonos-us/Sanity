@isTest
private class SalesforceOrderSyncIntacctQueueableTest {

    @testSetup
    static void setupData() {
        // Account with Intacct ID
        Account acc = new Account(
            Name = 'Test Account',
            Intacct_Customer_ID__c = 'CUST100',
            Intacct_Customer_Name__c = 'ACME Inc.'
        );
        insert acc;

        // Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(10),
            AccountId = acc.Id,
            Manufacturers__c = 'Adobe',
            Solutions__c = 'Client'
        );
        insert opp;

        // Quote
        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Primary__c = true,
            SBQQ__Opportunity2__c = opp.Id
        );
        insert quote;

        // Product
        Product2 prod = new Product2(Name = 'Test Product', IsActive = true, Intacct_Item_ID__c = 'SKU100');
        insert prod;
       
        PricebookEntry pbe = new PricebookEntry(
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert pbe;

        // Order
        Order ord = new Order(
            Name = 'Test Order',
            AccountId = acc.Id,
            SBQQ__Quote__c = quote.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id =  Test.getStandardPricebookId()
        );
        insert ord;

        // OrderItem
        OrderItem item = new OrderItem(
            OrderId = ord.Id,
            Quantity = 1,
            UnitPrice = 100,
            Product2Id = prod.Id,
            PricebookEntryId = pbe.Id
        );
        insert item;
    }

    @isTest
    static void testOrderInsertSync() {
        Order ord = [SELECT Id FROM Order LIMIT 1];

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockInsertOrderCallout());

        System.enqueueJob(new SalesforceOrderSyncIntacctQueueable(new List<Id>{ ord.Id }));
        Test.stopTest();

        Order updatedOrder = [SELECT Intacct_Sales_Order_ID__c, Intacct_Sync_Status__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals('INT-SO-001', updatedOrder.Intacct_Sales_Order_ID__c);
        System.assertEquals('Success', updatedOrder.Intacct_Sync_Status__c);
    }

        @isTest
    static void testOrderUpdateSync() {

        Order ord = [SELECT Id FROM Order LIMIT 1];
        
        ord.Intacct_Sales_Order_ID__c = 'SO-ALREADY-INTACCT';
        update ord;

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockUpdateOrderCallout());

        System.enqueueJob(new SalesforceOrderSyncIntacctQueueable(new List<Id>{ ord.Id }));
        Test.stopTest();

        Order updatedOrder = [SELECT Intacct_Sync_Status__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals('Success', updatedOrder.Intacct_Sync_Status__c);
    }

    private class MockInsertOrderCallout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/xml');
            res.setBody('<?xml version="1.0" encoding="UTF-8"?>' +
                '<response>' +
                '  <operation>' +
                '    <result>' +
                '      <status>success</status>' +
                '      <key>INT-SO-001</key>' +
                '    </result>' +
                '  </operation>' +
                '</response>');
            return res;
        }
    }
    
    private class MockUpdateOrderCallout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/xml');
            res.setBody('<?xml version="1.0" encoding="UTF-8"?>' +
                '<response>' +
                '  <operation>' +
                '    <result>' +
                '      <status>success</status>' +
                '      <key>SO-UPDATED-KEY</key>' +
                '    </result>' +
                '  </operation>' +
                '</response>');
            return res;
        }
    }
}
