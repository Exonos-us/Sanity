@isTest
private class IntacctInvoiceItemSyncQueueableTest {

    @isTest
    static void testInvoiceItemSync_SuccessfulCallout() {
        // Set up dependencies: invoice, product, vendor
        Product2 product = new Product2(Name = 'Test Product', Intacct_Item_ID__c = 'ITEM123', IsActive = true);
        insert product;

        Vendor__c vendor = new Vendor__c(Name = 'Vendor A', Intacct_Vendor_ID__c = 'VEND456');
        insert vendor;

        Intacct_Invoice__c invoice = new Intacct_Invoice__c(
            Name = 'Test Invoice',
            Intacct_Invoice_Key__c = 'INVKEY789'
        );
        insert invoice;

        Test.setMock(HttpCalloutMock.class, new MockInvoiceItemCallout());

        Test.startTest();
        System.enqueueJob(new IntacctInvoiceItemSyncQueueable(new List<Intacct_Invoice__c>{ invoice }));
        Test.stopTest();

        List<Intacct_Invoice_Entry__c> entries = [SELECT Id, Name FROM Intacct_Invoice_Entry__c];
        System.assertEquals(1, entries.size(), 'Expected one entry from mock data');
        System.assertEquals('456-ITEM123', entries[0].Name);
    }

    @isTest
    static void testInvoiceItemSync_EmptyInvoiceList() {
        Test.startTest();
        System.enqueueJob(new IntacctInvoiceItemSyncQueueable(new List<Intacct_Invoice__c>()));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Intacct_Invoice_Entry__c]);
    }

    @isTest
    static void testInvoiceItemSync_InvalidRecordKeys() {
        // Invoice with blank Intacct_Invoice_Key__c
        Intacct_Invoice__c invoice = new Intacct_Invoice__c(Name = 'Invalid', Intacct_Invoice_Key__c = null);
        insert invoice;

        Test.startTest();
        System.enqueueJob(new IntacctInvoiceItemSyncQueueable(new List<Intacct_Invoice__c>{ invoice }));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Intacct_Invoice_Entry__c]);
    }

    @isTest
    static void testInvoiceItemSync_StatusCodeFailure() {
        Intacct_Invoice__c invoice = new Intacct_Invoice__c(Name = 'Test', Intacct_Invoice_Key__c = 'INV123');
        insert invoice;

        Test.setMock(HttpCalloutMock.class, new MockErrorResponse());

        Test.startTest();
        System.enqueueJob(new IntacctInvoiceItemSyncQueueable(new List<Intacct_Invoice__c>{ invoice }));
        Test.stopTest();
    }

    @isTest
    static void testInvoiceItemSync_UnexpectedError() {
        // No mocks configured
        Intacct_Invoice__c invoice = new Intacct_Invoice__c(Name = 'No Mock', Intacct_Invoice_Key__c = 'INVXYZ');
        insert invoice;

        Test.startTest();
        System.enqueueJob(new IntacctInvoiceItemSyncQueueable(new List<Intacct_Invoice__c>{ invoice }));
        Test.stopTest();
    }

    // ---------- MOCKS ----------

    private class MockInvoiceItemCallout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/xml');
            res.setBody('<?xml version="1.0" encoding="UTF-8"?>' +
                '<response><operation><result><status>success</status>' +
                '<data>' +
                '  <arinvoice>' +
                '    <RECORDNO>456</RECORDNO>' +
                '    <RECORDID>789</RECORDID>' +
                '    <ARINVOICEITEMS>' +
                '      <arinvoiceitem>' +
                '        <RECORDNO>123</RECORDNO>' +
                '        <ITEMID>ITEM123</ITEMID>' +
                '        <TRX_AMOUNT>50.00</TRX_AMOUNT>' +
                '        <TRX_DISCOUNTAPPLIED>5.00</TRX_DISCOUNTAPPLIED>' +
                '        <TOTALPAID>45.00</TOTALPAID>' +
                '        <VENDORID>VEND456</VENDORID>' +
                '        <VENDORNAME>Vendor A</VENDORNAME>' +
                '      </arinvoiceitem>' +
                '    </ARINVOICEITEMS>' +
                '  </arinvoice>' +
                '</data></result></operation></response>');
            return res;
        }
    }

    private class MockErrorResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Server Error');
            return res;
        }
    }
}
