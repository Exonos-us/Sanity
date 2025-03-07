public class SalesforceAccountsSyncIntacctQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> accountIdsToProcess;
    private static final String API_ENDPOINT = 'https://api.intacct.com/ia/xml/xmlgw.phtml';

    public SalesforceAccountsSyncIntacctQueueable(List<Id> accountIds) {
        this.accountIdsToProcess = accountIds;
    }

    public void execute(QueueableContext context) {
        try {
            processAccounts();
        } catch (Exception e) {
            System.debug('❌ Error in execute: ' + e.getMessage());
            IntacctSyncUtil.sendErrorNotification('❌ Error in SalesforceAccountsSyncIntacctQueueable: ' + e.getMessage());
        }
    }

    private void processAccounts() {
        if (accountIdsToProcess.isEmpty()) {
            System.debug('✅ No more accounts to process.');
            return;
        }

        Id accountId = accountIdsToProcess.remove(0); // Get first record

        try {
            // 🔹 Query account to ensure it's editable
            Account acc = [SELECT Id, Name, Intacct_Customer_ID__c, Phone, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry 
                           FROM Account WHERE Id = :accountId LIMIT 1];

            if (String.isBlank(acc.Intacct_Customer_ID__c)) {
                // 🔹 Insert new customer in Intacct
                String customerId = insertCustomerInIntacct(acc);
                if (customerId != null) {
                    acc.Intacct_Customer_ID__c = customerId;
                    update acc;
                    System.debug('✅ Updated Salesforce Account with Intacct Customer ID: ' + customerId);
                }
            } else {
                System.debug('Skipping update logic for now');
            }

        } catch (Exception e) {
            System.debug('❌ Error processing account ' + accountId + ': ' + e.getMessage());
            IntacctSyncUtil.sendErrorNotification('❌ Error processing account ' + accountId + ': ' + e.getMessage());
        }

        // 🔄 Enqueue next record if there are more to process
        if (!accountIdsToProcess.isEmpty() && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new SalesforceAccountsSyncIntacctQueueable(accountIdsToProcess));
        }
    }

    // 🔹 Inserts a new customer into Intacct
    private String insertCustomerInIntacct(Account acc) {
        String requestBody = buildInsertRequest(acc);

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(API_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/xml');
            req.setBody(requestBody);

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                return parseInsertResponse(res.getBody());
            } else {
                System.debug('❌ Insert failed: ' + res.getBody());
                IntacctSyncUtil.sendErrorNotification('❌ Insert failed for Account ' + acc.Name + ': ' + res.getBody());
            }
        } catch (Exception e) {
            System.debug('❌ Callout error: ' + e.getMessage());
            IntacctSyncUtil.sendErrorNotification('❌ Callout error: ' + e.getMessage());
        }

        return null;
    }

    // 🔹 Parses the response from Intacct and retrieves CUSTOMERID
    private String parseInsertResponse(String xmlResponse) {
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
                    return customerNode.getChildElement('CUSTOMERID', null).getText();
                }
            }
        } catch (Exception e) {
            System.debug('❌ XML Parsing error: ' + e.getMessage());
            IntacctSyncUtil.sendErrorNotification('❌ XML Parsing error: ' + e.getMessage());
        }

        return null;
    }

    // 🔹 Builds XML Request for Inserting a Customer
    private String buildInsertRequest(Account acc) {
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
            '      <function controlid="createCustomer">' +
            '        <create>' +
            '          <CUSTOMER>' +
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
            '        </create>' +
            '      </function>' +
            '    </content>' +
            '  </operation>' +
            '</request>';
    }

    private String safeString(String value) {
        return value == null ? '' : value.escapeXml();
    }
}
