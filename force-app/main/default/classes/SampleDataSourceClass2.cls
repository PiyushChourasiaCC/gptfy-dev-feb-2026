global class SampleDataSourceClass2 implements AIDataSourceInterface {
	
    global String getExternalData(AI_Data_Source__c dataSource, String extractedData){
        Map<String, Object> maps = (Map<String, Object>)JSON.deserializeUntyped(extractedData);
        maps.put('Industry', 'Agriculture');
        return JSON.serialize(maps);
    }
    
}