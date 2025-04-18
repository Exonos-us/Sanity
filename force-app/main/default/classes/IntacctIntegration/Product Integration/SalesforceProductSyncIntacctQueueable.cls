public class SalesforceProductSyncIntacctQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> productIdsToProcess;
    private static final String API_ENDPOINT = 'https://api.intacct.com/ia/xml/xmlgw.phtml';

    public SalesforceProductSyncIntacctQueueable(List<Id> productIds) {
        this.productIdsToProcess = productIds;
    }

    public void execute(QueueableContext context) {
        try {
            processNextProduct();
        } catch (Exception e) {
            System.debug('❌ Error in execute: ' + e.getMessage());
            IntacctSyncUtil.logSyncError('Product Sync', '❌ Error in SalesforceProductSyncIntacctQueueable: ' + e.getMessage(), 'execute', 'SalesforceProductSyncIntacctQueueable');
        }
    }

    private void processNextProduct() {
        if (productIdsToProcess.isEmpty()) {
            System.debug('✅ No more products to process.');
            return;
        }

        Id productId = productIdsToProcess.remove(0);

        try {
            Product2 prod = [
                SELECT Id, Name, IsActive, Intacct_Item_ID__c
                FROM Product2
                WHERE Id = :productId
                LIMIT 1
            ];

            if (String.isBlank(prod.Intacct_Item_ID__c)) {
                // 🔹 Insert new item in Intacct
                String itemId = syncProductInIntacct(prod, true);
                if (itemId != null) {
                    prod.Intacct_Item_ID__c = itemId;
                    update prod;
                    System.debug('✅ Inserted and updated Salesforce Product2 with Intacct Item ID: ' + itemId);
                }
            } else {
                // 🔹 Update existing item in Intacct
                syncProductInIntacct(prod, false);
                System.debug('✅ Updated existing Intacct Item: ' + prod.Intacct_Item_ID__c);
            }

        } catch (Exception e) {
            System.debug('❌ Error processing product ' + productId + ': ' + e.getMessage());
            IntacctSyncUtil.logSyncError('Product Sync', '❌ Error processing product ' + productId + ': ' + e.getMessage(), 'processNextProduct', 'SalesforceProductSyncIntacctQueueable');
        }

        // ✅ Validate limits before enqueuing the next record
        if (!productIdsToProcess.isEmpty()) {
            if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs() && Limits.getCallouts() < Limits.getLimitCallouts()) {
                System.enqueueJob(new SalesforceProductSyncIntacctQueueable(productIdsToProcess));
            } else {
                System.debug('⚠️ Queueable job or callout limit reached. Next job not enqueued.');
                IntacctSyncUtil.logSyncError('Product Sync', '⚠️ Queueable job or callout limit reached. Unable to enqueue next job.', 'processNextProduct', 'SalesforceProductSyncIntacctQueueable');
                IntacctSyncUtil.sendErrorNotification('⚠️ Queueable job or callout limit reached. Unable to enqueue next job.');
            }
        }
    }

    // 🔹 Inserts or Updates an Item in Intacct
    private String syncProductInIntacct(Product2 prod, Boolean isInsert) {
        String requestBody = buildRequest(prod, isInsert);

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
                System.debug('❌ ' + (isInsert ? 'Insert' : 'Update') + ' failed: ' + res.getBody());
                IntacctSyncUtil.logSyncError('Product Sync', '❌ ' + (isInsert ? 'Insert' : 'Update') + ' failed for Product ' + prod.Name + ': ' + res.getBody(), 'syncProductInIntacct', 'SalesforceProductSyncIntacctQueueable');
            }

        } catch (Exception e) {
            System.debug('❌ Callout error: ' + e.getMessage());
            IntacctSyncUtil.logSyncError('Product Sync', '❌ Callout error for Product ' + prod.Name + ': ' + e.getMessage(), 'syncProductInIntacct', 'SalesforceProductSyncIntacctQueueable');
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
                Dom.XmlNode itemNode = dataNode.getChildElement('item', null);
                if (itemNode != null) {
                    String itemId = itemNode.getChildElement('ITEMID', null).getText();
                    return itemId;
                }
            }

        } catch (Exception e) {
            System.debug('❌ XML Parsing error: ' + e.getMessage());
            IntacctSyncUtil.logSyncError('Product Sync', '❌ XML Parsing error: ' + e.getMessage(), 'parseResponse', 'SalesforceProductSyncIntacctQueueable');
        }

        return null;
    }


    private String buildRequest(Product2 prod, Boolean isInsert) {
        String operationType = isInsert ? 'create' : 'update';
        String controlId = isInsert ? 'createItem' : 'updateItem';
        String statusValue = prod.IsActive ? 'active' : 'inactive';
    
        // ITEMID mapping:
        String itemId = isInsert
            ? safeString(prod.Name)  // INSERT: Product Name becomes the ITEMID
            : safeString(prod.Intacct_Item_ID__c);  // UPDATE: use existing Intacct Item ID
    
        return '<?xml version="1.0" encoding="UTF-8"?>' +
            '<request>' +
            '  <control>' +
            '    <senderid>' + IntacctSyncUtil.getIntacctCredentials().get('Sender_ID') + '</senderid>' +
            '    <password>' + IntacctSyncUtil.getIntacctCredentials().get('Sender_Password') + '</password>' +
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
            '          <ITEM>' +
            '            <ITEMID>' + itemId + '</ITEMID>' +  // This ensures correct behavior for insert/update
            '            <NAME>' + safeString(prod.Name) + '</NAME>' +
            '            <STATUS>' + statusValue + '</STATUS>' +
            '          </ITEM>' +
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
