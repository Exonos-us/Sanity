public class IntacctSyncUtil {

    
    @TestVisible
    public static Boolean overrideTestMode = false;

    /**
     * 🔹 Retrieves Intacct API credentials from Custom Metadata
     * @return Map<String, String> containing credentials
     */
    public static Map<String, String> getIntacctCredentials() {
        if (Test.isRunningTest()) {
            return new Map<String, String>{
                'Sender_ID' => 'test',
                'Sender_Password' => 'test',
                'User_Password' => 'test',
                'Company_ID' => 'test',
                'User_ID' => 'test',
                'API_Endpoint' => 'https://mock.endpoint'
            };
        }
    
        // Otherwise use real metadata
        IntacctSettings__mdt settings = [
            SELECT Sender_ID__c, Sender_Password__c, User_Password__c,
                   Company_ID__c, User_ID__c, API_Endpoint__c
            FROM IntacctSettings__mdt
            LIMIT 1
        ];
    
        return new Map<String, String>{
            'Sender_ID' => settings.Sender_ID__c,
            'Sender_Password' => settings.Sender_Password__c,
            'User_Password' => settings.User_Password__c,
            'Company_ID' => settings.Company_ID__c,
            'User_ID' => settings.User_ID__c,
            'API_Endpoint' => settings.API_Endpoint__c
        };
    }
    

    /**
     * 🔹 Retrieves the session ID for Intacct API authentication.
     * @return Session ID string or null if authentication fails.
     */
    public static String getSessionId() {
        // 🔹 Return mock session ID when running tests
        if (Test.isRunningTest() && !overrideTestMode) {
            return 'mocked-session-id';
        }
    
        Map<String, String> credentials = getIntacctCredentials();
        if (credentials == null) return null;
    
        try {
            String requestBody = '<?xml version="1.0" encoding="UTF-8"?>' +
                        '<request>' +
                        '  <control>' +
                        '    <senderid>' + credentials.get('Sender_ID') + '</senderid>' +
                        '    <password>' + credentials.get('Sender_Password') + '</password>' +
                        '    <controlid>session_request</controlid>' +
                        '    <uniqueid>false</uniqueid>' +
                        '    <dtdversion>3.0</dtdversion>' +
                        '    <includewhitespace>false</includewhitespace>' +
                        '  </control>' +
                        '  <operation>' +
                        '    <authentication>' +
                        '      <login>' +
                        '        <userid>' + credentials.get('User_ID') + '</userid>' +
                        '        <companyid>' + credentials.get('Company_ID') + '</companyid>' +
                        '        <password>' + credentials.get('User_Password') + '</password>' +
                        '      </login>' +
                        '    </authentication>' +
                        '    <content>' +
                        '      <function controlid="session_request">' +
                        '        <getAPISession />' +
                        '      </function>' +
                        '    </content>' +
                        '  </operation>' +
                        '</request>';
    
            HttpRequest req = new HttpRequest();
            req.setEndpoint(credentials.get('API_Endpoint'));
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/xml');
            req.setBody(requestBody);
    
            Http http = new Http();
            HttpResponse res = http.send(req);
    
            System.debug('🔹 Intacct API Response Code: ' + res.getStatusCode());
            System.debug('🔹 Intacct API Response Body: ' + res.getBody());
    
            if (res.getStatusCode() == 200) {
                Dom.Document doc = new Dom.Document();
                doc.load(res.getBody());
                Dom.XmlNode root = doc.getRootElement();
    
                Dom.XmlNode sessionIdNode = root.getChildElement('operation', null)
                    ?.getChildElement('result', null)
                    ?.getChildElement('data', null)
                    ?.getChildElement('api', null)
                    ?.getChildElement('sessionid', null);
                
                if (sessionIdNode == null) {
                    sendErrorNotification('❌ Session ID not found in response.');
                    return null;
                }
    
                String sessionId = sessionIdNode.getText();
                System.debug('✅ Session ID Retrieved: ' + sessionId);
                return sessionId;
            }
        } catch (Exception e) {
            System.debug('❌ Authentication Error: ' + e.getMessage());
            sendErrorNotification('❌ Authentication Failed: ' + e.getMessage());
        }
        return null;
    }
    

    /**
     * 🔹 Sends an email notification in case of errors to all users in the 'IntacctSyncAdmins' public group.
     * @param message The error message to be sent.
     */
    public static void sendErrorNotification(String message) {
        // ✅ Skip email logic when running tests
        if (Test.isRunningTest() && !overrideTestMode) {
            System.debug('📩 Test mode: Skipping actual email send.');
            return;
        }
    
        List<String> recipientEmails = new List<String>();
    
        for (GroupMember gm : [SELECT UserOrGroupId FROM GroupMember WHERE Group.Name = 'IntacctSyncAdmins']) {
            List<User> users = [SELECT Email FROM User WHERE Id = :gm.UserOrGroupId AND Email != null];
            for (User user : users) {
                recipientEmails.add(user.Email);
            }
        }
    
        if (recipientEmails.isEmpty()) {
            System.debug('⚠️ No recipients found in IntacctSyncAdmins Public Group.');
            return;
        }
    
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(recipientEmails);
        email.setSubject('🚨 Intacct Sync Error');
        email.setPlainTextBody('An error occurred: ' + message);
        Messaging.sendEmail(new List<Messaging.Email> { email });
    
        System.debug('📩 Sent error notification to: ' + recipientEmails);
    }
    

    public static void logSyncError(String module, String message) {
        try {
            Intacct_Error_Log__c errorLog = new Intacct_Error_Log__c();
            errorLog.Module__c = module;    
            if (!String.isBlank(message)) {
                errorLog.Message__c = message.length() > 32000 ? message.substring(0, 32000) : message;
            }
    
            insert errorLog;
            System.debug('📝 Error log inserted: ' + message);
        } catch (Exception e) {
            System.debug('❌ Failed to log error: ' + e.getMessage());
        }
    }
    
}