@isTest
private class IntacctInvoiceSyncSchedulerTest {

    @isTest
    static void testExecuteScheduler() {
        // Prepare mock callouts
        Test.setMock(HttpCalloutMock.class, new MockSessionCallout());
        Test.setMock(HttpCalloutMock.class, new MockInvoiceCallout());

        // Related Account for CUSTOMERID
        Account acc = new Account(Name = 'ACME', Intacct_Customer_ID__c = 'CUST123');
        insert acc;

        // Execute the scheduler
        Test.startTest();
        String cronExp = '0 0 0 1 1 ? 2050'; // Arbitrary future date
        System.schedule('Test Invoice Scheduler', cronExp, new IntacctInvoiceSyncScheduler());
        Test.stopTest();

    }

    // -- Mocks --
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
                '<data numremaining="0">' +
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
}
