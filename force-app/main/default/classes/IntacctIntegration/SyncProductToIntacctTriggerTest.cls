@isTest
private class SyncProductToIntacctTriggerTest {

    @isTest
    static void testInsert_NewProduct() {
        Product2 prod = new Product2(Name = 'Test Product A', IsActive = true);
        Test.startTest();
        insert prod;
        Test.stopTest();
    }

    @isTest
    static void testUpdate_NonMonitoredField() {
        Product2 prod = new Product2(Name = 'Test Product B', IsActive = true);
        insert prod;

        Test.startTest();
        prod.Description = 'Now updated';
        update prod;
        Test.stopTest();
    }

    @isTest
    static void testUpdate_MonitoredField() {
        Product2 prod = new Product2(Name = 'Test Product C', IsActive = true);
        insert prod;

        Test.startTest();
        prod.Name = 'Updated Product C';
        update prod;
        Test.stopTest();
    }
}
