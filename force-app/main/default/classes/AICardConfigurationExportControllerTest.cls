@isTest
public class AICardConfigurationExportControllerTest {

    // Setup method to initialize test data
    @testSetup
    public static void makeData(){
        TestUtility.createCardConfiguration('DnB','APIDS',true);
        TestUtility.createCardConfiguration('GPTfy (OpenAI)','AMODL',true);
        TestUtility.createCardConfiguration('Boost Sales','CTLOG',true);
    }
 
    // Test the getCurrentPackageName method
    @isTest
    static void testGetCurrentPackageName() {
        AICardConfigurationExportController controller = new AICardConfigurationExportController();
        String packageName = controller.getCurrentPackageName();
        System.assertNotEquals(null, packageName, 'Package name should not be null');
    }

    // Test the navigateToListView method
    @isTest
    static void testNavigateToListView() {
        AICardConfigurationExportController controller = new AICardConfigurationExportController();
        PageReference pageRef = controller.navigateToListView();
        System.assertNotEquals(null, pageRef, 'PageReference should not be null');
        System.assertEquals(true, pageRef.getUrl().contains('/'), 'The URL should contain a slash indicating it is a valid navigation target');
    }

    // Test the getMappings method for exporting card configurations
    @isTest
    static void testGetMappings() {
        Test.startTest();
        ExportMappingWrapper mappingWrapper = AICardConfigurationExportController.getMappings();
        Test.stopTest();

        System.assertNotEquals(null, mappingWrapper, 'Mapping wrapper should not be null');
        System.assertNotEquals(0, mappingWrapper.cardConfigs.size(), 'There should be exported card configurations');
    }

    // Test the readFileData method for processing valid file data
    @isTest
    static void testReadFileDataValid() {
        // Assume this JSON represents the file data format expected by your readFileData method
        String validJson = '{ "orgId": "123456789", "exportedBy": "Test User", "cardConfigs": [{"salesforceId": "1A2B3C", "configName": "Test Config 1"}]}';

        Test.startTest();
        Map<String, Object> result = AICardConfigurationExportController.readFileData(validJson);
        Test.stopTest();

        System.assertEquals(false, (Boolean)result.get('hasError'), 'Processing valid file data should not result in an error');
    }


@isTest
    static void testInsertCards(){
        List<ExportMappingWrapper.CardConfigurationWrapper> cards = new List<ExportMappingWrapper.CardConfigurationWrapper>();
        ExportMappingWrapper.CardConfigurationWrapper card = new ExportMappingWrapper.CardConfigurationWrapper();
        card.salesforceId = '123';
        card.configName = 'Test';
        //card.externalId = 'Test';
        cards.add(card);
        Test.startTest();
        Map<String, AI_Card_Configuration__c> configs = AICardConfigurationExportController.insertCards(cards, true);
        Test.stopTest();
        System.assertEquals(1, configs.size(), 'Size should be 1');
    }

    
@isTest
    static void testSaveCards(){
        List<ExportMappingWrapper.CardConfigurationWrapper> cards = new List<ExportMappingWrapper.CardConfigurationWrapper>();
        ExportMappingWrapper.CardConfigurationWrapper card = new ExportMappingWrapper.CardConfigurationWrapper();
        card.salesforceId = '123';
        card.configName = 'Test';
        //card.externalId = 'Test';
        cards.add(card);
        Test.startTest();
        AICardConfigurationExportController.saveCards(cards, false);
        Test.stopTest();

        List<AI_Card_Configuration__c> savedCards = [SELECT Name FROM AI_Card_Configuration__c WHERE Name = :card.configName];
        System.assertEquals(1, savedCards.size(), 'New card configuration should be saved in the database');
    }
    
    @isTest
    static void testUpdateCards(){
        List<AI_Card_Configuration__c> cardConfig = [Select Id,Name from AI_Card_Configuration__c Where Name IN ('Boost Sales','DnB') LIMIT 2];
        cardConfig[0].Name = 'Test2';
        cardConfig[1].Name = 'Test2';
        Test.startTest();
        Boolean errorOccurred = false;
        try{
            update cardConfig;
        }catch(Exception e){
            errorOccurred = true;
        }
        Test.stopTest();
        System.assertEquals(true, errorOccurred, 'error should be occur while updating duplicate name card configurations');
    }
}