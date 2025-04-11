@isTest
private class SalesforceAccSyncIntacctQueueableTest {

    // 1️⃣ Test insert scenario (account without Intacct ID)
    @isTest
    static void testAccountInsertScenario() {
        Test.setMock(HttpCalloutMock.class, new MockInsertCustomerResponse());

        Account acc = new Account(
            Name = 'New Account',
            Phone = '123456',
            Intacct_Sync_Status__c = 'Sync'
        );
        insert acc;

        Test.startTest();
        System.enqueueJob(new SalesforceAccountsSyncIntacctQueueable(new List<Id>{ acc.Id }));
        Test.stopTest();

        Account updatedAcc = [SELECT Intacct_Customer_ID__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('INT123', updatedAcc.Intacct_Customer_ID__c);
    }

    // 2️⃣ Test update scenario (account already has Intacct ID)
    @isTest
    static void testAccountUpdateScenario() {
        Test.setMock(HttpCalloutMock.class, new MockUpdateCustomerResponse());

        Account acc = new Account(
            Name = 'Existing Account',
            Phone = '5555',
            Intacct_Customer_ID__c = 'INT123',
            Intacct_Sync_Status__c = 'Sync'
        );
        insert acc;

        Test.startTest();
        System.enqueueJob(new SalesforceAccountsSyncIntacctQueueable(new List<Id>{ acc.Id }));
        Test.stopTest();

        // We just check it didn’t fail
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Id = :acc.Id]);
    }

    // 3️⃣ Test empty list scenario
    @isTest
    static void testEmptyAccountList() {
        Test.startTest();
        System.enqueueJob(new SalesforceAccountsSyncIntacctQueueable(new List<Id>()));
        Test.stopTest();
    }

    // 4️⃣ Test error during processing
    @isTest
    static void testWithErrorResponse() {
        Test.setMock(HttpCalloutMock.class, new MockErrorResponse());

        Account acc = new Account(Name = 'Error Account', Intacct_Sync_Status__c = 'Sync');
        insert acc;

        Test.startTest();
        System.enqueueJob(new SalesforceAccountsSyncIntacctQueueable(new List<Id>{ acc.Id }));
        Test.stopTest();
    }

    // 🧪 Mocks
    private class MockInsertCustomerResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/xml');
            res.setBody('<?xml version="1.0" encoding="UTF-8"?><response><operation><result><status>success</status><data><customer><CUSTOMERID>INT123</CUSTOMERID></customer></data></result></operation></response>');
            return res;
        }
    }

    private class MockUpdateCustomerResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/xml');
            res.setBody('<?xml version="1.0" encoding="UTF-8"?><response><operation><result><status>success</status><data><customer><CUSTOMERID>INT123</CUSTOMERID></customer></data></result></operation></response>');
            return res;
        }
    }

    private class MockErrorResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Error occurred');
            return res;
        }
    }
}
