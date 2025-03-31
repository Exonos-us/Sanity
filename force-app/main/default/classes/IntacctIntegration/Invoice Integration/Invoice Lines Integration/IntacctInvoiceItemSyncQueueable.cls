public with sharing class IntacctInvoiceItemSyncQueueable implements Queueable, Database.AllowsCallouts {

    private List<Intacct_Invoice__c> invoices;
    private static final Integer PAGE_SIZE = 100;

    public IntacctInvoiceItemSyncQueueable(List<Intacct_Invoice__c> invoices) {
        this.invoices = invoices;
    }

    public void execute(QueueableContext context) {
        if (invoices.isEmpty()) {
            System.debug('⚠️ No invoices to process.');
            return;
        }

        List<String> invoiceIds = new List<String>();
        for (Intacct_Invoice__c invoice : invoices) {
            if (!String.isBlank(invoice.Intacct_Invoice_ID__c)) {
                invoiceIds.add(invoice.Intacct_Invoice_ID__c);
            }
        }

        if (invoiceIds.isEmpty()) {
            System.debug('⚠️ No valid RECORDNO found to process.');
            return;
        }

        try {
            // Retrieve credentials and session
            Map<String, String> credentials = IntacctSyncUtil.getIntacctCredentials();
            if (credentials == null) {
                IntacctSyncUtil.sendErrorNotification('❌ Failed to retrieve Intacct API credentials.');
                return;
            }

            String sessionId = IntacctSyncUtil.getSessionId();
            if (sessionId == null) {
                IntacctSyncUtil.sendErrorNotification('❌ Failed to retrieve Intacct session token.');
                return;
            }

            // Build request with all RECORDNOs separated by comma
            String requestBody = buildInvoiceItemQueryRequest(sessionId, String.join(invoiceIds, ','), credentials);
            HttpResponse res = sendHttpRequest(requestBody, credentials);

            System.debug('🔹 Intacct Invoice Item Query Response Code: ' + res.getStatusCode());
            System.debug('🔹 Intacct Invoice Item Query Response Body: ' + res.getBody());

            if (res.getStatusCode() != 200) {
                IntacctSyncUtil.sendErrorNotification('❌ Intacct Invoice Item Query failed. HTTP Code: ' + res.getStatusCode());
            } else {
                System.debug('✅ Invoice Items Request Completed Successfully');
            }
        } catch (Exception e) {
            IntacctSyncUtil.sendErrorNotification('❌ Error in IntacctInvoiceItemSyncQueueable: ' + e.getMessage());
        }
    }

    private HttpResponse sendHttpRequest(String requestBody, Map<String, String> credentials) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(credentials.get('API_Endpoint'));
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/xml');
        req.setBody(requestBody);

        Http http = new Http();
        return http.send(req);
    }

    private String buildInvoiceItemQueryRequest(String sessionId, String recordIds, Map<String, String> credentials) {
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
               '      <function controlid="readInvoiceDetails">' +
               '        <read>' +
               '          <object>ARINVOICE</object>' +
               '          <keys>' + recordIds + '</keys>' +
               '          <fields>*</fields>' +
               '        </read>' +
               '      </function>' +
               '    </content>' +
               '  </operation>' +
               '</request>';
    }
}
