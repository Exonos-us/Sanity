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
            IntacctSyncUtil.logSyncError('Order Sync', '❌ Error in SalesforceOrderSyncIntacctQueueable: ' + e.getMessage(), 'execute', 'SalesforceOrderSyncIntacctQueueable');
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
                SELECT Id, OrderNumber, EffectiveDate, Status, Account.Name, 
                       Account.Intacct_Customer_Id__c, Account.Intacct_Customer_Name__c, Description,
                       Intacct_Sync_Status__c, Intacct_Sync_Error_Message__c, Intacct_Sales_Order_ID__c,
                       SBQQ__Quote__r.SBQQ__SalesRep__r.Name
                FROM Order
                WHERE Id = :orderId
                LIMIT 1
            ];
            
            List<OrderItem> orderItems = [
                SELECT Id, Quantity, UnitPrice, Product2.Intacct_Item_ID__c, Product2.Name
                FROM OrderItem
                WHERE OrderId = :orderId
            ];
            
            Boolean isInsert = String.isBlank(ord.Intacct_Sales_Order_ID__c);
            
            // 🔹 Call sync logic
            String intacctSalesOrderId = syncOrderInIntacct(ord, orderItems, isInsert);
            
            if (intacctSalesOrderId != null) {
                ord.Intacct_Sales_Order_ID__c = intacctSalesOrderId;
                ord.Intacct_Sync_Status__c = 'Success';
                ord.Intacct_Sync_Error_Message__c = null;
                update ord;
                
                System.debug((isInsert ? '✅ Inserted' : '✅ Updated') + ' Order ' + ord.Id + ' in Intacct with ID: ' + intacctSalesOrderId);
            }
            
        } catch (Exception e) {
            System.debug('❌ Error processing Order ' + orderId + ': ' + e.getMessage());
            IntacctSyncUtil.logSyncError('Order Sync', '❌ Error processing Order ' + orderId + ': ' + e.getMessage(), 'processNextOrder', 'SalesforceOrderSyncIntacctQueueable');
        }
        
        if (!orderIdsToProcess.isEmpty()) {
            if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs() && Limits.getCallouts() < Limits.getLimitCallouts()) {
                System.enqueueJob(new SalesforceOrderSyncIntacctQueueable(orderIdsToProcess));
            } else {
                System.debug('⚠️ Limits reached. Not enqueuing next job.');
                IntacctSyncUtil.logSyncError('Order Sync', '⚠️ Limits reached. Not enqueuing next job.', 'processNextOrder', 'SalesforceOrderSyncIntacctQueueable');
                IntacctSyncUtil.sendErrorNotification('⚠️ Limits reached. Not enqueuing next job.');
            }
        }
    }
    
    private String syncOrderInIntacct(Order ord, List<OrderItem> orderItems, Boolean isInsert) {
        String requestBody = isInsert
            ? buildCreateSalesOrderRequest(ord, orderItems)
            : buildUpdateSalesOrderRequest(ord);
        
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
                String intacctSalesOrderId = parseResponse(res.getBody(), isInsert);
                
                if (intacctSalesOrderId != null) {
                    return intacctSalesOrderId;
                } 
            } else {
                IntacctSyncUtil.logSyncError('Order Sync', '❌ Intacct response code not 200 for Order ' + ord.Id + ': ' + res.getBody(), 'syncOrderInIntacct', 'SalesforceOrderSyncIntacctQueueable');
                updateOrderWithError(ord.Id, res.getBody());
            }
            
        } catch (Exception e) {
            System.debug('❌ Callout exception: ' + e.getMessage());
            IntacctSyncUtil.logSyncError('Order Sync', '❌ Callout exception for Order ' + ord.Id + ': ' + e.getMessage(), 'syncOrderInIntacct', 'SalesforceOrderSyncIntacctQueueable');
        }
        
        return null;
    }
    
    private String buildCreateSalesOrderRequest(Order ord, List<OrderItem> orderItems) {
        String controlId = 'createSalesOrderHeader' + String.valueOf(System.currentTimeMillis());
        String accountIntacctId = ord.Account.Intacct_Customer_Id__c;
        String primaryContact = ord.SBQQ__Quote__r != null && ord.SBQQ__Quote__r.SBQQ__SalesRep__r != null
            ? safeString(ord.SBQQ__Quote__r.SBQQ__SalesRep__r.Name)
            : '';
        String contactName = ord.Account.Intacct_Customer_Name__c;
        
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
    
    private String buildUpdateSalesOrderRequest(Order ord) {
        String controlId = 'updateSalesOrderHeader' + String.valueOf(System.currentTimeMillis());
        String primaryContact = ord.SBQQ__Quote__r != null && ord.SBQQ__Quote__r.SBQQ__SalesRep__r != null
            ? safeString(ord.SBQQ__Quote__r.SBQQ__SalesRep__r.Name)
            : '';
        String contactName = ord.Account.Intacct_Customer_Name__c;
        
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
            '      <function controlid="updateSalesOrderHeader">' +
            '        <update_sotransaction key="' + ord.Intacct_Sales_Order_ID__c + '">' +
            
        '          <datecreated>' +
            '            <year>' + ord.EffectiveDate.year() + '</year>' +
            '            <month>' + ord.EffectiveDate.month() + '</month>' +
            '            <day>' + ord.EffectiveDate.day() + '</day>' +
            '          </datecreated>' +
            
        '          <origdocdate>' +
            '            <year>' + ord.EffectiveDate.year() + '</year>' +
            '            <month>' + ord.EffectiveDate.month() + '</month>' +
            '            <day>' + ord.EffectiveDate.day() + '</day>' +
            '          </origdocdate>' +
            
        '          <message>' + safeString(ord.Description) + '</message>' +
            '          <shipto><contactname>' + contactName + '</contactname></shipto>' +
            '          <billto><contactname>' + contactName + '</contactname></billto>' +
            
        '          <basecurr>USD</basecurr>' +
            '          <currency>USD</currency>' +
            '          <exchratetype>Intacct Daily Rate</exchratetype>' +
            
        '          <customfields>' +
            '            <customfield>' +
            '              <customfieldname>REP</customfieldname>' +
            '              <customfieldvalue>' + primaryContact + '</customfieldvalue>' +
            '            </customfield>' +
            '          </customfields>' +
            
        '        </update_sotransaction>' +
            '      </function>' +
            '    </content>' +
            '  </operation>' +
            '</request>';
        
        return xml;
    }
    
    private String parseResponse(String xmlResponse, Boolean isInsert) {
        try {
            Dom.Document doc = new Dom.Document();
            doc.load(xmlResponse);
            
            Dom.XmlNode root = doc.getRootElement();
            Dom.XmlNode operationNode = root.getChildElement('operation', null);
            Dom.XmlNode resultNode = operationNode.getChildElement('result', null);
            Dom.XmlNode statusNode = resultNode.getChildElement('status', null);
            
            if (statusNode != null && statusNode.getText().toLowerCase() == 'success') {
                Dom.XmlNode keyNode = resultNode.getChildElement('key', null);
                return keyNode != null ? keyNode.getText() : null;
            }
            
        } catch (Exception e) {
            System.debug('❌ XML Parsing error: ' + e.getMessage());
            IntacctSyncUtil.logSyncError('Order Sync', '❌ XML Parsing error: ' + e.getMessage(), 'parseResponse', 'SalesforceOrderSyncIntacctQueueable');
        }
        
        return null;
    }
    
    private void updateOrderWithError(Id orderId, String errorMessage) {
        update new Order(
            Id = orderId,
        Intacct_Sync_Status__c = 'Failure',
        Intacct_Sync_Error_Message__c = errorMessage
            );
    }
    
    private String safeString(String value) {
        return value == null ? '' : value.escapeXml();
    }
}