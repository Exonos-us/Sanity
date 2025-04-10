@isTest
private class IntacctItemSyncQueueableTest {

    @isTest
    static void testQueueableExecution_WithCustomParameters() {
        Test.setMock(HttpCalloutMock.class, new MockIntacctSessionCallout());
        Test.setMock(HttpCalloutMock.class, new MockIntacctItemCallout());

        Test.startTest();
        System.enqueueJob(new IntacctItemSyncQueueable(0, '01/01/2024 00:00:00'));
        Test.stopTest();

        List<Product2> products = [SELECT Id, Name, Intacct_Item_ID__c FROM Product2];
        System.assertEquals(1, products.size());
        System.assertEquals('Test Item', products[0].Name);
        System.assertEquals('ITEM123', products[0].Intacct_Item_ID__c);
    }

    @isTest
    static void testQueueableExecution_UsingDefaultConstructor() {
        Test.setMock(HttpCalloutMock.class, new MockIntacctSessionCallout());
        Test.setMock(HttpCalloutMock.class, new MockIntacctItemCallout());

        Test.startTest();
        System.enqueueJob(new IntacctItemSyncQueueable());
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Product2]);
    }

    @isTest
    static void testQueueableExecution_NoItemsInResponse() {
        Test.setMock(HttpCalloutMock.class, new MockIntacctSessionCallout());
        Test.setMock(HttpCalloutMock.class, new MockEmptyItemResponse());

        Test.startTest();
        System.enqueueJob(new IntacctItemSyncQueueable());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Product2]);
    }

    @isTest
    static void testQueueableExecution_ErrorStatusCode() {
        Test.setMock(HttpCalloutMock.class, new MockIntacctSessionCallout());
        Test.setMock(HttpCalloutMock.class, new MockItemErrorResponse());

        Test.startTest();
        System.enqueueJob(new IntacctItemSyncQueueable());
        Test.stopTest();
    }

    private class MockIntacctSessionCallout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/xml');
            res.setBody('<?xml version="1.0" encoding="UTF-8"?>' +
                        '<response><operation><result><status>success</status>' +
                        '<data><api><sessionid>mock-session-123</sessionid></api></data>' +
                        '</result></operation></response>');
            return res;
        }
    }

    private class MockIntacctItemCallout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/xml');
            res.setBody('<?xml version="1.0" encoding="UTF-8"?>' +
                        '<response>' +
                        '  <operation>' +
                        '    <result>' +
                        '      <status>success</status>' +
                        '      <data numremaining="10">' +
                        '        <item>' +
                        '          <ITEMID>ITEM123</ITEMID>' +
                        '          <NAME>Test Item</NAME>' +
                        '          <STATUS>active</STATUS>' +
                        '        </item>' +
                        '      </data>' +
                        '    </result>' +
                        '  </operation>' +
                        '</response>');
            return res;
        }
    }

    private class MockEmptyItemResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/xml');
            res.setBody('<?xml version="1.0" encoding="UTF-8"?>' +
                        '<response><operation><result><status>success</status>' +
                        '<data numremaining="0"></data></result></operation></response>');
            return res;
        }
    }

    private class MockItemErrorResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
            return res;
        }
    }
}
