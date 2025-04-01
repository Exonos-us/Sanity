public class IntacctInvoiceItemSyncQueueable implements Queueable, Database.AllowsCallouts {

    private List<Intacct_Invoice__c> invoices;

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
            if (!String.isBlank(invoice.Intacct_Invoice_Key__c)) {
                invoiceIds.add(invoice.Intacct_Invoice_Key__c);
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

            // Build request
            String requestBody = buildInvoiceItemQueryRequest(sessionId, invoiceIds, credentials);
            HttpResponse res = sendHttpRequest(requestBody, credentials);

            System.debug('🔹 Intacct Invoice Item Query Response Code: ' + res.getStatusCode());
            System.debug('🔹 Intacct Invoice Item Query Response Body: ' + res.getBody());

            if (res.getStatusCode() != 200) {
                IntacctSyncUtil.sendErrorNotification('❌ Intacct Invoice Item Query failed. HTTP Code: ' + res.getStatusCode());
                return;
            }

            processInvoiceItemResponse(res.getBody());
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

    private String buildInvoiceItemQueryRequest(String sessionId, List<String> recordIds, Map<String, String> credentials) {
        String recordKeys = String.join(recordIds, ',');
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
               '          <keys>' + recordKeys + '</keys>' +
               '          <fields>ARINVOICEITEMS,RECORDNO,RECORDID</fields>' +
               '        </read>' +
               '      </function>' +
               '    </content>' +
               '  </operation>' +
               '</request>';
    }

    private void processInvoiceItemResponse(String responseBody) {
        List<Intacct_Invoice_Entry__c> entries = new List<Intacct_Invoice_Entry__c>();
        List<String> errorMessages = new List<String>();

        Set<String> invoiceKeys = new Set<String>();
        Set<String> itemIds = new Set<String>();
        Set<String> vendorIds = new Set<String>();


        try {
            Dom.Document doc = new Dom.Document();
            doc.load(responseBody);
            System.debug('🔎 XML Response Loaded Successfully');

            Dom.XmlNode rootNode = doc.getRootElement();
            Dom.XmlNode dataNode = rootNode.getChildElement('operation', null)
                                            ?.getChildElement('result', null)
                                            ?.getChildElement('data', null);

            if (dataNode == null) {
                errorMessages.add('⚠️ No data found in response.');
                return;
            }

            // Process the data directly and collect IDs
            for (Dom.XmlNode invoiceNode : dataNode.getChildElements()) {
                String recordNo = getNodeTextSafe(invoiceNode, 'RECORDNO');
                String recordId = getNodeTextSafe(invoiceNode, 'RECORDID');
                invoiceKeys.add(recordNo);

                Dom.XmlNode itemsNode = invoiceNode.getChildElement('ARINVOICEITEMS', null);
                if (itemsNode != null) {
                    for (Dom.XmlNode itemNode : itemsNode.getChildElements()) {
                        if (itemNode.getName() == 'arinvoiceitem') {
                            try {
                             

                                Intacct_Invoice_Entry__c entry = new Intacct_Invoice_Entry__c();
                                entry.Invoice_Entry_ID__c = getNodeTextSafe(itemNode, 'RECORDNO');
                                entry.Intacct_Invoice_Record_Key__c = recordNo;
                                String itemId = getNodeTextSafe(itemNode, 'ITEMID');
                                itemIds.add(itemId);
                                entry.Name = recordId + '-' + itemId;
                                entry.Quantity__c = parseDecimal(getNodeTextSafe(itemNode, 'AMOUNT'));
                                entry.Tax_Amount__c = parseDecimal(getNodeTextSafe(itemNode, 'TRX_DISCOUNTAPPLIED'));
                                entry.Total_Paid__c = parseDecimal(getNodeTextSafe(itemNode, 'TOTALPAID'));
                                entry.Unit_Price__c = parseDecimal(getNodeTextSafe(itemNode, 'TRX_AMOUNT'));
                                
                                String vendorId =  getNodeTextSafe(itemNode, 'VENDORID');
                                vendorIds.add(vendorId);
                                entry.Vendor_ID__c = vendorId;
                                entry.Vendor_Name__c = getNodeTextSafe(itemNode, 'VENDORNAME');

                                entries.add(entry);
                            } catch (Exception e) {
                                errorMessages.add('❌ Error processing invoice item: ' + e.getMessage());
                            }
                        }
                    }
                }
            }

            // Perform bulk queries
            Map<String, Id> invoiceMap = new Map<String, Id>();
            if (!invoiceKeys.isEmpty()) {
                for (Intacct_Invoice__c inv : [SELECT Id, Intacct_Invoice_Key__c FROM Intacct_Invoice__c WHERE Intacct_Invoice_Key__c IN :invoiceKeys]) {
                    invoiceMap.put(inv.Intacct_Invoice_Key__c, inv.Id);
                }
            }

            Map<String, Id> productMap = new Map<String, Id>();
            if (!itemIds.isEmpty()) {
                System.debug('itemIds: ' + itemIds);
                for (Product2 prod : [SELECT Id, Intacct_Item_ID__c FROM Product2 WHERE Intacct_Item_ID__c IN :itemIds]) {
                    productMap.put(prod.Intacct_Item_ID__c, prod.Id);
                }
            }

            Map<String, Id> vendorMap = new Map<String, Id>();
            if (!vendorIds.isEmpty()) {
                for (Vendor__c vend : [SELECT Id, Intacct_Vendor_ID__c FROM Vendor__c WHERE Intacct_Vendor_ID__c IN :vendorIds]) {
                    vendorMap.put(vend.Intacct_Vendor_ID__c, vend.Id);
                }
            }

            // Perform relationship assignments
            for (Intacct_Invoice_Entry__c entry : entries) {
                if (invoiceMap.containsKey(entry.Intacct_Invoice_Record_Key__c)) {
                    entry.Invoice__c = invoiceMap.get(entry.Intacct_Invoice_Record_Key__c);
                }
                if (productMap.containsKey(entry.Item_ID__c)) {
                    entry.Product__c = productMap.get(entry.Item_ID__c);
                }
                if (vendorMap.containsKey(entry.Vendor_ID__c)) {
                    entry.Vendor__c = vendorMap.get(entry.Vendor_ID__c);
                }
            }

            // Upsert entries
            if (!entries.isEmpty()) {
                Database.UpsertResult[] results = Database.upsert(entries, Intacct_Invoice_Entry__c.Invoice_Entry_ID__c, false);
    
                for (Integer i = 0; i < results.size(); i++) {
                    if (!results[i].isSuccess()) {
                        for (Database.Error err : results[i].getErrors()) {
                            errorMessages.add('❌ Upsert error on record [' + entries[i].Name + ']: ' + err.getMessage());
                        }
                    } else {
                        System.debug('✅ Upserted: ' + entries[i].Name);
                    }
                }
    
                System.debug('✅ Total Upserted Records: ' + results.size());
            } else {
                errorMessages.add('⚠️ No valid entries to upsert.');
            }
        } catch (Exception e) {
            errorMessages.add('❌ Error processing Invoice Entries: ' + e.getMessage());
        }

        if (!errorMessages.isEmpty()) {
            IntacctSyncUtil.sendErrorNotification(String.join(errorMessages, '\n'));
        }
    }

    // Helper to safely extract node text
    private String getNodeTextSafe(Dom.XmlNode node, String childName) {
        if (node == null) {
            System.debug('⚠️ Node is null when accessing: ' + childName);
            return null;
        }
        Dom.XmlNode childNode = node.getChildElement(childName, null);
        if (childNode == null) {
            System.debug('⚠️ Missing Child Node: ' + childName);
            return null;
        }
        return childNode.getText();
    }

    // Helper to parse Decimal values
    private Decimal parseDecimal(String value) {
        try {
            return (value != null && value != '') ? Decimal.valueOf(value) : null;
        } catch (Exception e) {
            System.debug('⚠️ Error parsing Decimal value: ' + value + ' Error: ' + e.getMessage());
            return null;
        }
    }
}
