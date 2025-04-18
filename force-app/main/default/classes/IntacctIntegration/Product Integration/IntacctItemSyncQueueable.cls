public class IntacctItemSyncQueueable implements Queueable, Database.AllowsCallouts {

    private static final Integer PAGE_SIZE = 100;

    private Integer offset;
    private String lastModifiedDate;

    public IntacctItemSyncQueueable() {
        this.offset = 0;
        this.lastModifiedDate = '01/01/2024 00:00:00';
    }

    public IntacctItemSyncQueueable(Integer offset, String lastModifiedDate) {
        this.offset = offset;
        this.lastModifiedDate = lastModifiedDate;
    }

    public void execute(QueueableContext context) {
        requestItems();
    }

    private void requestItems() {
        Map<String, String> credentials = IntacctSyncUtil.getIntacctCredentials();

        if (credentials == null) {
            IntacctSyncUtil.logSyncError( 'Item Sync', '❌ Failed to retrieve Intacct API credentials.', 'requestItems', 'IntacctItemSyncQueueable' );            return;
        }

        try {
            String sessionId = IntacctSyncUtil.getSessionId();
            if (sessionId == null) {
                IntacctSyncUtil.logSyncError( 'Item Sync', '❌ Failed to retrieve Intacct session token.', 'requestItems', 'IntacctItemSyncQueueable' );
                return;
            }

            String requestBody = buildItemQueryRequest(sessionId, offset, credentials);

            HttpRequest req = new HttpRequest();
            req.setEndpoint(credentials.get('API_Endpoint'));
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/xml');
            req.setBody(requestBody);

            Http http = new Http();
            HttpResponse res = http.send(req);

            System.debug('🔹 Intacct Item Query Response Code: ' + res.getStatusCode());
            System.debug('🔹 Intacct Item Query Response Body: ' + res.getBody());

            if (res.getStatusCode() != 200) {
                IntacctSyncUtil.logSyncError( 'Item Sync', '❌ Intacct Item Query failed. HTTP Code: ' + res.getStatusCode(), 'requestItems', 'IntacctItemSyncQueueable' );
                return;
            }

            processItemResponse(res.getBody());

        } catch (Exception e) {
            IntacctSyncUtil.logSyncError( 'Item Sync', '❌ Error in IntacctItemSyncQueueable: ' + e.getMessage(), 'requestItems', 'IntacctItemSyncQueueable' );
        }
    }

    private String buildItemQueryRequest(String sessionId, Integer offset, Map<String, String> credentials) {
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
               '      <function controlid="queryItems">' +
               '        <query>' +
               '          <object>ITEM</object>' +
               '          <filter>' +
               '            <and>' +
               '              <equalto>' +
               '                <field>STATUS</field>' +
               '                <value>active</value>' +
               '              </equalto>' +
               '              <greaterthan>' +
               '                <field>WHENMODIFIED</field>' +
               '                <value>' + lastModifiedDate + '</value>' +
               '              </greaterthan>' +
               '            </and>' +
               '          </filter>' +
               '          <select>' +
               '            <field>PRODUCTLINEID</field>' +
               '            <field>NAME</field>' +
               '            <field>STATUS</field>' +
               '            <field>ITEMID</field>' +
               '            <field>RECORDNO</field>' +
               '          </select>' +
               '          <pagesize>' + PAGE_SIZE + '</pagesize>' +
               '          <offset>' + offset + '</offset>' +
               '        </query>' +
               '      </function>' +
               '    </content>' +
               '  </operation>' +
               '</request>';
    }

    private void processItemResponse(String responseBody) {
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

            List<Product2> productsToUpsert = new List<Product2>();

            for (Dom.XmlNode itemNode : dataNode.getChildElements()) {
                try {
                    String itemId = itemNode.getChildElement('ITEMID', null)?.getText();
                    String name = itemNode.getChildElement('NAME', null)?.getText();
                    String status = itemNode.getChildElement('STATUS', null)?.getText();

                    if (String.isBlank(itemId) || String.isBlank(name)) {
                        errorMessages.add('⚠️ Skipping record due to missing ITEMID or NAME.');
                        continue;
                    }

                    Product2 prod = new Product2();
                    prod.Intacct_Item_ID__c = itemId;
                    prod.Name = name;

                    // Convert STATUS to boolean (active => true)
                    prod.IsActive = (status != null && status.toLowerCase() == 'active');

                    System.debug('✅ Product record: ' + prod);
                    productsToUpsert.add(prod);

                } catch (Exception e) {
                    IntacctSyncUtil.logSyncError( 'Item Sync', '❌ No result node found in response.', 'processItemResponse', 'IntacctItemSyncQueueable' );
                }
            }

            if (!productsToUpsert.isEmpty()) {
                System.debug('Products to upsert ' + productsToUpsert);
                Database.UpsertResult[] results = Database.upsert(productsToUpsert, Product2.Intacct_Item_ID__c, false);

                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        System.debug('✅ Successfully upserted: ' + productsToUpsert[i].Name + ' ITEMID: ' + productsToUpsert[i].Intacct_Item_ID__c);
                    } else {
                        for (Database.Error err : results[i].getErrors()) {
                            String msg = '❌ Upsert error on Product [' + productsToUpsert[i].Name + ']: ' + err.getMessage();
                            errorMessages.add('❌ Upsert error on Product [' + productsToUpsert[i].Name + ']: ' + err.getMessage());
                            IntacctSyncUtil.logSyncError( 'Item Sync', msg, 'processItemResponse', 'IntacctItemSyncQueueable' );
                        }
                    }
                }
            } else {
                errorMessages.add('⚠️ No valid products to upsert.');
            }

            Integer numRemaining = Integer.valueOf(dataNode.getAttributeValue('numremaining', null));

            System.debug('numRemaining records: ' + numRemaining);

            if (numRemaining > 0) {
                if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs() && Limits.getCallouts() < Limits.getLimitCallouts()) {
                    if (!Test.isRunningTest()) {
                        System.enqueueJob(new IntacctItemSyncQueueable(offset + PAGE_SIZE, lastModifiedDate));
                    }
                } else {
                    IntacctSyncUtil.logSyncError( 'Item Sync', '⚠️ Limits reached - Unable to enqueue next item job. Queueable jobs: ' + Limits.getQueueableJobs() + ' / ' + Limits.getLimitQueueableJobs() + ', Callouts: ' + Limits.getCallouts() + ' / ' + Limits.getLimitCallouts() + '. Remaining records: ' + numRemaining, 'processItemResponse', 'IntacctItemSyncQueueable' );
                    IntacctSyncUtil.sendErrorNotification(
                        '⚠️ Limits reached - Unable to enqueue next item job. ' +
                        'Queueable jobs: ' + Limits.getQueueableJobs() + ' / ' + Limits.getLimitQueueableJobs() +
                        ', Callouts: ' + Limits.getCallouts() + ' / ' + Limits.getLimitCallouts() +
                        '. Remaining records: ' + numRemaining
                    );
                }
            } else {
                System.debug('✅ No more items to process.');
            }

        } catch (Exception e) {
            IntacctSyncUtil.logSyncError( 'Item Sync', '❌ Critical error processing item response: ' + e.getMessage(), 'processItemResponse', 'IntacctItemSyncQueueable' );
        }

        if (!errorMessages.isEmpty()) {
            System.debug('Errors: ' + errorMessages);
            IntacctSyncUtil.sendErrorNotification(String.join(errorMessages, '\n'));
        }
    }
}
