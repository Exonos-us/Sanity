@isTest
private class IntacctInvoiceSyncQueueableTest {

    @isTest
    static void testInvoiceSync_SuccessfulCallout() {
        // Mock session ID
        Test.setMock(HttpCalloutMock.class, new MockSessionCallout());
        // Mock invoice response
        Test.setMock(HttpCalloutMock.class, new MockInvoiceCallout());

        // Create related Account to match CUSTOMERID
        Account acc = new Account(Name = 'Client Test', Intacct_Customer_ID__c = 'CUST123');
        insert acc;

        Test.startTest();
        System.enqueueJob(new IntacctInvoiceSyncQueueable(0, '01/01/2024 00:00:00'));
        Test.stopTest();

        List<Intacct_Invoice__c> invoices = [SELECT Id, Name FROM Intacct_Invoice__c];
        System.assertEquals(1, invoices.size(), 'Invoice should have been inserted');
        System.assertEquals('INV123', invoices[0].Name);
    }

    @isTest
    static void testInvoiceSync_EmptyResponse() {
        Test.setMock(HttpCalloutMock.class, new MockSessionCallout());
        Test.setMock(HttpCalloutMock.class, new MockEmptyInvoiceResponse());

        Test.startTest();
        System.enqueueJob(new IntacctInvoiceSyncQueueable());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Intacct_Invoice__c]);
    }

    @isTest
    static void testInvoiceSync_StatusCodeFailure() {
        Test.setMock(HttpCalloutMock.class, new MockSessionCallout());
        Test.setMock(HttpCalloutMock.class, new MockInvoiceErrorResponse());

        Test.startTest();
        System.enqueueJob(new IntacctInvoiceSyncQueueable());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Intacct_Invoice__c]);
    }

    @isTest
    static void testInvoiceSync_UnexpectedError() {
        // ❌ No mocks set intentionally to trigger the outer catch block
        Test.startTest();
        System.enqueueJob(new IntacctInvoiceSyncQueueable());
        Test.stopTest();

        // No assertion needed, this test just ensures that the catch block is hit
        System.assertEquals(0, [SELECT COUNT() FROM Intacct_Invoice__c], 'No invoices should be inserted on failure');
    }


    private class MockSessionCallout implements HttpCalloutMock {
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

    private class MockInvoiceCallout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/xml');
            res.setBody('<?xml version="1.0" encoding="UTF-8"?>' +
                        '<response><operation><result><status>success</status>' +
                        '<data numremaining="10">' +
                        '  <arinvoice>' +
                        '    <RECORDID>INV123</RECORDID>' +
                        '    <RECORDNO>456</RECORDNO>' +
                        '    <STATE>Posted</STATE>' +
                        '    <CUSTOMERID>CUST123</CUSTOMERID>' +
                        '    <CUSTOMERNAME>ACME Inc</CUSTOMERNAME>' +
                        '    <WHENCREATED>01/01/2024</WHENCREATED>' +
                        '    <WHENPAID>01/03/2024</WHENPAID>' +
                        '    <WHENDUE>01/10/2024</WHENDUE>' +
                        '    <TERMNAME>Net 30</TERMNAME>' +
                        '    <DESCRIPTION>Test invoice</DESCRIPTION>' +
                        '    <BASECURR>USD</BASECURR>' +
                        '    <CURRENCY>USD</CURRENCY>' +
                        '    <TOTALENTERED>100.00</TOTALENTERED>' +
                        '    <TOTALPAID>100.00</TOTALPAID>' +
                        '    <TOTALDUE>0.00</TOTALDUE>' +
                        '  </arinvoice>' +
                        '</data></result></operation></response>');
            return res;
        }
    }

    private class MockEmptyInvoiceResponse implements HttpCalloutMock {
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

    private class MockInvoiceErrorResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setHeader('Content-Type', 'text/plain');
            res.setBody('Internal Server Error');
            return res;
        }
    }
}
