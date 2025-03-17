public class IntacctCustomerSyncQueueable implements Queueable, Database.AllowsCallouts {

    private static final Integer PAGE_SIZE = 10;

    private Integer offset;
    private String lastModifiedDate;

    public IntacctCustomerSyncQueueable() {
        this.offset = 0;
        this.lastModifiedDate = '01/01/2024 00:00:00';
    }

    public IntacctCustomerSyncQueueable(Integer offset, String lastModifiedDate) {
        this.offset = offset;
        this.lastModifiedDate = lastModifiedDate;
    }

    public void execute(QueueableContext context) {
        requestCustomers();
    }

    private void requestCustomers() {
        // 🔹 Retrieve credentials from Custom Metadata
        Map<String, String> credentials = IntacctSyncUtil.getIntacctCredentials();

        if (credentials == null) {
            IntacctSyncUtil.sendErrorNotification('❌ Failed to retrieve Intacct API credentials.');
            return;
        }

        try {
            String sessionId = IntacctSyncUtil.getSessionId();
            if (sessionId == null) {
                IntacctSyncUtil.sendErrorNotification('❌ Failed to retrieve Intacct session token.');
                return;
            }

            String requestBody = buildCustomerQueryRequest(sessionId, offset, credentials);

            HttpRequest req = new HttpRequest();
            req.setEndpoint(credentials.get('API_Endpoint'));
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/xml');
            req.setBody(requestBody);

            Http http = new Http();
            HttpResponse res = http.send(req);

            System.debug('🔹 Intacct Customer Query Response Code: ' + res.getStatusCode());
            System.debug('🔹 Intacct Customer Query Response Body: ' + res.getBody());

            if (res.getStatusCode() != 200) {
                IntacctSyncUtil.sendErrorNotification('❌ Intacct Customer Query failed. HTTP Code: ' + res.getStatusCode());
                return;
            }

            processCustomerResponse(res.getBody());

        } catch (Exception e) {
            IntacctSyncUtil.sendErrorNotification('❌ Error in IntacctCustomerSyncQueueable: ' + e.getMessage());
        }
    }

    private String buildCustomerQueryRequest(String sessionId, Integer offset, Map<String, String> credentials) {
        return '<?xml version="1.0" encoding="UTF-8"?>' +
               '<request>' +
               '  <control>' +
               '    <senderid>' + credentials.get('Sender_ID') + '</senderid>' +
               '    <password>' + credentials.get('Sender_Password') + '</password>' +
               '    <controlid>' + System.now().format() + '</controlid>' +
               '    <uniqueid>false</uniqueid>' +
               '    <dtdversion>3.0</dtdversion>' +
               '    <includewhitespace>false</includewhitespace>' +
               '  </control>' +
               '  <operation>' +
               '    <authentication>' +
               '      <sessionid>' + sessionId + '</sessionid>' +
               '    </authentication>' +
               '    <content>' +
               '      <function controlid="queryCustomers">' +
               '        <query>' +
               '          <object>CUSTOMER</object>' +
               '          <filter>' +
               '            <greaterthan>' +
               '              <field>WHENMODIFIED</field>' +
               '              <value>' + lastModifiedDate + '</value>' +
               '            </greaterthan>' +
               '          </filter>' +
               '          <select>' +
               '            <field>CUSTOMERID</field>' +
               '            <field>NAME</field>' +
               '            <field>STATUS</field>' +
               '            <field>CUSTTYPE</field>' +
               '            <field>DISPLAYCONTACT.CONTACTNAME</field>'+
               '            <field>DISPLAYCONTACT.PHONE1</field>' +
               '            <field>DISPLAYCONTACT.CELLPHONE</field>' +
               '            <field>DISPLAYCONTACT.MAILADDRESS.ADDRESS1</field>' +
               '            <field>DISPLAYCONTACT.MAILADDRESS.CITY</field>' +
               '            <field>DISPLAYCONTACT.MAILADDRESS.STATE</field>' +
               '            <field>DISPLAYCONTACT.MAILADDRESS.ZIP</field>' +
               '            <field>DISPLAYCONTACT.MAILADDRESS.COUNTRY</field>' +
               '          </select>' +
               '          <pagesize>' + PAGE_SIZE + '</pagesize>' +
               '          <offset>' + offset + '</offset>' +
               '        </query>' +
               '      </function>' +
               '    </content>' +
               '  </operation>' +
               '</request>';
    }

    private void processCustomerResponse(String responseBody) {
        List<String> errorMessages = new List<String>();

        try {
            Dom.Document doc = new Dom.Document();
            doc.load(responseBody);
            Dom.XmlNode root = doc.getRootElement();

            Dom.XmlNode resultNode = root.getChildElement('operation', null)
                                         ?.getChildElement('result', null);
            if (resultNode == null) {
                errorMessages.add('❌ No result node found in response.');
                return;
            }

            Dom.XmlNode dataNode = resultNode.getChildElement('data', null);
            if (dataNode == null) {
                return;
            }

            List<Account> accountsToUpsert = new List<Account>();

            for (Dom.XmlNode customerNode : dataNode.getChildElements()) {
                try {
                    String customerId = customerNode.getChildElement('CUSTOMERID', null)?.getText();
                    String name = customerNode.getChildElement('NAME', null)?.getText();

                    if (String.isBlank(customerId) || String.isBlank(name)) {
                        errorMessages.add('⚠️ Skipping record due to missing CUSTOMERID or NAME.');
                        continue;
                    }

                    Account acc = new Account();
                    acc.Intacct_Customer_ID__c = customerId;
                    acc.Name = name;
                    acc.Account_Status__c = customerNode.getChildElement('STATUS', null)?.getText();
                    acc.Type = customerNode.getChildElement('CUSTTYPE', null)?.getText();
                    acc.Intacct_Customer_Name__c = customerNode.getChildElement('DISPLAYCONTACT.CONTACTNAME', null)?.getText();
                    acc.Phone = customerNode.getChildElement('DISPLAYCONTACT.PHONE1', null)?.getText();
                    acc.BillingStreet = customerNode.getChildElement('DISPLAYCONTACT.MAILADDRESS.ADDRESS1', null)?.getText();
                    acc.BillingCity = customerNode.getChildElement('DISPLAYCONTACT.MAILADDRESS.CITY', null)?.getText();
                    acc.BillingState = customerNode.getChildElement('DISPLAYCONTACT.MAILADDRESS.STATE', null)?.getText();
                    acc.BillingPostalCode = customerNode.getChildElement('DISPLAYCONTACT.MAILADDRESS.ZIP', null)?.getText();
                    acc.BillingCountry = customerNode.getChildElement('DISPLAYCONTACT.MAILADDRESS.COUNTRY', null)?.getText();

                    accountsToUpsert.add(acc);
                } catch (Exception e) {
                    errorMessages.add('❌ Error processing customer record: ' + e.getMessage() + ' StackTrace: ' + e.getStackTraceString());
                }
            }

            if (!accountsToUpsert.isEmpty()) {
                System.debug('Accounts to update ' + accountsToUpsert);
                Database.UpsertResult[] results = Database.upsert(accountsToUpsert, Account.Intacct_Customer_ID__c, false);

                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        System.debug('✅ Successfully processed: ' + accountsToUpsert[i].Name + ' ' + accountsToUpsert[i].Intacct_Customer_ID__c);
                    } else {
                        for (Database.Error err : results[i].getErrors()) {
                            errorMessages.add('❌ Upsert error on record [' + accountsToUpsert[i].Name + ']: ' + err.getMessage());
                        }
                    }
                }
            } else {
                errorMessages.add('⚠️ No valid accounts to upsert.');
            }

            Integer numRemaining = Integer.valueOf(dataNode.getAttributeValue('numremaining', null));

            System.debug('numRemaining records: ' + numRemaining);

            // 🔹 Check if we can enqueue another job
            if (numRemaining > 0) {
                if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs() && Limits.getCallouts() < Limits.getLimitCallouts()) {
                    if (!Test.isRunningTest()) {
                       // System.enqueueJob(new IntacctCustomerSyncQueueable(offset + PAGE_SIZE, lastModifiedDate));
                    }
                } else {
                    IntacctSyncUtil.sendErrorNotification(
                        '⚠️ Limits reached - Unable to enqueue next job. ' +
                        'Queueable jobs: ' + Limits.getQueueableJobs() + ' / ' + Limits.getLimitQueueableJobs() +
                        ', Callouts: ' + Limits.getCallouts() + ' / ' + Limits.getLimitCallouts() +
                        '. Remaining records: ' + numRemaining
                    );
                }
            } else {
                System.debug('✅ No more records to process.');
            }

        } catch (Exception e) {
            errorMessages.add('❌ Critical error processing customer response: ' + e.getMessage());
        }

        if (!errorMessages.isEmpty()) {
            System.debug('Errors: ' + errorMessages);
            IntacctSyncUtil.sendErrorNotification(String.join(errorMessages, '\n'));
        }
    }
}
