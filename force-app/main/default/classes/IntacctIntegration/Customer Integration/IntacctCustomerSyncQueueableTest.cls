@isTest
private class IntacctCustomerSyncQueueableTest {

    @isTest
    static void testQueueableExecution_WithCustomParameters() {
        // First mock: Session response
        Test.setMock(HttpCalloutMock.class, new MockIntacctSessionCallout());

        // Second mock: Customer data response
        Test.setMock(HttpCalloutMock.class, new MockIntacctCustomerCallout());

        Test.startTest();
        System.enqueueJob(new IntacctCustomerSyncQueueable(0, '01/01/2024 00:00:00'));
        Test.stopTest();

        List<Account> accounts = [SELECT Id, Name FROM Account];
        System.assertEquals(1, accounts.size());
        System.assertEquals('Test Customer', accounts[0].Name);
    }

    @isTest
    static void testQueueableExecution_UsingDefaultConstructor() {
        Test.setMock(HttpCalloutMock.class, new MockIntacctSessionCallout());
        Test.setMock(HttpCalloutMock.class, new MockIntacctCustomerCallout());

        Test.startTest();
        System.enqueueJob(new IntacctCustomerSyncQueueable());
        Test.stopTest();

        List<Account> accounts = [SELECT Id FROM Account];
        System.assertEquals(1, accounts.size());
    }

    @isTest
    static void testQueueableExecution_NoCustomersInResponse() {
        Test.setMock(HttpCalloutMock.class, new MockIntacctSessionCallout());
        Test.setMock(HttpCalloutMock.class, new MockEmptyCustomerResponse());

        Test.startTest();
        System.enqueueJob(new IntacctCustomerSyncQueueable());
        Test.stopTest();

        List<Account> accounts = [SELECT Id FROM Account];
        System.assertEquals(0, accounts.size());
    }

    @isTest
    static void testQueueableExecution_MissingCredentials() {
        IntacctSettings__mdt setting  = [SELECT Id FROM IntacctSettings__mdt LIMIT 1 ];
        

        Test.startTest();
        System.enqueueJob(new IntacctCustomerSyncQueueable());
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
                        '      <data numremaining="10">' +
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

    private class MockEmptyCustomerResponse implements HttpCalloutMock {
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
}
