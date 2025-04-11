@isTest
private class SalesforceProductSyncIntacctQueueTest {

    @isTest
    static void testProductSync_InsertFlow() {
        // Arrange
        Product2 prod = new Product2(Name = 'Test Insert Product', IsActive = true);
        insert prod;

        Test.setMock(HttpCalloutMock.class, new MockInsertItemResponse());

        Test.startTest();
        System.enqueueJob(new SalesforceProductSyncIntacctQueueable(new List<Id>{prod.Id}));
        Test.stopTest();

        Product2 updated = [SELECT Id, Intacct_Item_ID__c FROM Product2 WHERE Id = :prod.Id];
        System.assertNotEquals(null, updated.Intacct_Item_ID__c);
        System.assertEquals('ITEM123', updated.Intacct_Item_ID__c);
    }

    @isTest
    static void testProductSync_UpdateFlow() {
        Product2 prod = new Product2(Name = 'Test Update Product', IsActive = true, Intacct_Item_ID__c = 'ITEM456');
        insert prod;

        Test.setMock(HttpCalloutMock.class, new MockUpdateItemResponse());

        Test.startTest();
        System.enqueueJob(new SalesforceProductSyncIntacctQueueable(new List<Id>{prod.Id}));
        Test.stopTest();

        // No assert required for update; just check it didn't error
        System.assertEquals('ITEM456', [SELECT Intacct_Item_ID__c FROM Product2 WHERE Id = :prod.Id].Intacct_Item_ID__c);
    }

    @isTest
    static void testProductSync_EmptyList() {
        Test.startTest();
        System.enqueueJob(new SalesforceProductSyncIntacctQueueable(new List<Id>()));
        Test.stopTest();
    }

    private class MockInsertItemResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/xml');
            res.setBody('<?xml version="1.0" encoding="UTF-8"?>' +
                        '<response><operation><result><status>success</status>' +
                        '<data><item><ITEMID>ITEM123</ITEMID></item></data>' +
                        '</result></operation></response>');
            return res;
        }
    }

    private class MockUpdateItemResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/xml');
            res.setBody('<?xml version="1.0" encoding="UTF-8"?>' +
                        '<response><operation><result><status>success</status>' +
                        '<data><item><ITEMID>ITEM456</ITEMID></item></data>' +
                        '</result></operation></response>');
            return res;
        }
    }
} 
