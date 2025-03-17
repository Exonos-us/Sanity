public class IntacctInvoiceSyncQueueable implements Queueable, Database.AllowsCallouts {

    private static final Integer PAGE_SIZE = 10;

    private Integer offset;

    public IntacctInvoiceSyncQueueable() {
        this.offset = 0;
    }

    public IntacctInvoiceSyncQueueable(Integer offset) {
        this.offset = offset;
    }

    public void execute(QueueableContext context) {
        requestInvoices();
    }

    private void requestInvoices() {
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

            String requestBody = buildInvoiceQueryRequest(sessionId, offset, credentials);

            HttpRequest req = new HttpRequest();
            req.setEndpoint(credentials.get('API_Endpoint'));
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/xml');
            req.setBody(requestBody);

            Http http = new Http();
            HttpResponse res = http.send(req);

            System.debug('🔹 Intacct Invoice Query Response Code: ' + res.getStatusCode());
            System.debug('🔹 Intacct Invoice Query Response Body: ' + res.getBody());

            if (res.getStatusCode() != 200) {
                IntacctSyncUtil.sendErrorNotification('❌ Intacct Invoice Query failed. HTTP Code: ' + res.getStatusCode());
                return;
            }

            processInvoiceResponse(res.getBody());

        } catch (Exception e) {
            IntacctSyncUtil.sendErrorNotification('❌ Error in IntacctInvoiceSyncQueueable: ' + e.getMessage());
        }
    }

    private String buildInvoiceQueryRequest(String sessionId, Integer offset, Map<String, String> credentials) {
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
               '      <function controlid="querySalesInvoices">' +
               '        <query>' +
               '          <object>ARINVOICE</object>' +
               '          <select>' +
               '            <field>RECORDNO</field>' +
               '            <field>RECORDID</field>' +
               '            <field>STATE</field>' +
               '            <field>CUSTOMERID</field>' +
               '            <field>CUSTOMERNAME</field>' +
               '            <field>WHENCREATED</field>' +
               '            <field>WHENPOSTED</field>' +
               '            <field>WHENDUE</field>' +
               '            <field>WHENPAID</field>' +
               '            <field>TERMNAME</field>' +
               '            <field>DESCRIPTION</field>' +
               '            <field>BASECURR</field>' +
               '            <field>CURRENCY</field>' +
               '            <field>TOTALENTERED</field>' +
               '            <field>TOTALPAID</field>' +
               '            <field>TOTALDUE</field>' +
               '          </select>' +
               '          <pagesize>' + PAGE_SIZE + '</pagesize>' +
               '          <offset>' + offset + '</offset>' +
               '        </query>' +
               '      </function>' +
               '    </content>' +
               '  </operation>' +
               '</request>';
    }

    private void processInvoiceResponse(String responseBody) {
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

            // 🔸 Query Accounts for mapping CustomerID -> Account.Id
            Map<String, Account> relatedAccountsMap = new Map<String, Account>();
            for (Account acc : [SELECT Id, Intacct_Customer_ID__c FROM Account WHERE Intacct_Customer_ID__c != null]) {
                relatedAccountsMap.put(acc.Intacct_Customer_ID__c, acc);
            }

            List<Intacct_Invoice__c> invoicesToUpsert = new List<Intacct_Invoice__c>();

            for (Dom.XmlNode invoiceNode : dataNode.getChildElements()) {
                try {
                    String intacctInvoiceId = invoiceNode.getChildElement('RECORDNO', null)?.getText();

                    if (String.isBlank(intacctInvoiceId)) {
                        errorMessages.add('⚠️ Skipping invoice due to missing RECORDNO.');
                        continue;
                    }

                    Intacct_Invoice__c invoice = new Intacct_Invoice__c();

                    invoice.Intacct_Invoice_ID__c = intacctInvoiceId;
                    invoice.Name = invoiceNode.getChildElement('RECORDID', null)?.getText();
                    invoice.Invoce_State__c = invoiceNode.getChildElement('STATE', null)?.getText();
                    invoice.Invoice_Description__c = invoiceNode.getChildElement('DESCRIPTION', null)?.getText();
                    invoice.Terms__c = invoiceNode.getChildElement('TERMNAME', null)?.getText();
                    invoice.Date_Created__c = parseDate(invoiceNode.getChildElement('WHENCREATED', null)?.getText());
                    invoice.Date_Paid__c = parseDate(invoiceNode.getChildElement('WHENPAID', null)?.getText());
                    invoice.Due_Date__c = parseDate(invoiceNode.getChildElement('WHENDUE', null)?.getText());
                    invoice.Total_Entered__c = invoiceNode.getChildElement('TOTALENTERED', null)?.getText();
                    invoice.Total_Paid__c = invoiceNode.getChildElement('TOTALPAID', null)?.getText();
                    invoice.Total_Due__c = invoiceNode.getChildElement('TOTALDUE', null)?.getText();

                    String customerId = invoiceNode.getChildElement('CUSTOMERID', null)?.getText();
                    if (!String.isBlank(customerId)) {
                        Account relatedAccount = relatedAccountsMap.get(customerId);
                        if (relatedAccount != null) {
                            invoice.Customer__c = relatedAccount.Id;
                        } else {
                            errorMessages.add('⚠️ No matching Account found for CustomerID: ' + customerId);
                        }
                    }

                    invoicesToUpsert.add(invoice);

                } catch (Exception e) {
                    errorMessages.add('❌ Error processing invoice record: ' + e.getMessage());
                }
            }

            if (!invoicesToUpsert.isEmpty()) {
                Database.UpsertResult[] results = Database.upsert(invoicesToUpsert, Intacct_Invoice__c.Intacct_Invoice_ID__c, false);

                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        System.debug('✅ Upserted invoice: ' + invoicesToUpsert[i].Name);
                    } else {
                        for (Database.Error err : results[i].getErrors()) {
                            errorMessages.add('❌ Upsert error on Invoice [' + invoicesToUpsert[i].Name + ']: ' + err.getMessage());
                        }
                    }
                }
            }

            Integer numRemaining = Integer.valueOf(dataNode.getAttributeValue('numremaining', null));

            if (numRemaining > 0) {
                if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs() && Limits.getCallouts() < Limits.getLimitCallouts()) {
                    //System.enqueueJob(new IntacctInvoiceSyncQueueable(offset + PAGE_SIZE));
                } else {
                    IntacctSyncUtil.sendErrorNotification('⚠️ Limits reached - Unable to enqueue next invoice job.');
                }
            }

        } catch (Exception e) {
            errorMessages.add('❌ Critical error processing invoice response: ' + e.getMessage());
        }

        if (!errorMessages.isEmpty()) {
            IntacctSyncUtil.sendErrorNotification(String.join(errorMessages, '\n'));
        }
    }

    private Date parseDate(String dateStr) {
        if (String.isBlank(dateStr)) return null;
        try {
            List<String> parts = dateStr.split('/');
            if (parts.size() == 3) {
                return Date.newInstance(Integer.valueOf(parts[2]), Integer.valueOf(parts[0]), Integer.valueOf(parts[1]));
            }
        } catch (Exception e) {
            System.debug('⚠️ Date parse error: ' + dateStr);
        }
        return null;
    }

    private Decimal parseDecimal(String decimalStr) {
        if (String.isBlank(decimalStr)) return null;
        try {
            return Decimal.valueOf(decimalStr);
        } catch (Exception e) {
            System.debug('⚠️ Decimal parse error: ' + decimalStr);
        }
        return null;
    }
}
