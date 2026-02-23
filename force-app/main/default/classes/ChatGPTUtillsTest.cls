/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
@isTest
private with sharing class ChatGPTUtillsTest{
    
    @testSetup
    static void makeData(){
        Account acc = new Account(Name = 'Test Account22');
        insert acc;
        Contentversion cv = TestUtility.getContentversion('Test', 'Test', 'Test', true);
        
        AI_Response_Mapping__c responseMapping = TestUtility.createResponseMapping('TestResponse',true);
        
        AI_Response_Mapping_Line__c oResponseMappingLine = new AI_Response_Mapping_Line__c();
        oResponseMappingLine.AI_Response_Mapping__c = responseMapping.Id;
        oResponseMappingLine.Security_Audit_Field_Name__c = 'Message__c';
        oResponseMappingLine.Mapping_Field_Name__c = 'Name';
        insert oResponseMappingLine;
        
        AI_Connection__c conn = TestUtility.getConnection('GPTfy', false);
        conn.AI_Response_Mapping__c = responseMapping.Id;
        insert conn;
        
        TestUtility.insertDataExtraction();
        
        AI_Data_Extraction_Mapping__c master = [SELECT Id FROM AI_Data_Extraction_Mapping__c LIMIT 1];
        
        AI_Prompt__c prompt = TestUtility.getAIPrompt('Test Prompt', 'Account', 'Active', false);
        prompt.Type__c = 'JSON';
        prompt.Prompt_Command__c = 'Give a sample response.';
        prompt.Grounding_Content__c = 'Only answer what has been asked for.';
        prompt.Grounding_Ethical__c = 'Do not hallucinate.';
        prompt.AI_Connection__c = conn.Id;
        prompt.AI_Data_Extraction_Mapping__c = master.Id;
        prompt.AI_Locale_GPTfy_Console__c = AIConstants.PMT_LOCALE_GPTFY_CONSOLE_COMPANY_DEFAULT;
        prompt.AI_Locale_Automation__c = AIConstants.PMT_LOCALE_AUTOMATION_RECORD_OWNER;
        insert prompt;
        /*String pmtId = AIPromptController.saveAIPrompt(new Map<String, Object>{
            'targetObject' => 'Account', 'aiConnection' => conn.Id, 'promptName' => 'Test Prompt', 'extractionMappingId' => master.Id,
            'selectedType' => 'JSON', 'promptCommand' => 'Give a sample response.', 'groundingContent' => 'Only answer what has been asked for.', 
            'groundingEthical' => 'Do not hallucinate.'
        }); */
        AI_Prompt_Component__c cmp1 = TestUtility.getPromptComponent(prompt.Id, master.Id, 'Account', true);
        update cmp1;
        
        AI_Data_Extraction_Detail__c cDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Contact' LIMIT 1];
        AI_Prompt_Component__c cmp2 = TestUtility.getPromptComponent(prompt.Id, cDetail.Id, 'Contact', true);
        
        AI_Data_Extraction_Detail__c gcDetail = [SELECT Id FROM AI_Data_Extraction_Detail__c WHERE Object_Name__c = 'Case' LIMIT 1];
        AI_Prompt_Component__c cmp3 = TestUtility.getPromptComponent(prompt.Id, gcDetail.Id, 'Case', true);
        AIJsonGeneration.generatePromptCommand(prompt.Id);
        
        AI_Scheduler__c sch = TestUtility.getScheduler('Test', 'Daily', '1;1', '0 00 11 ? * * *', Time.newInstance(3, 14, 15, 926), 1, true);
        AI_Prompt__c prompt2 = TestUtility.getAIPrompt('Test', 'Account', 'Active', false);
        prompt2.Prompt_Request_Id__c = 'test';
        insert prompt2;
        AI_Prompt_Scheduler__c promptScheduler = TestUtility.getAIPromptScheduler(prompt2.Id, sch.Id, true);
        AI_Scheduled_Run__c scheduledRun = TestUtility.getAIScheduledRun(sch.Id, true);
    }
    
    @isTest
    static void initiateGPTfyTest(){
        Account acc = new Account(Name = 'Test Account',description = 'ABC Name 1234');
        insert acc;
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c where name='Test Prompt' LIMIT 1];
        Test.startTest();
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "Response"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
		AI_Response__c resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, null, null,true);
        Test.stopTest();
        System.Assert(resp != null);
    }
    
    @isTest
    static void initiateChatGptTest(){
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        conn.AI_Technology__c = 'OpenAI_ChatGPT';
        update conn;
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        String respBody = '{"choices": [{"message" : {"content" : "Response"}}]}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
		AI_Response__c resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, null, null,false);
        Test.stopTest();
        System.Assert(resp != null);
    }
    
    @isTest
    static void initiateChatGptContactTest(){
        
        AI_Security_Filters__c sf = TestUtility.getAISecurityFilter('Post Code', AIDataExtractionService.RT_REGEX, true);
        AI_Security_Filters__c sf2 = TestUtility.getAISecurityFilter('Accounts', AIDataExtractionService.RT_BLOCKLIST, true);
        sf  = [Select id,Replacement_Value__c from AI_Security_Filters__c where id =:sf.Id ];
        
        Account acc = [Select Id from Account where Name='Test Account22' limit 1];
        Contact con = new Contact(FirstName = 'Test', LastName = 'Test', Email='test@test.com', Description = 'Test 1234', Phone='9876543210', AccountId=acc.Id);
        insert con;
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        conn.AI_Technology__c = 'OpenAI_ChatGPT';
        update conn;
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        
        AI_Prompt_Action__c action = TestUtility.getAIPromptAction(pmt.Id,AIConstants.ACTION_TYPE_UPDATE_FIELD, false);
        action.Field_API_Name__c = 'Name';
        action.Object_Name__c = 'Account';
        insert action;
        
        AI_Prompt_Action__c action2 = TestUtility.getAIPromptAction(pmt.Id,AIConstants.ACTION_TYPE_UPDATE_FIELD, false);
        action2.Field_API_Name__c = 'Owner.FirstName';
        action2.Object_Name__c = 'Account';
        insert action2;
        
        AI_Prompt_Action__c actionCreateRecord = TestUtility.getAIPromptAction(pmt.Id,AIConstants.ACTION_TYPE_CREATE_RECORD, false);
        actionCreateRecord.Object_Name__c = 'Account';
        insert actionCreateRecord;
        
        AI_Prompt_Action_Detail__c actionDetails = TestUtility.getAIPromptActionDetail(actionCreateRecord.Id,'Name',AIConstants.ACTION_DETAIL_TYPE_HARDCODED, false);
        actionDetails.Value__c = 'TestValue';
        insert actionDetails;
        
        actionDetails = TestUtility.getAIPromptActionDetail(actionCreateRecord.Id,'Name',AIConstants.ACTION_DETAIL_TYPE_AI_RESP, false);
        actionDetails.Value__c = 'TestValue';
        insert actionDetails;
        Test.startTest();
        	String respBody = '{"choices": [{"message" : {"content" : "Response '+sf.Replacement_Value__c+'-001"}}]}';
            Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
            AI_Response__c resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, null, null,true);
            resp.Record_Id__c = acc.Id;
            FLSCheck.getInstance().upsertDML(new List<AI_Response__c>{resp}).get(0);
        Test.stopTest();
        System.Assert(resp != null);
    }
    
    @isTest
    static void initiateCohereTest(){
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        conn.AI_Technology__c = 'Cohere_AI';
        update conn;
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        String wrapperJson = '{"id":"testId",  "generations": [{"text" : "Response"}]  }';
        Test.startTest();
        String respBody = '{ "output" : { "message": { "content" : [ { "text": '+JSON.serialize(wrapperJson)+' } ]  } } , "generations": [{"text" : "Response"}]}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
		AI_Response__c resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, null, null,true);
        Test.stopTest();
        System.Assert(resp != null);
    }
    
    @isTest
    static void initiateAWSBedrock() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        List<String> fields = Label.Longer_Fields.split(';');
        String title = 'Test';
        if(!fields.isEmpty() && fields.size() > 0){
            title = fields[0]+'Test';
        }
        Contentversion cv = TestUtility.getContentversion(title, 'Test', 'Test', false);
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion where Id = :cv.Id];
        
        
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        conn.AI_Technology__c = 'AnyAI_AnyPlatform';
        conn.Model__c = AIConstants.AWS_BEDROCK_MODEL;
        conn.EndPoint_URL__c = '/retrieveAndGenerate';

        update conn;

        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "Response"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';

        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        AI_Response__c resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, null, null,true);
        ContentDocumentLink cdLink = TestUtility.getContentDocumentLink(resp.Id,cv.ContentDocumentId,true);
		ChatGPTUtills.getDataUsingFiles(resp);
        ChatGPTUtills.insertAIResponse(resp,true);
        new AIApexSecurityLayerDataWrapper(resp,new Map<String,Boolean>{ 'test' => true});
        Test.stopTest();
        System.Assert(resp != null);
    }

    @isTest
    static void initiateAWSBedrockWrongEndPoint() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        conn.AI_Technology__c = 'AnyAI_AnyPlatform';
        conn.Model__c = AIConstants.AWS_BEDROCK_MODEL;
        //conn.EndPoint_URL__c = '/retrieveAndGenerate';

        update conn;

        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "Response"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';

        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        AI_Response__c resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, null, null,true);

        Test.stopTest();
        System.Assert(resp != null);
    }

    //AIConstants.AZURE_RAG_GPT_35_TURBO_MODEL

    @isTest
    static void initiateAZURE_RAG_GPT_35_TURBO_MODEL() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        conn.AI_Technology__c = 'AnyAI_AnyPlatform';
        conn.Model__c = AIConstants.AZURE_RAG_GPT_35_TURBO_MODEL;
        //conn.EndPoint_URL__c = '/retrieveAndGenerate';

        update conn;

        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "Response"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';

        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        AI_Response__c resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, null, null,true);
        Test.stopTest();
        System.Assert(resp != null);
    }

    @isTest
    static void initiateErrorTest(){
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        String respBody = '{"error": {"message" : "Response"}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        AI_Response__c resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, null, null,true);
        Test.stopTest();
        System.Assert(resp.Status__c == AIConstants.RESP_STATUS_ERROR);
    }

    @isTest
    static void processFileRequestTest(){
        Contentversion cv = TestUtility.getContentversion('Test', 'Test', 'Test', false);
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion where Id = :cv.Id]; 
		System.Assert(cv != NULL);

        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        conn.AI_Technology__c = AIConstants.PRODUCT_NAME;
        conn.Model__c = AIConstants.GPT_4o_MODEL;
        conn.Type__c = 'File';
        update conn;
        
        /*AI_Response__c resp = new AI_Response__c();
        resp.Start_Date_Time__c = System.Now();
        resp.Data_PII_Removed__c = '{"Account": [{ "Content Version": [{ "Id": "'+cv.Id+'"}] }] }';
        insert resp;*/
        
        Account acc = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c pmt = [SELECT Id,AI_Model_File_Processing__c FROM AI_Prompt__c where name='Test Prompt' LIMIT 1];
        pmt.AI_Model_File_Processing__c = conn.Id;
        update pmt;
        Test.startTest();
        String respBody = '{"generations": [{"text" : "Response"}], "Operation-Location": "testurl","id": "vcId", "status": "succeeded" }';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        ChatGPTUtills.FileResponseWrapper fresponse;
        Boolean isError = false;
        try{
            ChatGPTUtills.processResponsesFileRequest(pmt.Id,acc.Id,'Test',new List<String>{cv.ContentDocumentId});
            //ChatGPTUtills.processResponsesFileRequest(pmt.Id,acc.Id,'Test',resp);
            fresponse = ChatGPTUtills.processFileRequest(pmt.Id,acc.Id,'Test',new List<String>{cv.ContentDocumentId},'{}');
            conn.AI_Technology__c = 'AnyAI_AnyPlatform';
            update conn;
            fresponse = ChatGPTUtills.processFileRequest(pmt.Id,acc.Id,'Test',new List<String>{cv.ContentDocumentId},'{ "vectorStoreId": "vsId" }');
            conn.Model__c = AIConstants.TURBO_16K_MODEL;
            update conn;
            fresponse = ChatGPTUtills.processFileRequest(pmt.Id,acc.Id,'Test',new List<String>{cv.ContentDocumentId},'{ "vectorStoreId": "vsId" }');
            
        }catch(Exception e){
             isError = true;
        }
        Test.stopTest();
        System.Assert(fresponse.vectorStoreId == 'vsId');
    }

    @isTest
    static void processFileRequestErrorTest(){
        Contentversion cv = TestUtility.getContentversion('Test', 'Test', 'Test', false);
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion where Id = :cv.Id]; 
        
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        conn.AI_Technology__c = AIConstants.PRODUCT_NAME;
        conn.Model__c = AIConstants.GPT_4o_MODEL;
        conn.Type__c = 'File';
        //conn.EndPoint_URL__c = '/retrieveAndGenerate';

        update conn;

        Account acc = [SELECT Id FROM Account LIMIT 1];
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c where name='Test Prompt' LIMIT 1];
		pmt.AI_Model_File_Processing__c = conn.Id;
        update pmt;
        
        Test.startTest();
        String respBody = '{"error": {"innererror":{"message" : "Response"}}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Boolean isError = false;
        try{
            ChatGPTUtills.FileResponseWrapper fresponse = ChatGPTUtills.processFileRequest(pmt.Id,acc.Id,'Test',new List<String>{cv.ContentDocumentId},'{}');
        }catch(Exception e){
            isError = true;
        }
        Test.stopTest();
        System.Assert(isError);
    }

    @isTest
    static void getAnalyzeResultTest(){
        Contentversion cv = TestUtility.getContentversion('Test', 'Test', 'Test', false);
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion where Id = :cv.Id]; 
        System.Assert(cv != NULL);
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        conn.AI_Technology__c = 'AnyAI_AnyPlatform';
        conn.Model__c = AIConstants.GPT_4o_MODEL;
        conn.Type__c = 'File';
        update conn;
        
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c where name='Test Prompt' LIMIT 1];
		pmt.AI_Model_File_Processing__c = conn.Id;
        update pmt;
        
        AI_Response__c resp = new AI_Response__c();
        resp.Start_Date_Time__c = System.Now();
        insert resp;
        
        Test.startTest();
        String respBody = '{"generations": [{"text" : "Response"}]}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
        
        Boolean isError = false;
        ChatGPTUtills.FileResponseWrapper fresponse;
        try{
            fresponse = ChatGPTUtills.getAnalyzeResult(pmt.Id,'{ "runStatus": "completed", "aiResponseId": "'+resp.Id+'" }');
            conn.AI_Technology__c = AIConstants.PRODUCT_NAME;
            update conn;
            fresponse = ChatGPTUtills.getAnalyzeResult(pmt.Id,'{ "runStatus": "completed","mapOfCdIdToEndpointUrls":["'+cv.ContentDocumentId+'"], "aiResponseId": "'+resp.Id+'" }');
        }catch(Exception e){
            isError = true;
        }
        Test.stopTest(); 
        System.Assert(fresponse.runStatus == 'completed');
    }
    
    @isTest
    static void initiateGPTfyTurboTest(){
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        String respBody = '{"data": {"value" : {"choices" : [{"message" : {"content" : "test"}}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
		AI_Response__c resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, null, null,true);
        Test.stopTest();
        System.Assert(resp != null);
    }
    
    @isTest
    static void initiateGPTfyDavinciTest(){
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        AI_Connection__c con = [SELECT Id FROM AI_Connection__c LIMIT 1];
        con.Model__c = AIConstants.DAVINCI_MODEL;
        update con;
        
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "Response"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
		AI_Response__c resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, null, null,true);
        Test.stopTest();
        System.Assert(resp != null);
    }

    @isTest
    static void initiateGPTfyAWS_BEDROCK_MODELTest(){
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        AI_Connection__c con = [SELECT Id FROM AI_Connection__c LIMIT 1];
        con.Model__c = AIConstants.AWS_BEDROCK_MODEL;
        update con;
        
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        String respBody = '{"data": {"value" : {"choices" : [{"text" : "Response"}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
		AI_Response__c resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, null, null,true);
        Test.stopTest();
        System.Assert(resp != null);
    }
    
    @isTest
    static void initiateGPTfyGoogleAITest(){
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        AI_Connection__c con = [SELECT Id FROM AI_Connection__c LIMIT 1];
        con.Model__c = AIConstants.TEXT_BISON_001_MODEL;
        update con;
        
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        pmt.Max_Output_Tokens__c = 5000;
        pmt.Temperature__c = 1;
        pmt.Top_P__c = 1;
        update pmt;
        Test.startTest();
        String respBody = '{"data": {"predictions" : [{"content" : "test"}]}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
		AI_Response__c resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, null, null,true);
        Test.stopTest();
        System.Assert(resp != null);
    }
    
    @isTest
    static void initiateGptDavinciTest(){
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        conn.AI_Technology__c = 'OpenAI_ChatGPT';
        conn.Model__c = AIConstants.DAVINCI_MODEL;
        update conn;
        
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        String respBody = '{"text": "test"}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
		AI_Response__c resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, null, null,true);
        Test.stopTest();
        System.Assert(resp != null);
    }
    
    @isTest
    static void initiateGptXLargeTest(){
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        conn.AI_Technology__c = 'GPTfy';
        conn.Model__c = AIConstants.X_LARGE_MODEL;
        update conn;
        
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        String respBody = '{ "output" : [{ "type": "message", "content": [{ "text": "textValue" }] }]}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
		AI_Response__c resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, null, null,true);
        Test.stopTest();
        System.Assert(resp != null);
    }
    
    @isTest
    static void initiateAzureDavinciTest(){
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        conn.AI_Technology__c = 'OpenAI_Azure';
        conn.Model__c = AIConstants.DAVINCI_MODEL;
        update conn;
        
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        String respBody = '{"choices": [{"message" : {"content" : "Response"}}]}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
		AI_Response__c resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, null, null,true);
        Test.stopTest();
        System.Assert(resp != null);
    }
    
    @isTest
    static void initiateGoogleVertexTest(){
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        conn.AI_Technology__c = 'Google_Vertex';
        conn.Model__c = AIConstants.GCP_CHAT_BISON_MODEL;
        update conn;
        
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        String respBody = '{"predictions": [{"candidates" : [{"content" : "test"}]}], "metadata" : {"tokenMetadata" : {"inputTokenCount" : {"totalTokens" : 20, "promptTokens": 10}, "outputTokenCount" : {"outputTokenCount": 10, "totalTokens" : 20}}}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
		AI_Response__c resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, null, null,true);
        Test.stopTest();
        System.Assert(resp != null);
    }
    
    @isTest
    static void initiateGoogleDialogFlowTest(){
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        conn.AI_Technology__c = 'Google_Vertex';
        conn.Model__c = AIConstants.GCP_DIALOGFLOW_MODEL;
        update conn;
        
        AI_Prompt__c pmt = [SELECT Id FROM AI_Prompt__c LIMIT 1];
        Test.startTest();
        String respBody = '{"queryResult": {"responseMessages" : [{"text":{"text":["test"]}}, {"payload":{"richContent":[[{"actionLink":"test"}]]}}]}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
		AI_Response__c resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, null, null,true);
        ChatGPTUtills.checkLicensePlanActive('test');
        Test.stopTest();
        System.Assert(resp != null);
    }
    
    @isTest
    static void rollupAIResponseScheduledRunTest(){
        AI_Scheduled_Run__c scheduledRun = [SELECT Id FROM AI_Scheduled_Run__c LIMIT 1];
        AI_Response__c resp = new AI_Response__c();
        resp.Scheduled_Run__c = scheduledRun.Id;
        resp.Status__c = AIConstants.RESP_STATUS_PROCESSED;
        insert resp;
        Test.startTest();
          ChatGPTUtills.rollupAIResponseScheduledRun(scheduledRun.Id);
          resp.Status__c = AIConstants.RESP_STATUS_DISQ;
          update resp;
          ChatGPTUtills.rollupAIResponseScheduledRun(scheduledRun.Id);
          resp.Status__c = AIConstants.RESP_STATUS_ERROR;
          update resp;
          ChatGPTUtills.rollupAIResponseScheduledRun(scheduledRun.Id);
        Test.stopTest();
        System.Assert(scheduledRun!=null);
    }

	@isTest
    static void processResponsesFileRequestTest(){
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion cv = [SELECT Id, ContentDocumentId FROM ContentVersion limit 1];
        AI_Prompt__c pmt = [SELECT Id,AI_Data_Extraction_Mapping__c FROM AI_Prompt__c where Name = 'Test Prompt' LIMIT 1];
        AIDataExtractionController.upsertRelatedObjectMapping(new Map<String, String>{
            'selectedObject' => 'ContentVersion', 'selectedObjectLabel' => 'Content Version', 'masterId' => pmt.AI_Data_Extraction_Mapping__c , 'parentId' => '', 'detailId' => '',
            'parentObject' => 'Account', 'relationshipField' => 'FirstPublishLocationId', 'relationshipName' => 'Content Version'       
        });
        
        AIExtractionFieldMappingController.FieldWrapper cvField = new AIExtractionFieldMappingController.FieldWrapper();
        cvField.fieldName = 'FileType';
        cvField.label = 'FileType';
        cvField.sendToAI = true;
        cvField.scanForPII = true;
        cvField.fieldType = 'String';
        cvField.anonymizeWith = 'PersonFull{n}';
        cvField.selectedMaskingOption = 'Entire Value';
        AIExtractionFieldMappingController.saveFieldMappings(pmt.AI_Data_Extraction_Mapping__c, 'ContentVersion', new List<AIExtractionFieldMappingController.FieldWrapper>{cvField});
        
        AIExtractionFieldMappingController.FieldWrapper cvField2 = new AIExtractionFieldMappingController.FieldWrapper();
        cvField2.fieldName = 'Id';
        cvField2.label = 'Id';
        cvField2.sendToAI = true;
        cvField2.scanForPII = true;
        cvField2.fieldType = 'String';
        cvField.anonymizeWith = 'PersonFull{n}';
        cvField.selectedMaskingOption = 'Entire Value';
        AIExtractionFieldMappingController.saveFieldMappings(pmt.AI_Data_Extraction_Mapping__c, 'ContentVersion', new List<AIExtractionFieldMappingController.FieldWrapper>{cvField2});
        
        
        AI_Connection__c conn = [SELECT Id FROM AI_Connection__c LIMIT 1];
        conn.AI_Technology__c = AIConstants.PRODUCT_NAME;
        conn.Model__c = AIConstants.GPT_4o_MODEL;
        conn.Type__c = 'File';
        update conn;
        
        pmt.AI_Model_File_Processing__c = conn.Id;
        update pmt;
        
        ContentDocumentLink cdl = New ContentDocumentLink();
        cdl.LinkedEntityId = acc.id;
        cdl.ContentDocumentId = cv.ContentDocumentId;
        cdl.shareType = 'V';
        insert cdl;
        
        String respBody = '{ "id" : "fileId","status" : "complete", "data": {"value" : {"choices" : [{"message" : {"content" : "test"}}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody));
       	AI_Response__c resp = NULL;
        try{
            resp = ChatGPTUtills.initiateGPT(acc.Id, pmt.Id, 'Test', null,true);
        Test.startTest();
         
         //String respBody2 = '{ "id" : "fileId","status" : "complete", "data": {"value" : {"choices" : [{"message" : {"content" : "test"}}]}}, "usage" : {"completion_tokens" : 100, "prompt_tokens" : 100, "total_tokens" : 200}}';
        // Test.setMock(HttpCalloutMock.class, new AIMockCallout(respBody2));
		 ChatGPTUtills.processResponsesFileRequest(pmt.Id,acc.Id,'Test',resp);        
        Test.stopTest();
        }catch(Exception e){
            System.assert(e != NULL);
        }
        System.assert(resp != NULL);
    }    
}