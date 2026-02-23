/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class ChatGPTUtills {
	
    /**
    * Initiates the AI response generation using the AI model for the specified record and prompt, with optional custom text prompts and files.
    * @param recordId The ID of the record for which the AI response is being generated.
    * @param promptId The ID of the prompt used for generating the AI response.
    * @param userInput A custom text prompt that can be provided as an alternative to using the prompt ID.
    * @param mapOfFiles A map containing file names as keys and lists of file paths as values, representing any additional files relevant to the AI response generation.
    * @return AI_Response__c The generated AI response record containing the response data.
    */
    
    @AuraEnabled
    public static AI_Response__c initiateGPT(Id recordId, Id promptId, String userInput, Map<String, List<String>> mapOfFiles,Boolean isGptfyConsole){ 
        if(!AILicenseManagerController.isLicenseAvailable() && !Test.isRunningTest()){
            throw new ApplicationException(Label.License_Consumption_Error);
        }
        AI_Prompt__c aiPrompt = AIPromptSelector.getAIPromptById(promptId);
        aiPrompt.Prompt_Command__c = preparePromptCommand(aiPrompt, userInput, recordId, isGptfyConsole);
        if(String.isBlank(aiPrompt.Prompt_Command__c) && !Test.isRunningTest() && aiPrompt.Type__c != AIConstants.AI_PMT_TYPE_CANVAS){
            throw new ApplicationException('Either Prompt command or User Input is required to run the Prompt.');
        }
        
        AI_Response__c response = new AI_Response__c();
        response.Start_Date_Time__c = System.Now();
        response = getExtractedData(recordId, aiPrompt, mapOfFiles, response);
        response = processRequest(recordId, aiPrompt, mapOfFiles, null, response);
        return response;
    }
    
    public static String preparePromptCommand(AI_Prompt__c aiPrompt, String userInput, String recordId, Boolean isGptfyConsole){
        String promptCommand = '';
        if(String.isNotBlank(aiPrompt.Prompt_Command__c)){
            promptCommand += aiPrompt.Prompt_Command__c;
        }
        if(String.isNotBlank(userInput)){
            //@Jira 5919: Manage additional instructions in prompts
            GPTfy_Settings__c settings = GPTfy_Settings__c.getOrgDefaults();
            String seperator = '\n\n';
            if(settings != null && String.isNotBlank(settings.Additional_Input_Separator__c)){
                seperator += settings.Additional_Input_Separator__c+' ';
            }else{
                seperator += 'Additional Instructions: ';
            }
            if(String.isNotBlank(promptCommand)){
                promptCommand  = promptCommand+seperator+userInput;
            }else{
                promptCommand = userInput;
            }
        }
        if(String.isNotBlank(aiPrompt.Grounding_Ethical__c)){
            List<String> rules = aiPrompt.Grounding_Ethical__c.split(';');
            if(rules != null && !rules.isEmpty()){
                String groundingEthical = '[Instructions - Ethical]';
                Integer index = 1;
                for(String rule : rules){
                    groundingEthical += '\n'+index+'. '+rule;
                    index++;
                }
                promptCommand += '\n\n'+groundingEthical;
            }
        }
        if(String.isNotBlank(aiPrompt.Grounding_Content__c)){
			List<String> rules = aiPrompt.Grounding_Content__c.split(';');
            if(rules != null && !rules.isEmpty()){
                String groundingContent = '[Instructions - Content Presentation]';
                Integer index = 1;
                for(String rule : rules){
                    groundingContent += '\n'+index+'. '+rule;
                    index++;
                }
                promptCommand += '\n\n'+groundingContent;
            }
        }
        
        String gptfyLocale = '';
        if(isGptfyConsole != null && isGptfyConsole && String.isNotBlank(aiPrompt.AI_Locale_GPTfy_Console__c)){
            if(aiPrompt.AI_Locale_GPTfy_Console__c == AIConstants.PMT_LOCALE_GPTFY_CONSOLE_COMPANY_DEFAULT){
                Organization org = [SELECT DefaultLocaleSidKey FROM Organization LIMIT 1];
                gptfyLocale = org.DefaultLocaleSidKey;
            }else if(aiPrompt.AI_Locale_GPTfy_Console__c == AIConstants.PMT_LOCALE_GPTFY_CONSOLE_ACTIVE_USER){
                gptfyLocale = UserInfo.getLocale();
            }
        }else if((isGptfyConsole == null || !isGptfyConsole ) && String.isNotBlank(aiPrompt.AI_Locale_Automation__c)){
            if(aiPrompt.AI_Locale_Automation__c == AIConstants.PMT_LOCALE_GPTFY_CONSOLE_COMPANY_DEFAULT){
                Organization org = [SELECT DefaultLocaleSidKey FROM Organization LIMIT 49999];
                gptfyLocale = org.DefaultLocaleSidKey;
            }else if(aiPrompt.AI_Locale_Automation__c == AIConstants.PMT_LOCALE_AUTOMATION_RECORD_OWNER){
                String query = 'SELECT Id, OwnerId, Owner.LocaleSidKey FROM '+String.escapeSingleQuotes(aiPrompt.Object__c)+' WHERE Id =:recordId';
                try{
                    List<SObject> lstOfRecords = Database.query(query);
                    if(lstOfRecords != null && !lstOfRecords.isEmpty()){
                        SObject so = lstOfRecords.get(0);
                        if(so.get('OwnerId') != null && so.getSobject('Owner').get('LocaleSidKey') != null){
                            gptfyLocale = String.valueOf(so.getSobject('Owner').get('LocaleSidKey'));
                        }
                    }
                }catch(Exception e){
					throw new ApplicationException(e.getMessage());                   
                }
            }
        }
        if(String.isNotBlank(gptfyLocale)){
            promptCommand += '\n\n'+String.format(System.Label.LOCALE_PROMPT_COMMAND,new List<String> { gptfyLocale });
        }
        return promptCommand;
    }
    
    /**
     * Retrieves the extracted data based on the provided record ID, AI prompt, map of file references, and existing AI response.
     * 
     * @param recordId The ID of the record for which the data is being extracted.
     * @param aiPrompt The AI prompt object containing information necessary for the data extraction process.
     * @param mapOfFiles A map where the keys represent file names and the values contain lists of file paths associated with the data extraction.
     * @param response The existing AI response object to which the extracted data is related.
     * @return AI_Response__c The AI response record updated with the extracted data.
     */
    
    public static AI_Response__c getExtractedData(Id recordId, AI_Prompt__c aiPrompt, Map<String, List<String>> mapOfFiles, AI_Response__c response){
        // @Jira : 4802 : add AIDataExtractionService.DataPIIWrapper
        AIDataExtractionService.DataPIIWrapper dataPIIKeyWrapper = AIDataExtractionService.extractData(recordId, aiPrompt, mapOfFiles, response);
        response = dataPIIKeyWrapper.resp;
        if(aiPrompt.AI_Data_Extraction_Mapping__c != null && aiPrompt.AI_Data_Extraction_Mapping__r.AI_Data_Source__c != null){
            if(!Test.isRunningTest()){
				if(!checkLicensePlanActive(System.Label.LICENSES_PRO_PLAN)){
                	throw new ApplicationException(String.format(System.Label.LICENESES_PLAN_ERROR_MESSAGE,new List<String>{System.Label.LICENSES_PRO_PLAN})); 
            	}                
            }
			response.Extracted_Data__c = response.Data_Original__c;
            AI_Data_Source__c ds = aiPrompt.AI_Data_Extraction_Mapping__r.AI_Data_Source__r;
            if(String.isNotBlank(ds.Connector_Class__c)){
                Type impl = Type.forName('', ds.Connector_Class__c);
                AIDataSourceInterface obj = (AIDataSourceInterface)impl.newInstance();
                response.Data_Original__c = obj.getExternalData(ds, response.Extracted_Data__c);
            }             
        }
        // @Jira : 5912 : New Security Layer - Apex
        if(aiPrompt.AI_Data_Extraction_Mapping__c != null && aiPrompt.AI_Data_Extraction_Mapping__r.Apex_Security_Layer__r.Apex_Class_Name__c != null){
            Type impl = Type.forName('', aiPrompt.AI_Data_Extraction_Mapping__r.Apex_Security_Layer__r.Apex_Class_Name__c);
            AIApexSecurityLayerInterface obj = (AIApexSecurityLayerInterface)impl.newInstance();
            AIApexSecurityLayerDataWrapper dataWrapper = obj.getExtractData(new AIApexSecurityLayerDataWrapper(response, dataPIIKeyWrapper.mapOfPIIKeyToMatchCompleteWord));
            if(dataWrapper != null){
                response = dataWrapper.response;
                dataPIIKeyWrapper.mapOfPIIKeyToMatchCompleteWord = dataWrapper.mapOfPIIKeyToMatchCompleteWord;
            }
        } 
        // @Jira : 4802 : add mapOfPIIKeyToMatchCompleteWord param for check matchcompleteword is true or not.
        response = AIDataExtractionService.anonymizeData(response,dataPIIKeyWrapper.mapOfPIIKeyToMatchCompleteWord);
        return response;
    }
    
    /**
     * Processes the request to handle AI-related operations for the specified record, utilizing the provided AI prompt, file references, response ID, and existing AI response object.
     * 
     * @param recordId The ID of the record associated with the AI-related operations.
     * @param aiPrompt The AI prompt object containing relevant information for the processing.
     * @param mapOfFiles A map where the keys represent file names and the values contain lists of file paths related to the AI operations.
     * @param responseId The ID associated with the response for the processing.
     * @param response The existing AI response object that is being processed and updated.
     * @return AI_Response__c The updated AI response record after the processing.
     */
    public static AI_Response__c processRequest(Id recordId, AI_Prompt__c aiPrompt, Map<String, List<String>> mapOfFiles, String responseId, AI_Response__c response){

        response.AI_Callout_Start_Time__c = System.now();
        String gptResponse = '';
        if(aiPrompt.Enable_Loopback__c){
            try{
                gptResponse = JSON.serializePretty((Map<String, Object>)JSON.deserializeUntyped(aiPrompt.Loopback_Message__c));
            }catch(Exception e){
                GPTfyException.log(e, 'GPTfy', '', 'AIGPTfyCalloutController', 'validateRequest', e.getMessage());
                gptResponse =  '{"error" : {"message" : "'+e.getMessage()+'"}}';
            }
        }else{
            gptResponse = AIGPTfyCalloutController.processRequest(aiPrompt.Prompt_Command__c, response.Data_PII_Removed__c, aiPrompt);
        }
        
        response.AI_Callout_End_Time__c = System.now();
        response.AI_Processed_Data_No_PII__c = gptResponse;

        String gptResponseParsed;
        
        if(aiPrompt.AI_Connection__r.AI_Technology__c == 'GPTfy'){
            gptResponseParsed = parseGPTfyResponse(gptResponse);
        }else if(aiPrompt.AI_Connection__r.AI_Technology__c == 'OpenAI_ChatGPT'){
            gptResponseParsed = parseChatGptResponse(gptResponse, aiPrompt.AI_Connection__r.Model__c);
        }else{
            gptResponseParsed = parseOtherResponse(gptResponse);
        }
        String gptDeanonymizeData = AIDataExtractionService.deAnonymizeData(response, gptResponseParsed);
        response.Record_Id__c = recordId;
        response.GPT_Config__c = aiPrompt.AI_Connection__r.Name;
        response.AI_Prompt__c = aiPrompt.Id;
        response.Prompt_Command__c = aiPrompt.Prompt_Command__c;
        response.Profiles__c = aiPrompt.Profiles__c;
        response.Prompt_Version__c = aiPrompt.Prompt_Version__c;
        response.How_It_Works__c = aiPrompt.How_It_Works__c;
        response.Status__c = AIConstants.RESP_STATUS_PROCESSED;
        response.Message__c = '';

        //calculate usage tracking
        List<AI_Usage_Tracking__c> upsertList = new List<AI_Usage_Tracking__c>();
        response = AIUsageTrackingController.getTokensFromResponse(response);
        if(response.Total_Tokens__c > 0){
            List<AI_Usage_Tracking__c> lstOfTrackings = AIUsageTrackingController.getUsageTrackings(response);
            if(lstOfTrackings != null && !lstOfTrackings.isEmpty()){
                upsertList.addAll(lstOfTrackings);
            }
        }
        
        //for cohere
        if(aiPrompt.AI_Connection__c != null && aiPrompt.AI_Connection__r.AI_Technology__c.containsIgnoreCase('Cohere')){
            String data = gptDeanonymizeData;
            if(String.isNotBlank(data)){
                CohereWrapper maps = (CohereWrapper)JSON.deserialize(data, CohereWrapper.class);
                if(maps != null && maps.generations != null && !maps.generations.isEmpty() && String.isNotBlank(maps.generations.get(0).text)){
                    response.AI_Processed_Data_PII_Added__c = maps.generations.get(0).text;
                }
            }
        }else{
            //for anything other that cohere
            response.AI_Processed_Data_PII_Added__c = gptDeanonymizeData;
        }
        
        if(String.isBlank(response.AI_Processed_Data_PII_Added__c)){
            response.Message__c = AIConstants.AI_BLANK_RESPONSE;
            response.Status__c = AIConstants.RESP_STATUS_ERROR;
        }
        
        if(String.isNotBlank(response.AI_Processed_Data_No_PII__c)){
            String msg = getErrorMessage(response.AI_Processed_Data_No_PII__c);
            if(String.isNotBlank(msg)){
                response.Message__c = msg;
                response.Status__c = AIConstants.RESP_STATUS_ERROR;
            }
        }
        if(String.isNotBlank(aiPrompt.AI_Connection__c) && String.isNotBlank(aiPrompt.AI_Connection__r.AI_Response_Mapping__c) && hasResponseMapping(aiPrompt.AI_Connection__r.AI_Response_Mapping__c)){
            parseResponse(response, gptResponse, aiPrompt.AI_Connection__r.AI_Response_Mapping__c);
        }
        if(responseId != null && String.isNotBlank(responseId)){
            response.Id = responseId;
        }
        
        if(!AIResponseValidationUtility.validateResponse(aiPrompt, response.AI_Processed_Data_PII_Added__c)){
            response.Message__c = aiPrompt.Response_Validation_Message__c;
        	response.Status__c = AIConstants.RESP_STATUS_ERROR;
        }
        
        response.End_Date_Time__c = System.Now();
        
        response = insertAIResponse(response, true);
        
        //updating license usage count to track user based license
        AILicenseManagerController.updateLicenseUsage();
        
        if(response != null && !upsertList.isEmpty()){
            for(AI_Usage_Tracking__c track : upsertList){
                track.Lifetime_Saving_Seconds__c += response.Time_Saved_Seconds__c ;
            }
            List<AI_Usage_Tracking__c> utList = FLSCheck.getInstance().upsertDML(upsertList);
            AIUsageTrackingController.upsertUsageTrackingDetails(utList,response.Time_Saved_Seconds__c);
        }
        
        //Jira - 7221: Processing Prompt Actions only when the response is success.
        if(response.Status__c == AIConstants.RESP_STATUS_PROCESSED){
            List<AI_Security_Audit_Detail__c> lstOfAuditDetails = AIPromptActionService.managePromptActions(response);
            if(lstOfAuditDetails != null && !lstOfAuditDetails.isEmpty()){
                Boolean isError = false;
                for(AI_Security_Audit_Detail__c detail : lstOfAuditDetails){
                    if(detail.Status__c == AIConstants.SECURITY_AUDIT_DETAIL_STATUS_ERRORED){
                        isError = true;
                        break;
                    }
                }
                if(isError){
                    response.Status__c = AIConstants.RESP_STATUS_ERROR;
                    response.Message__c = 'One or more Prompt Action failed, please contact your System Admin.';
                    FLSCheck.getInstance().updateDML(new List<AI_Response__c>{response});
                }
            }
        }
        
        return response;
    }
    public static boolean hasResponseMapping(String responseMappingName){
        Boolean hasMetadata = false;
        for(AI_Response_Mapping__c rm : [SELECT Id FROM AI_Response_Mapping__c WHERE Id =: responseMappingName limit 1]){
            hasMetadata = true;
        }
        return hasMetadata;
    }
	
    public static void parseResponse(AI_Response__c response, String jsonString, String responseMappingName){
        Map<String, Object> mapResponse = (Map<String, Object>)JSON.deserializeUntyped(jsonString);
        if(!mapResponse.IsEmpty()){
            for(AI_Response_Mapping_Line__c responseMappingLine : [SELECT Security_Audit_Field_Name__c,Mapping_Field_Name__c FROM AI_Response_Mapping_Line__c WHERE AI_Response_Mapping__c =: responseMappingName LIMIT 50000]){
                List<String> path = String.valueOf(responseMappingLine.Mapping_Field_Name__c).split('\\.');
                if(path  != null && path.size()>0){
                    response.put(responseMappingLine.Security_Audit_Field_Name__c, getResponse(path, mapResponse.get(path.remove(0))));
                }
            }
        }
    }

    public static Object getResponse(List<String> path, Object obj){
        if(obj instanceof map<string,object>){
            Map<String, Object> response = (Map<String, Object>)obj;
            Object newobj = response.get(path.remove(0));
            return (path.size()>0?getResponse(path, newobj):newobj);
        }else if(obj instanceof list<object>){
            list<Object> response = (list<Object>)obj;
            if(response != null && response.size()>0){
                Map<String, Object> mresponse = (Map<String, Object>)response.get(0);
                Object newobj = mresponse.get(path.remove(0));
                return (path.size()>0?getResponse(path, newobj):newobj);
            }
        }else{
            Map<String, Object> response = (Map<String, Object>)obj;
            Object newobj;
            if(response != null && !response.isEmpty()){
                newobj = response.get(path.remove(0));
            }
            return ((newobj != null && path.size()>0)?getResponse(path, newobj):newobj);
        }
        return null;
    }

    /**
     * Parses the JSON response from the Chatbot GPT model and retrieves the relevant data based on the specified model.
     * 
     * @param jsonString The JSON string containing the response data from the Chatbot GPT model.
     * @param model The name or identifier of the specific GPT model used for the response.
     * @return String The parsed data extracted from the JSON response, relevant to the specified GPT model.
     */
    public static String parseChatGptResponse(String jsonString, String model){
        Map<String, Object> dataMap = (Map<String, Object>)JSON.deserializeUntyped(jsonString);
        if(model == 'text-davinci-003'){
            JSONParser parser = JSON.createParser(jsonString);
            String parsedResponse = '';
            while (parser.nextToken() != null){
                if((parser.getCurrentToken() == JSONToken.FIELD_NAME) && (parser.getText() == 'text')){
                    parser.nextToken();
                    parsedResponse = parser.getText();
                }
            }
            return parsedResponse;
        }
         //@Jira V2-7425 
        else if (dataMap != null && dataMap.containsKey('output')) {
            List<Object> outputList = (List<Object>)dataMap.get('output');
            if (outputList != null && !outputList.isEmpty()) {
                String assistantResponse = '';
                for (Object obj : outputList) {
                    Map<String, Object> objMap = (Map<String, Object>)obj;
                    if (objMap != null && objMap.containsKey('type') && 
                        String.valueOf(objMap.get('type')) == 'message') {
                        List<Object> contentList = (List<Object>)objMap.get('content');
                        if (contentList != null && !contentList.isEmpty()) {
                            Map<String, Object> contentMap = (Map<String, Object>)contentList.get(0);
                            if (contentMap != null && contentMap.containsKey('text')) {
                                assistantResponse+=String.valueOf(contentMap.get('text')) + '\n';
                            }
                        }
                    }
                }
                return assistantResponse;
            }
            return jsonString;
        }else{
            if(dataMap.containsKey('choices')){
                List<object> choicesList = (List<object>)dataMap.get('choices');
                Map<String, Object> choiceMap = (Map<String, Object>)choicesList.get(0);
                if(choiceMap.containsKey('message')){
                    Map<String, Object> messageMap = (Map<String, Object>)choiceMap.get('message');
                    return String.valueOf(messageMap.get('content'));
                } 
            }
            return jsonString;
        }
        
    }

    /**
     * Parses the JSON response from the GPTfy service and extracts the relevant data from the provided JSON string.
     * 
     * @param jsonString The JSON string containing the response data from the GPTfy service.
     * @return String The parsed data extracted from the JSON response for further processing.
     */
    public static String parseGPTfyResponse(String jsonString){
        if(String.isNotBlank(jsonString)){
            Map<String,Object> mainMap = (Map<String,Object>)JSON.deserializeUntyped(jsonString);
            if(mainMap != null && mainMap.containsKey('data')){
				Boolean isJSON = true;
                try{
                    //check if the data returned is in the JSON format
                    Map<String, Object> dataMap = (Map<String,Object>)mainMap.get('data');
                    if(dataMap != null && dataMap.containsKey('value')){
                        Map<String, Object> valueMap = (Map<String,Object>)dataMap.get('value');
                        if(valueMap != null && valueMap.containsKey('choices')){
                            List<object> choicesList = (List<object>)valueMap.get('choices');
                            Map<String, Object> choiceMap = (Map<String, Object>)choicesList.get(0);
                            if(choiceMap != null && choiceMap.containsKey('text')){
                                return String.valueOf(choiceMap.get('text'));
                            }else if(choiceMap != null && choiceMap.containsKey('message') && choiceMap.get('message') != null){
                                Map<String, Object> msgMap = (Map<String, Object>)choiceMap.get('message');
                                if(msgMap != null && msgMap.containsKey('content') && msgMap.get('content') != null){
                                    return String.valueOf(msgMap.get('content'));
                                }
                            } 
                        }
                    }else if(dataMap != null && dataMap.containsKey('predictions')){
                        List<Object> predictionList = (List<Object>)dataMap.get('predictions');
                        if(predictionList != null && !predictionList.isEmpty()){
                            Map<String, Object> predictionMap = (Map<String, Object>)predictionList.get(0);
                            if(predictionMap != null && predictionMap.containsKey('content') && predictionMap.get('content') != null){
                                return String.valueOf(predictionMap.get('content'));
                            }
                        }
                    }
                }catch(Exception e){
                    isJSON = false;
                }
                if(!isJSON){
                    if(mainMap.get('data') != null){
                        return String.valueOf(mainMap.get('data'));
                    }
                }
                
            }else if(mainMap != null && mainMap.containsKey('choices')){
                List<Object> choices = (List<Object>) mainMap.get('choices');
                Map<String, Object> choiceObj = (Map<String, Object>) choices[0];
                Map<String, Object> message = (Map<String, Object>) choiceObj.get('message');
                return (String) message.get('content');

            }
             //@Jira V2-7425 
            else if (mainMap != null && mainMap.containsKey('output')) {
                List<Object> outputList = (List<Object>)mainMap.get('output');
                if (outputList != null && !outputList.isEmpty()) {
                    String assistantResponse = '';
                    for (Object obj : outputList) {
                        Map<String, Object> dataMap = (Map<String, Object>)obj;
                        if (dataMap != null && dataMap.containsKey('type') && 
                            String.valueOf(dataMap.get('type')) == 'message') {
                            List<Object> contentList = (List<Object>)dataMap.get('content');
                            if (contentList != null && !contentList.isEmpty()) {
                                Map<String, Object> contentMap = (Map<String, Object>)contentList.get(0);
                                if (contentMap != null && contentMap.containsKey('text')) {
                                    assistantResponse+=String.valueOf(contentMap.get('text')) + '\n';
                                }
                            }
                        }
                    }
                    return assistantResponse;
                }
            }
        }
        return jsonString;
    }
	
    /**
     * Parses the JSON response from an external service and extracts the relevant data from the provided JSON string.
     * 
     * @param jsonString The JSON string containing the response data from the external service.
     * @return String The parsed data extracted from the JSON response for further processing.
     */
    public static String parseOtherResponse(String jsonString){
        Map<String,Object> dataMap = (Map<String,Object>)JSON.deserializeUntyped(jsonString);

        if(dataMap.containsKey('choices')){
            List<object> choicesList = (List<object>)dataMap.get('choices');
            Map<String,Object> choiceMap = (Map<String,Object>)choicesList.get(0);
            if(choiceMap != null && choiceMap.containsKey('text')){
                return String.valueOf(choiceMap.get('text'));
            }else if(choiceMap != null && choiceMap.containsKey('message')){
                Map<String,Object> msgMap = (Map<String, Object>)choiceMap.get('message');
                if(msgMap != null && msgMap.containsKey('content')){
                    return String.valueOf(msgMap.get('content'));
                }
            }else if(choiceMap != null && choiceMap.containsKey('messages')){
                List<Object> msgsList = (List<Object>)choiceMap.get('messages');
                if(msgsList != null && !msgsList.isEmpty()){
                    for(Object obj : msgsList){
                        Map<String,Object> msgMap = (Map<String, Object>)obj;
                        if(msgMap.containsKey('content') && msgMap.containsKey('role') && String.valueOf(msgMap.get('role')) == 'assistant' && msgMap.containsKey('end_turn') && Boolean.valueOf(msgMap.get('end_turn'))){
                            return String.valueOf(msgMap.get('content'));
                        }
                    }
                }
            }
        }else if(dataMap.containsKey('predictions') && dataMap.get('predictions') != null){
            List<object> predictList = (List<object>)dataMap.get('predictions');
            Map<String,Object> predictMap = (Map<String,Object>)predictList.get(0);
            if(predictMap != null && predictMap.containsKey('candidates') && predictMap.get('candidates') != null){
                List<object> candidateList = (List<object>)predictMap.get('candidates');
                Map<String,Object> candidateMap = (Map<String,Object>)candidateList.get(0);
                if(candidateMap != null && candidateMap.containsKey('content')){
                    return String.valueOf(candidateMap.get('content'));
                }
            }
        }
        //google dialogflow change
        else if(dataMap.containsKey('queryResult') && dataMap.get('queryResult') != null){
            Map<String, Object> queryResultMap = (Map<String,Object>)dataMap.get('queryResult');
            if(queryResultMap != null && queryResultMap.containsKey('responseMessages')){
                List<object> respMessagesList = (List<object>)queryResultMap.get('responseMessages');
                List<String> lstOfReturnText = new List<String>();
                for(Object respMessage : respMessagesList){
                    Map<String, Object> respMessageMap = (Map<String,Object>)respMessage;
                    if(respMessageMap != null && respMessageMap.containsKey('text')){
                        Map<String, Object> textMap = (Map<String,Object>)respMessageMap.get('text');
                        if(textMap != null && textMap.containsKey('text')){
                            List<Object> textList = (List<object>)textMap.get('text');
                            if(textList != null && !textList.isEmpty()){
                                lstOfReturnText.add(String.valueOf(textList.get(0)));
                        	}
                        } 
                    }else if(respMessageMap != null && respMessageMap.containsKey('payload')){
                        Map<String, Object> payloadMap = (Map<String,Object>)respMessageMap.get('payload');
                        if(payloadMap != null && payloadMap.containsKey('richContent')){
                            List<object> richContentList = (List<object>)payloadMap.get('richContent');
                            if(richContentList != null && !richContentList.isEmpty()){
                                List<Object> richContentChildList = (List<object>)richContentList.get(0);
                                if(richContentChildList != null && !richContentChildList.isEmpty()){
                                    Map<String, Object> richContentChildMap = (Map<String,Object>)richContentChildList.get(0);
                                    if(richContentChildMap != null && richContentChildMap.containsKey('actionLink')){
                                        String link = String.valueOf(richContentChildMap.get('actionLink'));
                                        if(string.isNotBlank(link) && link.contains('#:~:')){
                                            link = link.subStringBefore('#:~:');
                                        }
                                        lstOfReturnText.add(link);
                                    }
                                }
                            }
                        }
                    }
                }
                if(lstOfReturnText != null && !lstOfReturnText.isEmpty()){
                    return String.join(lstOfReturnText, '\n\n');
                }
            }
        }else if(dataMap.containsKey('completion') && dataMap.get('completion') != null && String.isNotBlank(String.valueOf(dataMap.get('completion')))){
            return String.valueOf(dataMap.get('completion'));
        }else if(dataMap.containsKey('output') && dataMap.get('output') != null){
            try{
                Map<String, Object> outputMap = (Map<String,Object>)dataMap.get('output');
                if(outputMap != null && outputMap.containsKey('text')){
                    return String.valueOf(outputMap.get('text'));
                }else if(outputMap != null && outputMap.containsKey('message')){
                    Map<String, Object> messageMap = (Map<String,Object>)outputMap.get('message');
                    if(messageMap != null && messageMap.containsKey('content')){
                        List<Object> contentList = (List<Object>)messageMap.get('content');
                        if(contentList != null && !contentList.isEmpty()){
                            Map<String, Object> contentTextMap = (Map<String, Object>)contentList.get(0);
                            if(contentTextMap != null && contentTextMap.containsKey('text')){
                                return String.valueOf(contentTextMap.get('text'));
                            }
                        }
                    }
                }
            }catch(Exception e){
                 //@Jira V2-7425 
                List<Object> outputList = (List<Object>)dataMap.get('output');
                if (outputList != null && !outputList.isEmpty()) {
                    String assistantResponse = '';
                    for (Object obj : outputList) {
                        Map<String, Object> objMap = (Map<String, Object>)obj;
                        if (objMap != null && objMap.containsKey('type') && 
                            String.valueOf(objMap.get('type')) == 'message') {
                            List<Object> contentList = (List<Object>)objMap.get('content');
                            if (contentList != null && !contentList.isEmpty()) {
                                Map<String, Object> contentMap = (Map<String, Object>)contentList.get(0);
                                if (contentMap != null && contentMap.containsKey('text')) {
                                    assistantResponse+=String.valueOf(contentMap.get('text')) + '\n';
                                }
                            }
                        }
                    }
                    return assistantResponse;
                }
            }
        }
        return jsonString;
    }
    
    /**
     * Retrieves the error message from the provided JSON string, typically generated in response to an error condition.
     * 
     * @param jsonString The JSON string containing the error message from a response or request.
     * @return String The error message extracted from the JSON response for handling and display purposes.
     */
    public static String getErrorMessage(String jsonString){
        String message = '';
        Map<String,Object> dataMap = (Map<String,Object>)JSON.deserializeUntyped(jsonString);

        if(dataMap.containsKey('error') && dataMap.get('error') != null){
            Map<String, Object> errorMap = (Map<String,Object>)dataMap.get('error');
            if(errorMap.containsKey('message') && String.isNotBlank(String.valueOf(errorMap.get('message')))){
                message = String.valueOf(errorMap.get('message'));
            }
        }else if(dataMap.containsKey('errorCode') && dataMap.containsKey('errorText')){
            message = String.valueOf(dataMap.get('errorText'));
        }else if(dataMap.containsKey('type') && String.valueOf(dataMap.get('type')) == 'invalid_request_error'){
            message = String.valueOf(dataMap.get('message'));
        }else if(dataMap.containsKey('code') && String.valueOf(dataMap.get('code')) == '404'){
            message = String.valueOf(dataMap.get('message'));
        }else if(dataMap.containsKey('message') && String.isNotBlank(String.valueOf(dataMap.get('message')))){
            message = String.valueOf(dataMap.get('message'));
        }
        return message;
    }
    
    public class CohereWrapper{
        public String id{get;set;}
        public List<CohereGenerationWrapper> generations{get;set;}
    }

    public class CohereGenerationWrapper{
        public String id{get;set;}
        public String text{get;set;}
    }
    
    
    /**
     * Processes the file request based on the provided list of content distribution IDs (cdIds) and retrieves the relevant file data.
     * 
     * @param cdIds A list of content distribution IDs representing the requested files.
     * @return Map<String, String> A map where the keys represent file names, and the values contain the corresponding file data for further processing.
     */
    @AuraEnabled
    public static FileResponseWrapper processFileRequest(String promptId, String recordId, String userInput, List<String> cdIds, String fwrapStr){
        FileResponseWrapper fwrap = (FileResponseWrapper) System.JSON.deserialize(fwrapStr, FileResponseWrapper.class);

        AI_Prompt__c aiPrompt = AIPromptSelector.getAIPromptById(promptId);
        if(aiPrompt != null && aiPrompt.AI_Model_File_Processing__c != null){
            if(aiPrompt.AI_Model_File_Processing__r.AI_Technology__c == AIConstants.PRODUCT_NAME){
                fwrap.mapOfCdIdToEndpointUrls = AIGPTfyCalloutController.processGPTfyFileRequest(cdIds); 
            }else if(aiPrompt.AI_Model_File_Processing__r.Model__c == AIConstants.GPT_4o_MODEL){
                if(String.isBlank(fwrap.vectorStoreId)){
                    AIAssistantApiCalloutUtility.AssistantWrapper wrap = new AIAssistantApiCalloutUtility.AssistantWrapper();
                    wrap.recordId = recordId;
                    wrap.aiModel = aiPrompt.AI_Model_File_Processing__r;
                    wrap.cdIds = cdIds;
                    wrap = AIAssistantApiCalloutUtility.processFileRequest(wrap);
                    
                    fwrap.uploadedFileId = wrap.uploadedFileId;
                    fwrap.vectorStoreId = wrap.vectorStoreId;
                    Integer delay = 15;
                    if(String.isNotBlank(Label.Assistant_API_Delay)){
                        try{
                            delay = Integer.valueOf(Label.Assistant_API_Delay);
                        }catch(Exception e){}
                    }
                    fwrap.delay = delay;
                }else{
                    aiPrompt.Prompt_Command__c = preparePromptCommand(aiPrompt, userInput, recordId, true);
                    if(String.isBlank(aiPrompt.Prompt_Command__c) && !Test.isRunningTest()){
                        throw new ApplicationException('Either Prompt command or User Input is required to run the Prompt.');
                    }
                    
                    AI_Response__c response = new AI_Response__c();
                    response.Start_Date_Time__c = System.Now();
                    response = getExtractedData(recordId, aiPrompt, null, response);
                    response.AI_Callout_Start_Time__c = System.now();
                    
                    response.Record_Id__c = recordId;
                    response.GPT_Config__c = aiPrompt.AI_Connection__r.Name;
                    response.AI_Prompt__c = aiPrompt.Id;
                    response.Prompt_Command__c = aiPrompt.Prompt_Command__c;
                    response.Profiles__c = aiPrompt.Profiles__c;
                    response.Prompt_Version__c = aiPrompt.Prompt_Version__c;
                    response.How_It_Works__c = aiPrompt.How_It_Works__c;
                    response.Status__c = AIConstants.RESP_STATUS_INPROGRESS;
                    response.Message__c = '';
                    
                    AIAssistantApiCalloutUtility.AssistantWrapper wrap = new AIAssistantApiCalloutUtility.AssistantWrapper();
                    wrap.recordId = recordId;
                    wrap.aiModel = aiPrompt.AI_Model_File_Processing__r;
                    wrap.cdIds = cdIds;
                    wrap.promptCommand = aiPrompt.Prompt_Command__c;
                    wrap.extractedData = response.Data_PII_Removed__c;
                    wrap.uploadedFileId = fwrap.uploadedFileId;
                    wrap.vectorStoreId = fwrap.vectorStoreId;
                    
                    try{
                        wrap = AIAssistantApiCalloutUtility.processFileRequest(wrap);
                    }catch(Exception e){
                        response.Status__c = AIConstants.RESP_STATUS_ERROR;
                        response.Message__c = e.getMessage(); 
                        if(String.isBlank(response.Message__c)){
                            response.Message__c = AIConstants.AI_GENERAL_ERROR;
                        }
                    }
    
                    response.AI_Callout_End_Time__c = System.now(); 
                    response = insertAIResponse(response, true); 
                    
                    fwrap.threadId = wrap.threadId;
                    fwrap.runId = wrap.runId;
                    fwrap.runStatus = wrap.runStatus;
                    fwrap.aiResponseId = response.Id;
                    fwrap.delay = 0;
                    if(response.Status__c == AIConstants.RESP_STATUS_ERROR){
                        fwrap.isError = true;
                        fwrap.errorMessage = response.Message__c;
                    }
                }
            }else{
                fwrap.mapOfCdIdToEndpointUrls = AIGPTfyCalloutController.processFileRequest(aiPrompt.AI_Model_File_Processing__r, cdIds);
            }
        }
        
        return fwrap;
    }
    
    /**
     * Retrieves the analysis results based on the provided map of endpoint URLs, performing analysis on the corresponding resources.
     * 
     * @param mapOfEndpointUrls A map where the keys represent endpoint URLs, and the values contain the corresponding resources to be analyzed.
     * @return Map<String, String> A map where the keys represent analysis results, and the values contain relevant data or information derived from the analysis process.
     */
    @AuraEnabled
    public static FileResponseWrapper getAnalyzeResult(String promptId, String fwrapStr){ 
        FileResponseWrapper fwrap = (FileResponseWrapper) System.JSON.deserialize(fwrapStr, FileResponseWrapper.class);
        AI_Prompt__c aiPrompt = AIPromptSelector.getAIPromptById(promptId);
        if(aiPrompt != null && aiPrompt.AI_Model_File_Processing__c != null){
            if(aiPrompt.AI_Model_File_Processing__r.AI_Technology__c == AIConstants.PRODUCT_NAME){
                fwrap.mapOfCdIdToFileData = AIGPTfyCalloutController.getGPTfyAnalyzeResult(fwrap.mapOfCdIdToEndpointUrls);
            }else if(aiPrompt.AI_Model_File_Processing__r.Model__c == AIConstants.GPT_4o_MODEL){
                AIAssistantApiCalloutUtility.AssistantWrapper wrap = new AIAssistantApiCalloutUtility.AssistantWrapper();
                wrap.threadId = fwrap.threadId;
                wrap.runId = fwrap.runId;
                wrap.runStatus = fwrap.runStatus;     
                wrap.aiModel = aiPrompt.AI_Model_File_Processing__r;
                wrap = AIAssistantApiCalloutUtility.getAnalyzeResult(wrap);
                
                if(wrap.runStatus != 'queued' && wrap.runStatus != 'in_progress'){
                    AI_Response__c response = [SELECT Id, Data_Decrypt_PII_Key__c 
                                               FROM AI_Response__c 
                                               WHERE Id =:fwrap.aiResponseId
                                               LIMIT 1];
                    response.AI_Processed_Data_No_PII__c = wrap.assistantResponse;
                    response.End_Date_Time__c = System.Now(); 
                    response.AI_Processed_Data_PII_Added__c = AIDataExtractionService.deAnonymizeData(response, wrap.assistantResponse);
                    response.Status__c = AIConstants.RESP_STATUS_PROCESSED;
                    if(String.isBlank(response.AI_Processed_Data_PII_Added__c)){
                        response.Message__c = AIConstants.AI_BLANK_RESPONSE;
                        response.Status__c = AIConstants.RESP_STATUS_ERROR;
                    }
                    FLSCheck.getInstance().updateDML(new List<AI_Response__c>{response});
                }
                fwrap.runStatus = wrap.runStatus; 
            }else{
                fwrap.mapOfCdIdToFileData = AIGPTfyCalloutController.getAnalyzeResult(aiPrompt.AI_Model_File_Processing__r, fwrap.mapOfCdIdToEndpointUrls);
            }
        }
        return fwrap;
    } 
    
    public class FileResponseWrapper{
        @AuraEnabled public Map<String, String> mapOfCdIdToEndpointUrls{get;set;}
        @AuraEnabled public Map<String, String> mapOfCdIdToFileData{get;set;}
        
        @AuraEnabled public String uploadedFileId{get;set;}
        @AuraEnabled public String vectorStoreId{get;set;}
        @AuraEnabled public String threadId{get;set;}
        @AuraEnabled public String runId{get;set;}
        @AuraEnabled public String runStatus{get;set;}
        @AuraEnabled public String aiResponseId{get;set;}
        @AuraEnabled public Boolean isError{get;set;}
        @AuraEnabled public String errorMessage{get;set;}
        @AuraEnabled public Integer delay{get;set;}
    }
    
    @AuraEnabled
    public static Boolean checkLicensePlanActive(String planName){
        planName = planName.toLowerCase();
        String starter = String.valueOf(System.Label.LICENSES_STARTER_PLAN).toLowerCase();
        String pro = String.valueOf(System.Label.LICENSES_PRO_PLAN).toLowerCase();
        String enterprise = String.valueOf(System.Label.LICENSES_ENTERPRISE_PLAN).toLowerCase();

        Map<String, Object> licenseData = AILicenseManagerController.getLicensesForCheck();

        if(licenseData.containsKey('licenseBypass') && licenseData.get('licenseBypass') == true){
            return true;
        }

        List<Object> licenses = (List<Object>)licenseData.get('licenses');
        if(licenses == null || licenses.isEmpty()){
            return false;
        }

        Boolean isEnterpriseActive = false;
        Boolean isProActive = false;
        Boolean isStarterActive = false;

        for(Object licObj : licenses){
            Map<String, Object> lic = (Map<String, Object>)licObj;
            String licType = String.valueOf(lic.get('licenseType')).toLowerCase();
            String status = String.valueOf(lic.get('status'));
            if(status == 'Active'){
                if(licType == enterprise){
                    isEnterpriseActive = true;
                } else if(licType == pro){
                    isProActive = true;
                } else if(licType == starter){
                    isStarterActive = true;
                }
            }
        }

        if(planName == enterprise){
            return isEnterpriseActive;
        } else if(planName == pro){
            return isProActive || isEnterpriseActive;
        } else if(planName == starter){
            return isStarterActive || isProActive || isEnterpriseActive;
        }
        return false;
    }
    
    public static AI_Response__c insertAIResponse(AI_Response__c response, Boolean insertFiles){
     	
        List<String> longerFields = AIConstants.longerFields;
        List<ContentVersion> lstOfVersions = new List<ContentVersion>();
        
        if(insertFiles && longerFields != null && !longerFields.isEmpty()){
            Map<String, Schema.SObjectField> mapOfFields = AI_Response__c.getSObjectType().getDescribe().fields.getMap();
            
            //checking already present files
            if(response.Id != NULL){
                Set<String> setOfAlreadyAddedDocIds = new Set<String>();
                for(ContentDocumentLink cdl : [SELECT Id, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId =:response.Id]){
                    setOfAlreadyAddedDocIds.add(cdl.ContentDocumentId);
                } 
                if(!setOfAlreadyAddedDocIds.isEmpty()){
                    for(ContentVersion cv : [SELECT Id, VersionData, Title FROM ContentVersion WHERE ContentDocumentId IN :setOfAlreadyAddedDocIds]){
                        if(String.isNotBlank(cv.Title) && longerFields.contains(cv.Title)){
                            String data = '';
                            if(cv.VersionData != NULL){
                                data = cv.VersionData.toString();
                            }
                            response.put(cv.Title, '');
                        }
                    }
                }
            }

            //creating new files
            for(String fName : longerFields){
                Integer length = mapOfFields.get(fName).getDescribe().getLength();
                if(length > 0 && response.get(fName) != NULL && String.isNotBlank(String.valueOf(response.get(fName))) && String.valueOf(response.get(fName)).length() > length){
                    ContentVersion cv = new ContentVersion(
                        Title = fName, 
                        PathOnClient = fName+'.json',
                        VersionData = Blob.valueOf(String.valueOf(response.get(fName))),
                        origin = 'H'
                    );
                    lstOfVersions.add(cv);
                    response.put(fName, '');
                }
            }
        }

        try{
            response = (AI_Response__c)FLSCheck.getInstance().upsertDML(new List<AI_Response__c>{response}).get(0);
        }catch(Exception e){
            String message = e.getMessage();
            if(e.getTypeName() == 'System.DmlException'){
                message = e.getDMLMessage(0);
            }
            if(String.isNotBlank(message)){
                throw new ApplicationException(message);
            }
        }
        
        response = getQueriedAIResponse(response.Id);
        
        if(!lstOfVersions.isEmpty()){
            List<SObject> insertedVersions = FLSCheck.getInstance().insertDML(lstOfVersions);
            
            Set<String> versionIds = new Set<String>();
            for(SObject so : insertedVersions){
                versionIds.add(String.valueOf(so.get('Id')));
            }
            
  			List<ContentDocumentLink> lstOfLinks = new List<ContentDocumentLink>();
            for(ContentVersion cv : [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :versionIds]){
                lstOfLinks.add(new ContentDocumentLink(LinkedEntityId = response.Id, ContentDocumentId = cv.ContentDocumentId, ShareType = 'V'));
            } 
            if(!lstOfLinks.isEmpty()){
                FLSCheck.getInstance().insertDML(lstOfLinks);
            }
        }
        
        return response;
    }
    
    public static AI_Response__c getQueriedAIResponse(String responseId){
        return [SELECT Id, Name, Record_Id__c, Data_Original__c, Data_PII_Key__c, Data_PII_Removed__c, AI_Processed_Data_No_PII__c, 
                AI_Processed_Data_PII_Added__c, Completion_Tokens__c, Prompt_Tokens__c, Total_Tokens__c, Time_Saved_Seconds__c, 
                Time_Estimate_Seconds__c, Message__c, Status__c, AI_Prompt__c FROM AI_Response__c WHERE Id =:responseId];
    } 
    
    public static AI_Response__c getDataUsingFiles(AI_Response__c response){
        List<String> longerFields = AIConstants.longerFields;
        
        if(longerFields != null && !longerFields.isEmpty()){
            String responseId = response.Id;
			AI_Response__c aiResp = (AI_Response__c)Database.query('SELECT Id, '+String.join(longerFields, ', ')+' FROM '+AIConstants.NAMESPACE+'AI_Response__c WHERE Id =:responseId LIMIT 1');
            for(String fName : longerFields){
                response.put(fName, aiResp.get(fName));
            }
            
            Set<String> setOfDocIds = new Set<String>();
            for(ContentDocumentLink cdl : [SELECT Id, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId =:response.Id]){
                setOfDocIds.add(cdl.ContentDocumentId);
            } 
            if(!setOfDocIds.isEmpty()){
                for(ContentVersion cv : [SELECT Id, VersionData, Title FROM ContentVersion WHERE ContentDocumentId IN :setOfDocIds]){
                    if(String.isNotBlank(cv.Title) && longerFields.contains(cv.Title)){
                        String data = '';
                        if(cv.VersionData != NULL){
                            data = cv.VersionData.toString();
                        }
                        response.put(cv.Title, data);
                    }
                }
            }
        }
        return response;
    }
    
    public static void rollupAIResponseScheduledRun(String scheduledRunId){
        AI_Scheduled_Run__c scheduledRun = new AI_Scheduled_Run__c(Id=scheduledRunId, Errored_Records__c=0, InProgress_Records__c=0, Disqualified_Records__c=0, Processed_Records__c=0);
        for(AggregateResult agr : [SELECT Status__c status, count(Id) totalRecords FROM AI_Response__c WHERE Scheduled_Run__c=:scheduledRunId AND Status__c != null Group BY Status__c]){
            String status = (String)agr.get('status');
            if(status == AIConstants.RESP_STATUS_PROCESSED){
                scheduledRun.Processed_Records__c = (Integer)agr.get('totalRecords');
            }else if(status == AIConstants.RESP_STATUS_DISQ){
                scheduledRun.Disqualified_Records__c = (Integer)agr.get('totalRecords');
            }else if(status == AIConstants.RESP_STATUS_ERROR){
                scheduledRun.Errored_Records__c = (Integer)agr.get('totalRecords');
            }else{
                scheduledRun.InProgress_Records__c = (Integer)agr.get('totalRecords');
            }
        }
        FLSCheck.getInstance().updateDML(new List<AI_Scheduled_Run__c>{scheduledRun});
    }
    
    public class ApplicationException extends Exception {}

    public static Set<String> getMinedContentVersionIds(String jsonString){
        Set<String> minedIds = new Set<String>();

        Map<String,Object> parsedResponse = (Map<String,Object>) JSON.deserializeUntyped(jsonString);
        for(String key : parsedResponse.keySet()){
            try{
                if(key == 'Content Version'){
                    List<Object> records = (List<Object>) parsedResponse.get(key);
                    for(Object record : records){
                        Map<String,Object> recordMap = (Map<String,Object>)record;
                        minedIds.add(String.valueOf(recordMap.get('Id')));
                    }
                }else{
                    List<Object> records = (List<Object>) parsedResponse.get(key);
                    for(Object record : records){
                        Map<String,Object> recordMap = (Map<String,Object>)record;
                        for(String subKey : recordMap.keySet()){
                            if(subKey == 'Content Version'){
                                List<Object> subRecords = (List<Object>) recordMap.get(subKey);
                                for(Object subRecord : subRecords){
                                    Map<String,Object> subRecordsMap = (Map<String,Object>)subRecord;
                                    minedIds.add(String.valueOf(subRecordsMap.get('Id')));
                                }
                            }
                        }
                    }
                }
            }catch(Exception ex){
                continue;
            }
        }
        return minedIds;
    }
    @AuraEnabled
    public static String processResponsesFileRequest(String promptId, String recordId, String userInput, List<String> cdIds){
        AIResponsesApiCalloutUtility.ResponseApiWrapper wrap = new AIResponsesApiCalloutUtility.ResponseApiWrapper();
        AI_Prompt__c aiPrompt = AIPromptSelector.getAIPromptById(promptId);
        if(aiPrompt != null && aiPrompt.AI_Model_File_Processing__c != null){
            
            aiPrompt.Prompt_Command__c = preparePromptCommand(aiPrompt, userInput, recordId, true);
        
            AI_Response__c response = new AI_Response__c();
            response.Start_Date_Time__c = System.Now();
            response = getExtractedData(recordId, aiPrompt, null, response);
            response.AI_Callout_Start_Time__c = System.now();
            
            response.Record_Id__c = recordId;
            response.GPT_Config__c = aiPrompt.AI_Connection__r.Name;
            response.AI_Prompt__c = aiPrompt.Id;
            response.Prompt_Command__c = aiPrompt.Prompt_Command__c;
            response.Profiles__c = aiPrompt.Profiles__c;
            response.Prompt_Version__c = aiPrompt.Prompt_Version__c;
            response.How_It_Works__c = aiPrompt.How_It_Works__c;
            response.Status__c = AIConstants.RESP_STATUS_INPROGRESS;
            response.Message__c = '';
            
            wrap.recordId = recordId;
            wrap.aiModel = aiPrompt.AI_Model_File_Processing__r;
            wrap.promptCommand = aiPrompt.Prompt_Command__c + ' ' + userInput;
            wrap.extractedData = response.Data_PII_Removed__c;
            Set<String> minedContentVersionsIds = getMinedContentVersionIds(wrap.extractedData);
            if(Id.valueOf(recordId).getSObjectType() == ContentVersion.SObjectType){
                minedContentVersionsIds.add(recordId);
            }
            minedContentVersionsIds.addAll(getContentVersionIds(cdIds));
            wrap.cdIds = minedContentVersionsIds;
            try{
                if(!minedContentVersionsIds.isEmpty()){
                    wrap = AIResponsesApiCalloutUtility.processFileRequest(wrap);
                    //response.Files_Id__c = String.join(wrap.uploadedFileIds, ', ');
                    response.Vector_Store_Id__c = wrap.vectorStoreId;
                }else{
                    response.Status__c = AIConstants.RESP_STATUS_ERROR;
                    response.Message__c = 'Either the files are missing or filter does not match.';
                    if(String.isBlank(response.Message__c)){
                        response.Message__c = AIConstants.AI_GENERAL_ERROR;
                    }
                    response.AI_Callout_End_Time__c = System.now(); 
                    response = insertAIResponse(response, true); 
                }
            }catch(Exception e){
                response.Status__c = AIConstants.RESP_STATUS_ERROR;
                response.Message__c = e.getMessage();
                if(String.isBlank(response.Message__c)){
                    response.Message__c = AIConstants.AI_GENERAL_ERROR;
                }
                response.AI_Callout_End_Time__c = System.now(); 
                response = insertAIResponse(response, true); 
            }
            wrap.aiResponse = response;
        }
        return JSON.serialize(wrap);
    }
    private static Set<String> getContentVersionIds(List<String> cdIds){
        Set<String> cvIds = new Set<String>();

        for(ContentVersion cv : [SELECT Id FROM ContentVersion WHERE ContentDocumentId IN :cdIds]){
            cvIds.add(cv.Id);
        }
        return cvIds;
    }
    @AuraEnabled
    public static string getAnalyzeResponsesResult(String fileId, String wrapJSON){
        try {
            AIResponsesApiCalloutUtility.ResponseApiWrapper wrap = (AIResponsesApiCalloutUtility.ResponseApiWrapper)JSON.deserialize(wrapJSON, AIResponsesApiCalloutUtility.ResponseApiWrapper.class);
            wrap.fileId = fileId;
            wrap.fileStatus = '';
            wrap = AIResponsesApiCalloutUtility.getFileStatus(wrap);
            return wrap.fileStatus;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    @AuraEnabled
    public static String getPromptResponse(String wrapJSON){
        AIResponsesApiCalloutUtility.ResponseApiWrapper wrap = (AIResponsesApiCalloutUtility.ResponseApiWrapper)JSON.deserialize(wrapJSON, AIResponsesApiCalloutUtility.ResponseApiWrapper.class);
        try{
            wrap = AIResponsesApiCalloutUtility.createResponses(wrap);
            wrap.aiResponse.Thread_Id__c = wrap.previousResponseId;
            wrap.aiResponse.AI_Processed_Data_No_PII__c = wrap.response;
            String gptDeanonymizeData = AIDataExtractionService.deAnonymizeData(wrap.aiResponse, parseGPTfyResponse(wrap.response));
            wrap.aiResponse.AI_Processed_Data_PII_Added__c = gptDeanonymizeData;
            wrap.aiResponse.Status__c = AIConstants.RESP_STATUS_PROCESSED;
            
            List<AI_Usage_Tracking__c> upsertList = new List<AI_Usage_Tracking__c>();
            wrap.aiResponse = AIUsageTrackingController.getTokensFromResponse(wrap.aiResponse);
            if(wrap.aiResponse.Total_Tokens__c > 0){
                List<AI_Usage_Tracking__c> lstOfTrackings = AIUsageTrackingController.getUsageTrackings(wrap.aiResponse);
                if(lstOfTrackings != null && !lstOfTrackings.isEmpty()){
                    upsertList.addAll(lstOfTrackings);
                }
            }
            if(wrap.aiResponse != null && !upsertList.isEmpty() && wrap.aiResponse.Time_Saved_Seconds__c != null){
                for(AI_Usage_Tracking__c track : upsertList){
                    track.Lifetime_Saving_Seconds__c += wrap.aiResponse.Time_Saved_Seconds__c ;
                }
                List<AI_Usage_Tracking__c> utList = FLSCheck.getInstance().upsertDML(upsertList);
                AIUsageTrackingController.upsertUsageTrackingDetails(utList,wrap.aiResponse.Time_Saved_Seconds__c);
            }
        }catch(Exception e){
            wrap.aiResponse.Status__c = AIConstants.RESP_STATUS_ERROR;
            wrap.aiResponse.Message__c = e.getMessage();
            if(String.isBlank(wrap.aiResponse.Message__c)){
                wrap.aiResponse.Message__c = AIConstants.AI_GENERAL_ERROR;
            }
        }

        wrap.aiResponse.AI_Callout_End_Time__c = System.now();  
        wrap.aiResponse = insertAIResponse(wrap.aiResponse, true); 

        if(wrap.aiResponse.Status__c == AIConstants.RESP_STATUS_PROCESSED){
            List<AI_Security_Audit_Detail__c> lstOfAuditDetails = AIPromptActionService.managePromptActions(wrap.aiResponse);
            if(lstOfAuditDetails != null && !lstOfAuditDetails.isEmpty()){
                Boolean isError = false;
                for(AI_Security_Audit_Detail__c detail : lstOfAuditDetails){
                    if(detail.Status__c == AIConstants.SECURITY_AUDIT_DETAIL_STATUS_ERRORED){
                        isError = true;
                        break;
                    }
                }
                if(isError){
                    wrap.aiResponse.Status__c = AIConstants.RESP_STATUS_ERROR;
                    wrap.aiResponse.Message__c = 'One or more Prompt Action failed, please contact your System Admin.';
                    wrap.aiResponse = insertAIResponse(wrap.aiResponse, true); 
                    return JSON.serialize(wrap);
                }
            }
        }
        return JSON.serialize(wrap);
    }
    public static AI_Response__c processResponsesFileRequest(String promptId, String recordId, String userInput, AI_Response__c response){
        AIResponsesApiCalloutUtility.ResponseApiWrapper wrap = new AIResponsesApiCalloutUtility.ResponseApiWrapper();
        AI_Prompt__c aiPrompt = AIPromptSelector.getAIPromptById(promptId);
        if(aiPrompt != null && aiPrompt.AI_Model_File_Processing__c != null){
            
            aiPrompt.Prompt_Command__c = preparePromptCommand(aiPrompt,'', recordId, true);
        
            response.Start_Date_Time__c = System.Now();
            response = getExtractedData(recordId, aiPrompt, null, response);
            response.AI_Callout_Start_Time__c = System.now();
            
            response.Record_Id__c = recordId;
            response.GPT_Config__c = aiPrompt.AI_Connection__r.Name;
            response.AI_Prompt__c = aiPrompt.Id;
            response.Prompt_Command__c = aiPrompt.Prompt_Command__c;
            response.Profiles__c = aiPrompt.Profiles__c;
            response.Prompt_Version__c = aiPrompt.Prompt_Version__c;
            response.How_It_Works__c = aiPrompt.How_It_Works__c;
            response.Status__c = AIConstants.RESP_STATUS_INPROGRESS;
            response.Message__c = '';
            
            wrap.recordId = recordId;
            wrap.aiModel = aiPrompt.AI_Model_File_Processing__r;
            wrap.promptCommand = aiPrompt.Prompt_Command__c + ' ' + userInput;
            wrap.extractedData = response.Data_PII_Removed__c;
            Set<String> minedContentVersionsIds = getMinedContentVersionIds(wrap.extractedData);
            if(Id.valueOf(recordId).getSObjectType() == ContentVersion.SObjectType){
                minedContentVersionsIds.add(recordId);
            }
            wrap.cdIds = minedContentVersionsIds;
            System.debug(minedContentVersionsIds);
            try{
                if(!minedContentVersionsIds.isEmpty()){
                    wrap = AIResponsesApiCalloutUtility.processFileRequest(wrap);
                    //response.Files_Id__c = String.join(wrap.uploadedFileIds, ', ');
                    response.Vector_Store_Id__c = wrap.vectorStoreId;
                }else{
                    response.Status__c = AIConstants.RESP_STATUS_ERROR;
                    response.Message__c = 'Either the files are missing or filter does not match.';
                    response.AI_Callout_End_Time__c = System.now();  
                    wrap.aiResponse = insertAIResponse(response, true); 
                    return wrap.aiResponse;
                }
            }catch(Exception e){
                response.Status__c = AIConstants.RESP_STATUS_ERROR;
                response.Message__c = e.getMessage();
                response.AI_Callout_End_Time__c = System.now(); 
                wrap.aiResponse = insertAIResponse(response, true); 
                return wrap.aiResponse;
            }
            wrap.aiResponse = response;
        }
        if(wrap.uploadedFileIds != null && !wrap.uploadedFileIds.isEmpty()){
            for(String fileId : wrap.uploadedFileIds){
                getAnalyzeResponsesResult(fileId,JSON.serialize(wrap));
            }
        }
        wrap = (AIResponsesApiCalloutUtility.ResponseApiWrapper) JSON.deserialize(getPromptResponse(JSON.serialize(wrap)), AIResponsesApiCalloutUtility.ResponseApiWrapper.class);
        return wrap.aiResponse;
    }
}