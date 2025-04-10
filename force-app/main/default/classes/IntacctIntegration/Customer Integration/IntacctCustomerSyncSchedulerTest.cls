@isTest
private class IntacctCustomerSyncSchedulerTest {

    @isTest
    static void testScheduledExecution_EnqueuesQueueable() {
        // Set required mocks
        Test.setMock(HttpCalloutMock.class, new MockIntacctSessionCallout());
        Test.setMock(HttpCalloutMock.class, new MockIntacctCustomerCallout());

        // Create the instance of the scheduler
        IntacctCustomerSyncScheduler scheduler = new IntacctCustomerSyncScheduler();

        Test.startTest();
        // Simulate the scheduled execution
        scheduler.execute(null);
        Test.stopTest();

        // Assert the Account was inserted from the queueable run
        List<Account> accounts = [SELECT Id, Name FROM Account];
        System.assertEquals(1, accounts.size());
        System.assertEquals('Test Customer', accounts[0].Name);
    }

    // ---- Required mocks ----

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

    private class MockIntacctCustomerCallout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/xml');
            res.setBody('<?xml version="1.0" encoding="UTF-8"?>' +
                        '<response>' +
                        '  <operation>' +
                        '    <result>' +
                        '      <status>success</status>' +
                        '      <data numremaining="0">' +
                        '        <customer>' +
                        '          <CUSTOMERID>CUST123</CUSTOMERID>' +
                        '          <NAME>Test Customer</NAME>' +
                        '          <STATUS>active</STATUS>' +
                        '          <CUSTTYPE>Retail</CUSTTYPE>' +
                        '          <DISPLAYCONTACT.CONTACTNAME>John Doe</DISPLAYCONTACT.CONTACTNAME>' +
                        '          <DISPLAYCONTACT.PHONE1>123-456-7890</DISPLAYCONTACT.PHONE1>' +
                        '          <DISPLAYCONTACT.MAILADDRESS.ADDRESS1>123 Main St</DISPLAYCONTACT.MAILADDRESS.ADDRESS1>' +
                        '          <DISPLAYCONTACT.MAILADDRESS.CITY>San Jose</DISPLAYCONTACT.MAILADDRESS.CITY>' +
                        '          <DISPLAYCONTACT.MAILADDRESS.STATE>CR</DISPLAYCONTACT.MAILADDRESS.STATE>' +
                        '          <DISPLAYCONTACT.MAILADDRESS.ZIP>10101</DISPLAYCONTACT.MAILADDRESS.ZIP>' +
                        '          <DISPLAYCONTACT.MAILADDRESS.COUNTRY>Costa Rica</DISPLAYCONTACT.MAILADDRESS.COUNTRY>' +
                        '        </customer>' +
                        '      </data>' +
                        '    </result>' +
                        '  </operation>' +
                        '</response>');
            return res;
        }
    }
}
