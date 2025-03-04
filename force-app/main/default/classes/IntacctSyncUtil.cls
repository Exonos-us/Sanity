public class IntacctSyncUtil {

    // 🔹 Load credentials from Custom Metadata or Custom Settings
    private static final String SENDER_ID = 'Sanity1720';  // TODO: Store in Custom Metadata
    private static final String SENDER_PASSWORD = 'Cloudstreet2025!';  // TODO: Store securely
    private static final String USER_PASSWORD = 'v4ZRi%s63pp';  // TODO: Store securely
    private static final String COMPANY_ID = 'Sanity1720';  // TODO: Store in Custom Metadata
    private static final String USER_ID = 'workato_isu';  // TODO: Store in Custom Metadata
    private static final String API_ENDPOINT = 'https://api.intacct.com/ia/xml/xmlgw.phtml';

    /**
     * 🔹 Retrieves the session ID for Intacct API authentication.
     * @return Session ID string or null if authentication fails.
     */
    public static String getSessionId() {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(API_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/xml');
    
            String body = '<?xml version="1.0" encoding="UTF-8"?>' +
                        '<request>' +
                        '  <control>' +
                        '    <senderid>' + SENDER_ID + '</senderid>' +
                        '    <password>' + SENDER_PASSWORD + '</password>' +
                        '    <controlid>session_request</controlid>' +
                        '    <uniqueid>false</uniqueid>' +
                        '    <dtdversion>3.0</dtdversion>' +
                        '    <includewhitespace>false</includewhitespace>' +
                        '  </control>' +
                        '  <operation>' +
                        '    <authentication>' +
                        '      <login>' +
                        '        <userid>' + USER_ID + '</userid>' +
                        '        <companyid>' + COMPANY_ID + '</companyid>' +
                        '        <password>' + USER_PASSWORD + '</password>' +
                        '      </login>' +
                        '    </authentication>' +
                        '    <content>' +
                        '      <function controlid="session_request">' +
                        '        <getAPISession />' +
                        '      </function>' +
                        '    </content>' +
                        '  </operation>' +
                        '</request>';

    
            req.setBody(body);
            Http http = new Http();
            HttpResponse res = http.send(req);
    
            System.debug('🔹 Intacct API Response Code: ' + res.getStatusCode());
            System.debug('🔹 Intacct API Response Body: ' + res.getBody());

            if (res.getStatusCode() == 200) {
                Dom.Document doc = new Dom.Document();
                doc.load(res.getBody());
                Dom.XmlNode root = doc.getRootElement();

                Dom.XmlNode operationNode = root.getChildElement('operation', null);
                if (operationNode == null) {
                    return null;
                }

                Dom.XmlNode authenticationNode = operationNode.getChildElement('authentication', null);
                if (authenticationNode == null) {
                    return null;
                }

                Dom.XmlNode authStatusNode = authenticationNode.getChildElement('status', null);
                if (authStatusNode == null || authStatusNode.getText() != 'success') {
                    System.debug('❌ Error: Authentication failed in Intacct API.');
                    sendErrorNotification('Authentication failed in Intacct API. Status: ' + (authStatusNode != null ? authStatusNode.getText() : 'N/A'));
                    return null;
                }

                Dom.XmlNode sessionIdNode = root.getChildElement('operation', null)
                ?.getChildElement('result', null)
                ?.getChildElement('data', null)
                ?.getChildElement('api', null)
                ?.getChildElement('sessionid', null);
                if (sessionIdNode == null) {
                    sendErrorNotification('Session ID not found in response.');
                    return null;
                }

                String sessionId = sessionIdNode.getText();
                System.debug('✅ Session ID Retrieved: ' + sessionId);
                return sessionId;


            }
        } catch (Exception e) {
            System.debug('❌ Authentication Error: ' + e.getMessage());
            sendErrorNotification('Authentication Failed: ' + e.getMessage());
        }
        return null;
    }

    /**
     * 🔹 Sends an email notification in case of errors.
     * @param message The error message to be sent.
     */
    public static void sendErrorNotification(String message) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{'admin@example.com'});  // TODO: Replace with actual email
        email.setSubject('🚨 Intacct Sync Error');
        email.setPlainTextBody('An error occurred: ' + message);
        Messaging.sendEmail(new List<Messaging.Email> {email});
    }

    
}
