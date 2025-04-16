public class SalesforceAccountsSyncIntacctQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> accountIdsToProcess;
    private static final String API_ENDPOINT = 'https://api.intacct.com/ia/xml/xmlgw.phtml';

    public SalesforceAccountsSyncIntacctQueueable(List<Id> accountIds) {
        this.accountIdsToProcess = accountIds;
    }

    public void execute(QueueableContext context) {
        try {
            processNextAccount();
        } catch (Exception e) {
            String msg = '❌ Error in SalesforceAccountsSyncIntacctQueueable: ' + e.getMessage();
            IntacctSyncUtil.logSyncError('Account Sync', msg, 'execute', 'SalesforceAccountsSyncIntacctQueueable');            
        }
    }

    private void processNextAccount() {
        if (accountIdsToProcess.isEmpty()) {
            System.debug('✅ No more accounts to process.');
            return;
        }

        Id accountId = accountIdsToProcess.remove(0);

        try {
            Account acc = [SELECT Id, Name, Intacct_Customer_ID__c, Phone, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry 
                           FROM Account WHERE Id = :accountId LIMIT 1];

            if (String.isBlank(acc.Intacct_Customer_ID__c)) {
                // 🔹 Insert new customer in Intacct
                String customerId = syncCustomerInIntacct(acc, true);
                if (customerId != null) {
                    acc.Intacct_Customer_ID__c = customerId;
                    update acc;
                    System.debug('✅ Inserted and updated Salesforce Account with Intacct Customer ID: ' + customerId);
                }
            } else {
                // 🔹 Update existing customer in Intacct
                syncCustomerInIntacct(acc, false);
                System.debug('✅ Updated existing customer in Intacct: ' + acc.Intacct_Customer_ID__c);
            }

        } catch (Exception e) {
            String msg = '❌ Error processing account ' + accountId + ': ' + e.getMessage();
            IntacctSyncUtil.logSyncError('Account Sync', msg, 'processNextAccount', 'SalesforceAccountsSyncIntacctQueueable');   
            Account accError = new Account(Id = accountId);
            accError.Intacct_Sync_Error__c = e.getMessage();
            update accError;        
        }

        // ✅ Validate limits before enqueuing the next record
        if (!accountIdsToProcess.isEmpty()) {
            if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs() && Limits.getCallouts() < Limits.getLimitCallouts()) {
                System.enqueueJob(new SalesforceAccountsSyncIntacctQueueable(accountIdsToProcess));
            } else {
                System.debug('⚠️ Queueable job or callout limit reached. Next job not enqueued.');
                IntacctSyncUtil.sendErrorNotification('⚠️ Queueable job or callout limit reached. Unable to enqueue next job.');
            }
        }
    }

    // 🔹 Inserts or Updates a customer in Intacct
    private String syncCustomerInIntacct(Account acc, Boolean isInsert) {
        String requestBody = buildRequest(acc, isInsert);

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(API_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/xml');
            req.setBody(requestBody);

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                return parseResponse(res.getBody(), isInsert);
            } else {
                String msg = '❌ ' + (isInsert ? 'Insert' : 'Update') + ' failed for Account ' + acc.Name + ': ' + res.getBody();
                IntacctSyncUtil.logSyncError('Account Sync', msg, 'syncCustomerInIntacct', 'SalesforceAccountsSyncIntacctQueueable');                
            }
        } catch (Exception e) {
            String msg = '❌ Callout error for Account ' + acc.Name + ': ' + e.getMessage();
            IntacctSyncUtil.logSyncError('Account Sync', msg, 'syncCustomerInIntacct', 'SalesforceAccountsSyncIntacctQueueable');
        }

        return null;
    }

    // 🔹 Parses the response from Intacct
    private String parseResponse(String xmlResponse, Boolean isInsert) {
        try {
            Dom.Document doc = new Dom.Document();
            doc.load(xmlResponse);

            Dom.XmlNode root = doc.getRootElement();
            Dom.XmlNode dataNode = root.getChildElement('operation', null)
                .getChildElement('result', null)
                .getChildElement('data', null);

            if (dataNode != null) {
                Dom.XmlNode customerNode = dataNode.getChildElement('customer', null);
                if (customerNode != null) {
                    String customerId = customerNode.getChildElement('CUSTOMERID', null).getText();
                    return customerId;
                }
            }
        } catch (Exception e) {
            String msg = '❌ XML Parsing error: ' + e.getMessage();
            IntacctSyncUtil.logSyncError('Account Sync', msg, 'parseResponse', 'SalesforceAccountsSyncIntacctQueueable');            
        }

        return null;
    }

    // 🔹 Builds XML Request for Insert or Update
    private String buildRequest(Account acc, Boolean isInsert) {
        String operationType = isInsert ? 'create' : 'update';
        String controlId = isInsert ? 'createCustomer' : 'updateCustomer';

        return '<?xml version="1.0" encoding="UTF-8"?>' +
            '<request>' +
            '  <control>' +
            '    <senderid>Sanity1720</senderid>' +
            '    <password>Cloudstreet2025!</password>' +
            '    <controlid>' + System.currentTimeMillis() + '</controlid>' +
            '    <uniqueid>false</uniqueid>' +
            '    <dtdversion>3.0</dtdversion>' +
            '    <includewhitespace>false</includewhitespace>' +
            '  </control>' +
            '  <operation>' +
            '    <authentication>' +
            '      <sessionid>' + IntacctSyncUtil.getSessionId() + '</sessionid>' +
            '    </authentication>' +
            '    <content>' +
            '      <function controlid="' + controlId + '">' +
            '        <' + operationType + '>' +
            '          <CUSTOMER>' +
            (isInsert ? '' : '            <CUSTOMERID>' + acc.Intacct_Customer_ID__c + '</CUSTOMERID>') +
            '            <NAME>' + acc.Name + '</NAME>' +
            '            <STATUS>active</STATUS>' +
            '            <DISPLAYCONTACT>' +
            '              <PHONE1>' + safeString(acc.Phone) + '</PHONE1>' +
            '              <MAILADDRESS>' +
            '                <ADDRESS1>' + safeString(acc.BillingStreet) + '</ADDRESS1>' +
            '                <CITY>' + safeString(acc.BillingCity) + '</CITY>' +
            '                <STATE>' + safeString(acc.BillingState) + '</STATE>' +
            '                <ZIP>' + safeString(acc.BillingPostalCode) + '</ZIP>' +
            '                <COUNTRY>' + safeString(acc.BillingCountry) + '</COUNTRY>' +
            '              </MAILADDRESS>' +
            '            </DISPLAYCONTACT>' +
            '            <TAXABLE>true</TAXABLE>' +
            '            <CURRENCY>USD</CURRENCY>' +
            '          </CUSTOMER>' +
            '        </' + operationType + '>' +
            '      </function>' +
            '    </content>' +
            '  </operation>' +
            '</request>';
    }

    private String safeString(String value) {
        return value == null ? '' : value.escapeXml();
    }
}
