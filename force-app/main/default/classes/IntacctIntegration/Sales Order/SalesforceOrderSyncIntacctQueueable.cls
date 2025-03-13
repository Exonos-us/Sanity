public class SalesforceOrderSyncIntacctQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> orderIdsToProcess;
    private String orderId;
    private static final String API_ENDPOINT = 'https://api.intacct.com/ia/xml/xmlgw.phtml';

    public SalesforceOrderSyncIntacctQueueable(List<Id> orderIds) {
        this.orderIdsToProcess = orderIds;
    }

    public void execute(QueueableContext context) {
        try {
            processNextOrder();
        } catch (Exception e) {
            System.debug('❌ Error in execute: ' + e.getMessage());
            IntacctSyncUtil.sendErrorNotification('❌ Error in SalesforceOrderSyncIntacctQueueable: ' + e.getMessage());
        }
    }

    private void processNextOrder() {
        if (orderIdsToProcess.isEmpty()) {
            System.debug('✅ No more orders to process.');
            return;
        }

        orderId = orderIdsToProcess.remove(0);


        try {
            Order ord = [
                SELECT Id, OrderNumber, EffectiveDate, Status, Account.Name, Account.Intacct_Customer_Id__c,Account.Intacct_Customer_Name__c, Description,
                       Intacct_Sync_Status__c, Intacct_Sync_Error_Message__c, Intacct_Sales_Order_ID__c,
                       SBQQ__Quote__r.SBQQ__PrimaryContact__r.Name
                FROM Order
                WHERE Id = :orderId
                LIMIT 1
            ];

            List<OrderItem> orderItems = [
                SELECT Id, Quantity, UnitPrice, Product2.Intacct_Item_ID__c, Product2.Name
                FROM OrderItem
                WHERE OrderId = :orderId
            ];

            // 🔹 Call the Intacct sync method
            String intacctSalesOrderId = syncOrderInIntacct(ord, orderItems);

            // 🔸 If we get an ID back, update the Order
            if (intacctSalesOrderId != null) {
                ord.Intacct_Sales_Order_ID__c = intacctSalesOrderId;
                ord.Intacct_Sync_Status__c = 'Success';
                ord.Intacct_Sync_Error_Message__c = null;
                update ord;

                System.debug('✅ Successfully synced Order ' + ord.Id + ' with Intacct Sales Order ID: ' + intacctSalesOrderId);
            }

        } catch (Exception e) {
            System.debug('❌ Error processing Order ' + orderId + ': ' + e.getMessage());
            IntacctSyncUtil.sendErrorNotification('❌ Error processing Order ' + orderId + ': ' + e.getMessage());

            // ⚠️ Update Order with failure
            Order failedOrder = new Order(
                Id = orderId,
                Intacct_Sync_Status__c = 'Failure',
                Intacct_Sync_Error_Message__c = e.getMessage()
            );
            update failedOrder;
        }

        // 🔹 Enqueue next job if needed
        if (!orderIdsToProcess.isEmpty()) {
            if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs() && Limits.getCallouts() < Limits.getLimitCallouts()) {
                System.enqueueJob(new SalesforceOrderSyncIntacctQueueable(orderIdsToProcess));
            } else {
                System.debug('⚠️ Queueable job or callout limit reached. Next job not enqueued.');
                IntacctSyncUtil.sendErrorNotification('⚠️ Queueable job or callout limit reached. Unable to enqueue next order sync job.');
            }
        }
    }

    private String syncOrderInIntacct(Order ord, List<OrderItem> orderItems) {
        String requestBody = buildRequest(ord, orderItems);

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(API_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/xml');
            req.setBody(requestBody);

            Http http = new Http();
            HttpResponse res = http.send(req);

            System.debug('🔹 Intacct Raw Response: ' + res.getBody());

            if (res.getStatusCode() == 200) {
                String intacctSalesOrderId = parseResponse(res.getBody());

                if (intacctSalesOrderId != null) {
                    return intacctSalesOrderId;
                } else {
                    // Failure: save XML response
                    updateOrderWithError(ord.Id, res.getBody());
                }
            } else {
                // HTTP error
                updateOrderWithError(ord.Id, res.getBody());
            }

        } catch (Exception e) {
            System.debug('❌ Callout exception: ' + e.getMessage());
            IntacctSyncUtil.sendErrorNotification('❌ Callout error syncing Order ' + ord.Id + ': ' + e.getMessage());

            updateOrderWithError(ord.Id, e.getMessage());
        }

        return null;
    }

    private String parseResponse(String xmlResponse) {
        try {
            Dom.Document doc = new Dom.Document();
            doc.load(xmlResponse);
    
            Dom.XmlNode root = doc.getRootElement();
            Dom.XmlNode controlNode = root.getChildElement('control', null);
            Dom.XmlNode controlStatusNode = controlNode.getChildElement('status', null);
    
            if (controlStatusNode != null && controlStatusNode.getText().toLowerCase() == 'success') {
                Dom.XmlNode operationNode = root.getChildElement('operation', null);
                Dom.XmlNode resultNode = operationNode.getChildElement('result', null);
    
                Dom.XmlNode resultStatusNode = resultNode.getChildElement('status', null);
                
                if (resultStatusNode != null && resultStatusNode.getText().toLowerCase() == 'success') {
                    Dom.XmlNode keyNode = resultNode.getChildElement('key', null);
    
                    if (keyNode != null) {
                        String salesOrderKey = keyNode.getText();
                        System.debug('✅ Intacct Sales Order Key: ' + salesOrderKey);
                        return salesOrderKey;
                    } else {
                        System.debug('⚠️ No <key> node found in result.');
                    }
                } else {
                    System.debug('❌ Result status indicates failure.');
                    updateOrderWithError(orderId, xmlResponse);

                }
            } else {
                System.debug('❌ Control status indicates failure.');
            }
    
        } catch (Exception e) {
            System.debug('❌ XML Parsing error: ' + e.getMessage());
            IntacctSyncUtil.sendErrorNotification('❌ XML Parsing error: ' + e.getMessage());
        }
    
        return null;
    }

    private void updateOrderWithError(Id orderId, String errorMessage) {
        Order failedOrder = new Order(
            Id = orderId,
            Intacct_Sync_Status__c = 'Failure',
            Intacct_Sync_Error_Message__c = errorMessage
        );
        update failedOrder;
    }

    private String buildRequest(Order ord, List<OrderItem> orderItems) {
        String controlId = 'createSalesOrderHeader' + String.valueOf(System.currentTimeMillis());
        String accountIntacctId = ord.Account.Intacct_Customer_Id__c;
        System.debug('accountIntacctId: ' + accountIntacctId);
        String primaryContact = ord.SBQQ__Quote__r != null && ord.SBQQ__Quote__r.SBQQ__PrimaryContact__r != null
            ? safeString(ord.SBQQ__Quote__r.SBQQ__PrimaryContact__r.Name)
            : '';
    
        String contactName = ord.Account.Intacct_Customer_Name__c;
        System.debug('contactName: ' + contactName);
    
        String xml =
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<request>' +
            '  <control>' +
            '    <senderid>' + IntacctSyncUtil.getIntacctCredentials().get('Sender_ID') + '</senderid>' +
            '    <password>' + IntacctSyncUtil.getIntacctCredentials().get('Sender_Password') + '</password>' +
            '    <controlid>' + controlId + '</controlid>' +
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
            '        <create_sotransaction>' +
            '          <transactiontype>Sales Order</transactiontype>' +
    
            '          <datecreated>' +
            '            <year>' + ord.EffectiveDate.year() + '</year>' +
            '            <month>' + ord.EffectiveDate.month() + '</month>' +
            '            <day>' + ord.EffectiveDate.day() + '</day>' +
            '          </datecreated>' +
    
            '          <createdfrom></createdfrom>' + 
            '          <customerid>' + accountIntacctId + '</customerid>' +
            '          <documentno>' + safeString(ord.OrderNumber) + '</documentno>' +
            '          <origdocdate>' +
            '            <year>' + ord.EffectiveDate.year() + '</year>' +
            '            <month>' + ord.EffectiveDate.month() + '</month>' +
            '            <day>' + ord.EffectiveDate.day() + '</day>' +
            '          </origdocdate>' +
            '          <referenceno></referenceno>' +  
            '          <termname></termname>' +       
    
    

            '          <datedue>' +
            '            <year>' + ord.EffectiveDate.year() + '</year>' +
            '            <month>' + ord.EffectiveDate.month() + '</month>' +
            '            <day>' + ord.EffectiveDate.day() + '</day>' +
            '          </datedue>' +
    
            '          <message>' + safeString(ord.Description)  + '</message>' +
            '          <shippingmethod></shippingmethod>' +
    
            '          <shipto>' +
            '            <contactname>' + contactName + '</contactname>' +
            '          </shipto>' +
            '          <billto>' +
            '            <contactname>' + contactName + '</contactname>' +
            '          </billto>' +
    
            '          <basecurr>USD</basecurr>' +
            '          <currency>USD</currency>' +
            '          <exchratetype>Intacct Daily Rate</exchratetype>' +
    
    
            '          <customfields>' +
            '            <customfield>' +
            '              <customfieldname>REP</customfieldname>' +
            '              <customfieldvalue>' + primaryContact + '</customfieldvalue>' +
            '            </customfield>' +
            '            <customfield>' +
            '              <customfieldname>NASPO_NCPA_GSA_ETC</customfieldname>' +
            '              <customfieldvalue>Commercial/Enterprise</customfieldvalue>' +
            '            </customfield>' +
            '          </customfields>' +
            '          <state>Pending</state>' +
            '          <sotransitems>';
    

        for (OrderItem item : orderItems) {
            System.debug('item: ' + item);
            xml +=
                '            <sotransitem>' +
                '              <bundlenumber></bundlenumber>' +
                '              <itemid>' + item.Product2.Intacct_Item_ID__c + '</itemid>' +
                '              <quantity>' + item.Quantity + '</quantity>' +
                '              <unit>Each</unit>' + 
                '              <price>' + item.UnitPrice + '</price>' +
                '              <discsurchargememo></discsurchargememo>' + 
                '            </sotransitem>';
        }
    
        xml +=
            '          </sotransitems>' +
            '        </create_sotransaction>' +
            '      </function>' +
            '    </content>' +
            '  </operation>' +
            '</request>';
    
        return xml;
    }
    

    private String safeString(String value) {
        return value == null ? '' : value.escapeXml();
    }
}
