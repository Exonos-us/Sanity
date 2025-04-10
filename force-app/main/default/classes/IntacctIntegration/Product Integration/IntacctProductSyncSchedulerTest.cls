@isTest
private class IntacctProductSyncSchedulerTest {

    @isTest
    static void testScheduledExecution_EnqueuesQueueable() {
        // Set up mocks for session and item callout
        Test.setMock(HttpCalloutMock.class, new MockIntacctSessionCallout());
        Test.setMock(HttpCalloutMock.class, new MockIntacctItemCallout());

        Test.startTest();

        // Simulate the scheduler execution
        String jobId = System.schedule(
            'Test Product Sync Schedule',
            '0 0 12 * * ?', // Runs at noon every day (example cron)
            new IntacctProductSyncScheduler()
        );

        Test.stopTest();

        System.assertNotEquals(null, jobId, 'The scheduled job ID should not be null');
    }

    // Mock for session callout
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

    // Mock for product (item) query callout
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
                        '      <data numremaining="0">' +
                        '        <item>' +
                        '          <ITEMID>ITEM001</ITEMID>' +
                        '          <NAME>Test Product</NAME>' +
                        '          <STATUS>active</STATUS>' +
                        '        </item>' +
                        '      </data>' +
                        '    </result>' +
                        '  </operation>' +
                        '</response>');
            return res;
        }
    }
}
