@isTest
private class IntacctSyncUtilTest {

    @testSetup
    static void setupData() {
        String uniqueUsername = 'testuser-' + DateTime.now().getTime() + '@example.com';

        User u = new User(
            Username = uniqueUsername,
            Email = 'testuser@example.com',
            LastName = 'User',
            Alias = 'tuser',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = UserInfo.getProfileId(),
            LanguageLocaleKey = 'en_US'
        );
        insert u;

        Group g = new Group(Name = 'IntacctSyncAdmins', Type = 'Regular');
        insert g;

        GroupMember gm = new GroupMember(GroupId = g.Id, UserOrGroupId = u.Id);
        insert gm;

    }

    @isTest
    static void testGetIntacctCredentials() {
        Map<String, String> creds = IntacctSyncUtil.getIntacctCredentials();
        System.assertNotEquals(null, creds);
    }

    @isTest
    static void testGetSessionId_Successful() {
        // 🧪 Activamos modo completo para evitar Test.isRunningTest() early return
        IntacctSyncUtil.overrideTestMode = true;

        Test.setMock(HttpCalloutMock.class, new MockSessionCallout());

        Test.startTest();
        String sessionId = IntacctSyncUtil.getSessionId();
        Test.stopTest();

        System.assertEquals('mocked-session-123', sessionId, 'Session ID should be mocked');
    }

    @isTest
    static void testSendErrorNotification() {
        Test.startTest();
        IntacctSyncUtil.overrideTestMode = true;
        IntacctSyncUtil.sendErrorNotification('❌ Test error message');
        Test.stopTest();
    }

    @isTest
    static void testLogSyncError() {
        Test.startTest();
        IntacctSyncUtil.logSyncError('Invoice', 'Something failed badly');
        Test.stopTest();

        Intacct_Error_Log__c log = [SELECT Id, Message__c FROM Intacct_Error_Log__c LIMIT 1];
        System.assert(log.Message__c.contains('Something failed'));
    }

    private class MockSessionCallout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/xml');
            res.setBody('<?xml version="1.0" encoding="UTF-8"?>' +
                        '<response><operation><result><status>success</status>' +
                        '<data><api><sessionid>mocked-session-123</sessionid></api></data>' +
                        '</result></operation></response>');
            return res;
        }
    }
}
