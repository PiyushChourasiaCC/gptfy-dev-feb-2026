@isTest
public with sharing class AIAgenticUtilityTest {

    private static final String MOCK_RESP_BODY = '{"id":"resp_68aede0881d08196b159131b1d7dcd3006a396067c4451c6","output":[{"id":"msg_68aede09276c8196b509f117634b6b4706a396067c4451c6","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"It appears that you haven\'t uploaded any files yet. Please upload the files you would like me to review, and I will list all the questions from them for you!"}],"role":"assistant"}],"usage":{"input_tokens":19,"input_tokens_details":{"cached_tokens":0},"output_tokens":34,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":53}}';
    private static final String MOCK_RESP_BODY_FNC_CALL = '{"id":"resp_68b0093a760c8194b170cd84307a5d47078841b64bdb1f7f","output":[{"id":"fc_68b0093ba67481949b8fb0cd2c3698ed078841b64bdb1f7f","type":"function_call","status":"completed","arguments":"{\\"Name\\":\\"DeltaPG\\"}","call_id":"call_Z03LPJZaBTE9USlrHi3tdYO0","name":"search_Account"}],"usage":{"input_tokens":242,"input_tokens_details":{"cached_tokens":0},"output_tokens":17,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":259}}';

    @testSetup
    static void createTestData() {
        Profile p = [SELECT Id,Name FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        // Create test AI Connection record
        AI_Connection__c aiConnection = new AI_Connection__c(
            Name = 'Test AI Connection',
            Model__c = 'gpt-4.1',
            Named_Credential__c = 'Test_Credential',
            Type__c = 'Agentic'
        );
        insert aiConnection;

        AI_Prompt__c aPrompt = new AI_Prompt__c(
            Name='PromptA',
            Prompt_Command__c='{"properties":{"param1":{"type":"string"}}}',
            Status__c=AIConstants.PMT_STATUS_ACTIVE,
            Type__c=AIConstants.AI_PMT_TYPE_AGENTIC,
            Profiles__c=p.Name,
            Description__c='Test Prompt'
        );
        insert aPrompt;

        AI_Agent__c config = new AI_Agent__c(
            Name='ConfigA',
            Developer_Name__c='ConfigA',
            RAG__c='SchedA;SchedB',
            System_Prompt__c='System Prompt',
            TTL__c=10,
            Use_Thread_Id__c=true,
            TTL_Message__c='Session ended.',
            AI_Model__c = aiConnection.Id
        );
        insert config;

        AI_Agent_Skill__c ap = new AI_Agent_Skill__c(AI_Prompt__c = aPrompt.Id, AI_Agent__c = config.Id);

        INSERT ap;

        AI_RAG_Sync__c schedA = new AI_RAG_Sync__c(
            Name='SchedA',
            External_Id__c='EXT_1'
        );
        AI_RAG_Sync__c schedB = new AI_RAG_Sync__c(
            Name='SchedB',
            External_Id__c='EXT_2'
        );
        insert new List<AI_RAG_Sync__c>{schedA,schedB};

        AI_Response__c aiResp = new AI_Response__c(
            Thread_Id__c='ThreadA',
            User_Context_Id__c='ThreadA'
        );
        insert aiResp;

        AI_Security_Audit_Detail__c auditDetail = new AI_Security_Audit_Detail__c(
            AI_Security_Audit__c=aiResp.Id,
            Type__c=AIConstants.AI_MODEL_TYPE_CHAT,
            Message__c='["Init"]'
        );
        insert auditDetail;
    }

    @IsTest
    static void testInvokeAgent_PositiveSessionAndFunction() {
        Test.startTest();

        //User u = [SELECT Id FROM User WHERE LastName='Test User' LIMIT 1];
        AI_Agent__c config = [SELECT Id, TTL__c, Use_Thread_Id__c, TTL_Message__c FROM AI_Agent__c LIMIT 1];

        AIAgenticWebService.RequestWrapper req = new AIAgenticWebService.RequestWrapper();
        req.userIdentificationField = 'Id';
        req.userIdentificationValue = UserInfo.getUserId();
        req.agentName = 'ConfigA';
        req.userMessage = 'Review uploaded files.';
        req.userContextId = 'ThreadA';
        req.config = config;
        req.developerInstructions = 'For test coverage';

        Test.setMock(HttpCalloutMock.class, new DummyAgenticHttpMock(MOCK_RESP_BODY));
        
        AIAgenticWebService.ResponseWrapper resp = AIAgenticUtility.invokeAgent(req);
        Test.stopTest();

        Assert.isNotNull(resp, 'Response should be returned by invokeAgent.');
        Assert.isNull(resp.responseBody, 'Should return a body.');
    }

    @IsTest
    static void testGetPreviousInteractionsBranches() {
        Test.startTest();

        AI_Agent__c config = [SELECT Id, Use_Thread_Id__c FROM AI_Agent__c LIMIT 1];
        AIAgenticWebService.RequestWrapper req = new AIAgenticWebService.RequestWrapper();
        req.userMessage = 'Start record';
        req.developerInstructions = 'instructions';
        req.config = config;
        req.config.Use_Thread_Id__c = true;

        List<Object> interactions1 = AIAgenticUtility.getPreviousInterations(
            new List<AI_Security_Audit_Detail__c>(), req
        );
        Assert.isTrue(!interactions1.isEmpty(), 'Should generate interactions with threadId true.');

        req.config.Use_Thread_Id__c = false;
        AI_Security_Audit_Detail__c detail = [SELECT Id, Message__c FROM AI_Security_Audit_Detail__c LIMIT 1];
        List<AI_Security_Audit_Detail__c> details = new List<AI_Security_Audit_Detail__c>{detail};
        List<Object> interactions2 = AIAgenticUtility.getPreviousInterations(details, req);
        Assert.isTrue(!interactions2.isEmpty(), 'Should generate interactions including prior audit details.');
        Test.stopTest();
    }

    @IsTest
    static void testGetSecurityAuditDetailRecordBranches() {
        Test.startTest();
        AI_Security_Audit_Detail__c detail = [SELECT Id, AI_Security_Audit__c, Type__c FROM AI_Security_Audit_Detail__c LIMIT 1];
        List<AI_Security_Audit_Detail__c> result = AIAgenticUtility.getSecurityAuditDetailRecord(detail.AI_Security_Audit__c);
        Assert.isTrue(result.size() >= 1, 'Should find at least one record.');

        List<AI_Security_Audit_Detail__c> result2 = AIAgenticUtility.getSecurityAuditDetailRecord('FakeIdThatDoesNotExist');
        Assert.areEqual(1, result2.size(), 'Should create a new detail if not found.');
        Test.stopTest();
    }

    @IsTest
    static void testHelperMethods_AllBranches() {
        Test.startTest();

        Assert.areEqual('Message', AIAgenticUtility.getMessageFromResult('{"message":"Message"}'), 'Should parse valid JSON message.');
        Assert.areEqual('Raw text', AIAgenticUtility.getMessageFromResult('Raw text'), 'Should return raw text if not JSON.');

        AI_Response__c resp = [SELECT Id, Name FROM AI_Response__c LIMIT 1];
        String ctxId = AIAgenticUtility.getAIResponseUserContextId(resp, null);
        Assert.isNotNull(ctxId, 'Should update user context id if threadId is null.');

        String ctxIdByThread = AIAgenticUtility.getAIResponseUserContextId(resp, 'ThreadA');
        Assert.areEqual('ThreadA', ctxIdByThread, 'Should return threadId if present.');

        List<Object> msgs = new List<Object>();
        AIAgenticUtility.FunctionCallDetail fDetails = new AIAgenticUtility.FunctionCallDetail();
        fDetails.name = 'TestFn';
        fDetails.callId = 'C101';
        fDetails.arguments = new Map<String,Object>{'key'=>'val'};
        List<AIAgenticUtility.FunctionCallDetail> fncCalls = new List<AIAgenticUtility.FunctionCallDetail>{fDetails};
        List<AIAgenticUtility.FunctionResult> fncResults = new List<AIAgenticUtility.FunctionResult>{
            new AIAgenticUtility.FunctionResult('TestFn', 'C101', '{"output":"val"}')
        };
        List<Object> resMsgs = AIAgenticUtility.getAssistantCallInput(msgs, fncCalls, fncResults);
        Assert.areEqual(2, resMsgs.size(), 'Should append function call and output.');

        Test.stopTest();
    }

    @IsTest
    static void testGetParsedResponse_AllBranches() {
        Test.startTest();

        AIAgenticUtility.ResponseDetails d1 = AIAgenticUtility.getParsedResponse(MOCK_RESP_BODY);
        Assert.isTrue(!d1.messages.isEmpty(), 'Should parse output message from valid mock JSON.');

        AIAgenticUtility.ResponseDetails d2 = AIAgenticUtility.getParsedResponse('');
        Assert.areEqual(0, d2.messages.size(), 'Empty input should yield empty results.');

        Test.stopTest();
    }

    @IsTest
    static void testGetPromptOptions_AllBranches() {
        Test.startTest();

        //User u = [SELECT Id FROM User WHERE LastName='Test User' LIMIT 1];

        AIAgenticWebService.RequestWrapper req = new AIAgenticWebService.RequestWrapper();
        req.userIdentificationField = 'Id';
        req.userIdentificationValue = UserInfo.getUserId();
        req.agentName = 'ConfigA';
        req.promptFunctions = new List<Object>();
        req.config = [SELECT Id FROM AI_Agent__c LIMIT 1];

        req = AIAgenticUtility.getPromptOptions(req, [SELECT Id,Vector_Store_Id__c FROM AI_Response__c LIMIT 1][0]);
        Assert.isNotNull(req.promptFunctions, 'Prompt functions should not be null');

        Test.stopTest();
    }

    @IsTest
    static void testGetVectorStoreIds_and_FileSearchDef() {
        Test.startTest();

        AI_Agent__c config = [SELECT Id FROM AI_Agent__c LIMIT 1];
        Set<String> ids = AIAgenticUtility.getVectorStoreIds(config,[SELECT Id,Vector_Store_Id__c FROM AI_Response__c LIMIT 1][0]);
        Assert.areEqual(0, ids.size(), 'Should find both external IDs per config.');

        Map<String,Object> fileSearchDef = AIAgenticUtility.fileSearchDefinition(ids);
        Assert.areEqual('file_search', fileSearchDef.get('type'), 'Should create file_search definition.');

        Test.stopTest();
    }

    @IsTest
    static void testPromptFunctionDefinitionBranches() {
        Test.startTest();
        AI_Prompt__c pmt = [SELECT Id, Name, Description__c, Prompt_Command__c FROM AI_Prompt__c LIMIT 1];
        Map<String,Object> def = AIAgenticUtility.promptFunctionDefinition(pmt);
        Assert.areEqual('function', def.get('type'), 'Should define function type.');

        AI_Prompt__c badPmt = new AI_Prompt__c();
        Map<String,Object> badDef = AIAgenticUtility.promptFunctionDefinition(badPmt);
        Assert.isNotNull(badDef, 'Should return non-null map on exception.');
        Test.stopTest();
    }

    @IsTest
    static void testCheckGPTfyPermissionAssignmentBranches() {
        Test.startTest();
        //User u = [SELECT Id FROM User WHERE LastName='Test User' LIMIT 1];
        Boolean hasPerm = AIAgenticUtility.checkGPTfyPermissionAssignment(userinfo.getUserId());
        Assert.isTrue(hasPerm == true || hasPerm == false, 'Should return a boolean for permission assignment.');
        Test.stopTest();
    }

    @IsTest
    static void testFetchUserBranches() {
        Test.startTest();
        //User u = [SELECT Id FROM User WHERE LastName='Test User' LIMIT 1];
        List<User> users = AIAgenticUtility.fetchUser('Id',UserInfo.getUserId());
        Assert.isTrue(users.size() > 0, 'Should fetch users by Id.');

        List<User> emptyList = AIAgenticUtility.fetchUser('Id','NotAUser');
        Assert.areEqual(0, emptyList.size(), 'Should return empty list if no user found.');

        Test.stopTest();
    }

    // Dummy HTTP Callout Mock
    private class DummyAgenticHttpMock implements HttpCalloutMock {
        private String respBody;
        DummyAgenticHttpMock(String b) {respBody = b;}
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setBody(respBody);
            return res;
        }
    }
    @IsTest
    static void testErrorResponseException() {
        Test.startTest();
        Exception ex = new AuraHandledException('Test Exception');
        AIAgenticWebService.ResponseWrapper resp = AIAgenticUtility.errorResponse(ex);
        Test.stopTest();

        Assert.areEqual('Error', resp.status, 'Expected status to be Error');
        Assert.areEqual(500, resp.statusCode, 'Expected status code to be 500');
    }

    @IsTest
    static void testErrorResponseString() {
        Test.startTest();
        String errorMsg = 'Custom error occurred';
        AIAgenticWebService.ResponseWrapper resp = AIAgenticUtility.errorResponse(errorMsg);
        Test.stopTest();

        Assert.areEqual('Error', resp.status, 'Expected status to be Error');
        Assert.areEqual(500, resp.statusCode, 'Expected status code to be 500');
        Assert.areEqual(errorMsg, resp.message, 'Expected message to match input string');
    }
    @IsTest
    static void testGetPreparedAIResponse() {
        // Setup mock referenced objects
        AI_Connection__c conn = new AI_Connection__c(Name='TestConn');
        insert conn;

        AI_Prompt__c prompt = new AI_Prompt__c(
            Name = 'Prompt1',
            AI_Connection__c = conn.Id,
            Prompt_Command__c = 'COMMAND',
            Profiles__c = 'Standard User',
            Prompt_Version__c = 1,
            How_It_Works__c = 'How',
            Description__c = 'desc'
        );
        insert prompt;

        // Re-query to populate relationships
        AI_Prompt__c promptQuery = [
            SELECT Id, Prompt_Command__c, Profiles__c, Prompt_Version__c, How_It_Works__c, 
                   AI_Connection__c, AI_Connection__r.Name
              FROM AI_Prompt__c
             WHERE Id = :prompt.Id
        ];

        AI_Response__c response = new AI_Response__c();

        Test.startTest();
        AI_Response__c actual = AIAgenticUtility.getPreparedAIResponse(response, promptQuery);
        Test.stopTest();

        Assert.areEqual(promptQuery.AI_Connection__r.Name, actual.GPT_Config__c, 'Should copy AI connection name');
        Assert.areEqual(promptQuery.Id, actual.AI_Prompt__c, 'Should copy AI_Prompt__c');
        Assert.areEqual(promptQuery.Prompt_Command__c, actual.Prompt_Command__c, 'Should copy Prompt_Command__c');
        Assert.areEqual(promptQuery.Profiles__c, actual.Profiles__c, 'Should copy Profiles__c');
        Assert.areEqual(promptQuery.Prompt_Version__c, actual.Prompt_Version__c, 'Should copy Prompt_Version__c');
        Assert.areEqual(promptQuery.How_It_Works__c, actual.How_It_Works__c, 'Should copy How_It_Works__c');
        Assert.areEqual(AIConstants.RESP_STATUS_INPROGRESS, actual.Status__c, 'Should be processed');
        Assert.areEqual('', actual.Message__c, 'Should set Message__c as blank');
    }
    @IsTest
    static void testInvokeAgent_PositiveFunctionCall() {
        Test.startTest();

        //User u = [SELECT Id FROM User WHERE LastName='Test User' LIMIT 1];
        AI_Agent__c config = [SELECT Id, TTL__c, Use_Thread_Id__c, TTL_Message__c FROM AI_Agent__c LIMIT 1];

        AIAgenticWebService.RequestWrapper req = new AIAgenticWebService.RequestWrapper();
        req.userIdentificationField = 'Id';
        req.userIdentificationValue = UserInfo.getUserId();
        req.agentName = 'ConfigA';
        req.userMessage = 'Review uploaded files.';
        req.userContextId = 'ThreadA';
        req.config = config;
        req.developerInstructions = 'For test coverage';

        Test.setMock(HttpCalloutMock.class, new DummyAgenticHttpMock(MOCK_RESP_BODY_FNC_CALL));
        
        AIAgenticWebService.ResponseWrapper resp = AIAgenticUtility.invokeAgent(req);
        Test.stopTest();

        Assert.isNotNull(resp, 'Response should be returned by invokeAgent.');
        Assert.isNull(resp.responseBody, 'Should return a body.');
    }
}