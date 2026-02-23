global class AIApexSecurityLayerDataWrapper {
    global AI_Response__c response {get;set;}
    global Map<String,Boolean> mapOfPIIKeyToMatchCompleteWord {get;set;}
    global AIApexSecurityLayerDataWrapper(AI_Response__c resp,Map<String,Boolean> mapOfPIIKeyToMatchCompleteWord){
        this.response = resp;
        this.mapOfPIIKeyToMatchCompleteWord = mapOfPIIKeyToMatchCompleteWord;
    }
}