/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
public with sharing class AIConstants {
	
    public static final String ORG_TYPE_SB = 'Sandbox';
    public static final String ORG_TYPE_PROD = 'Production';
    
    public static final String PRODUCT_NAME = 'GPTfy';
   	public static final String PRODUCT_UNIQ_ENDPOINT = '?code=dgTt417hXkH5162S1dvV_24L_TcsmqBUTYlCwWFrPlZQAzFus9FF1Q==';//'?code=PWtstj8CwAi-_er0frh9RUGMwWfOqibAecRhiErMuBV2AzFucW_q3w==';
    
    public static final String RESP_STATUS_DRAFT = 'Draft';
    public static final String RESP_STATUS_ERROR = 'Errored';
    public static final String RESP_STATUS_PROCESSED = 'Processed';
    public static final String RESP_STATUS_INPROGRESS = 'In Progress';
    public static final String RESP_STATUS_DATA_EXT = 'Data Extracted';
    public static final String RESP_STATUS_DISQ = 'Disqualified';
    
    public static final String SCH_STATUS_SCHEDULED = 'Scheduled';
    public static final String SCH_STATUS_NOT_SCHEDULED = 'Not Scheduled';
    public static final String SCH_STATUS_CANCELLED = 'Cancelled';

    public static final String SCH_STATUS_ABORTED = 'Aborted';
    public static final String SCH_STATUS_COMPLETED = 'Completed';
    public static final Set<String> SCH_BATCH_CLASSES = new Set<String>{'AIPromptScheduler', 'AIPromptCountRequestBatch', 'AIPromptRequestBatch', 'AIPromptDataExtractionBatch', 'AIPromptProcessingBatch','AIPromptRetryBatch'};
    
    public static final String SCH_FREQ_CUSTOM = 'Custom';
    public static final String SCH_FREQ_HOURLY = 'Hourly';
    public static final String SCH_FREQ_DAILY = 'Daily';
    public static final String SCH_FREQ_WEEKLY = 'Weekly';
    public static final String SCH_FREQ_MONTHLY = 'Monthly';
    
    public static final String REQUEST_FAILED = 'Request Failed. Please try again.';
    public static final String INCORRECT_JSON = 'Incorrect JSON.';
    public static final String PMT_REQ_ID_NOT_FOUND = 'Prompt Request Id missing.';
    public static final String REC_ID_NOT_FOUND = 'Record Id missing.';
    public static final String REC_ID_DOES_NOT_EXISTS = 'Record with the RecordId does not exists or you do not have permissions to it.';
    public static final String INCORRECT_REC_ID = 'Incorrect Record Id.';
    public static final String NO_ACTIVE_PMT_FOUND = 'No Active Prompt found.';
    public static final String EMPTY_REQ_BODY = 'Request Body is Empty.';
    public static final String AI_BLANK_RESPONSE = 'AI returned a blank response, please try again.';
    public static final String AI_GENERAL_ERROR = 'An error occured, please contact your System Admin.';
    
    public static final String DAVINCI_MODEL = 'text-davinci-003';
    public static final String TURBO_16K_MODEL = 'gpt-35-turbo-16k';
    public static final String TEXT_BISON_001_MODEL = 'text-bison-001';
    public static final String X_LARGE_MODEL = 'xlarge';
    public static final String GCP_CHAT_BISON_MODEL = 'chat-bison';
    public static final String GCP_DIALOGFLOW_MODEL = 'dialogflow';
    public static final String AWS_BEDROCK_MODEL = 'anthropic.claude-v2';
    public static final String AZURE_RAG_GPT_35_TURBO_MODEL = 'gpt-35-turbo';
    public static final String GCP_CHIP_MODEL = 'Chirp';
    public static final String KENSHO_VOICE_MODEL = 'Kensho';
    public static final String WHISPER_VOICE_MODEL = 'whisper';
    public static final String GPT_4o_MODEL = 'gpt-4o';
    public static final Set<String> RESPONSES_API_MODEL = new Set<String>{'gpt-4o', 'gpt-4.1', 'gpt-5', 'gpt-5.1'};
        
    public static final String GCP_FILE_UPLOAD = 'GCP Storage';    
    public static final String GCP_DISCOVERY_ENGINE = 'GCP Discovery Engine';
    
    // Azure AI Search direct index upload (no blob storage needed)
    public static final String AZURE_AI_SEARCH_DIRECT = 'Azure Search';

	public static final String SYNC_JOB_STATUS_IN_PROGRESS = 'In Progress';  
    public static final String SYNC_JOB_STATUS_COMPLETE = 'Completed'; 
    public static final String SYNC_JOB_STATUS_ERRORED = 'Errored';  
    
    public static final String DATA_CONTEXT_STATUS_ACTIVE = 'Active';
    public static final String DATA_CONTEXT_STATUS_DRAFT = 'Draft';
    
    public static final String PMT_STATUS_ACTIVE = 'Active';
    public static final String PMT_STATUS_IACTIVE = 'Inactive';
    public static final String PMT_STATUS_DRAFT = 'Draft';
    
    public static final String SEC_LAYER_STATUS_ACTIVE = 'Active';
    
    public static final String SEC_LAYER_REC_TYPE_APEX = 'Apex';
    
    public static final String APPLICATION_NAME = 'GPTfy';
    public static final String GPTFY_CARD_CONFIGURATION_MDT_AMODL = 'AMODL';
    public static final String GPTFY_CARD_CONFIGURATION_MDT_APIDS = 'APIDS';
    public static final String GPTFY_CARD_CONFIGURATION_MDT_CTLOG = 'CTLOG';
    
    public static final String GPTFY_ADMIN_PERM_SET = 'SGPT_Admin';
    public static final String GPTFY_USER_PERM_SET = 'SGPT_User';
    public static final String GPTFY_PORTAL_PERM_SET = 'SGPT_Portal_User';
    public static final String GPTFY_VOICE_PERM_SET = 'SGPT_Voice';
     
    public static final String RETENTION_JOB_NAME = 'AI Retention Scheduler';
    public static final String PMT_LOCALE_GPTFY_CONSOLE_COMPANY_DEFAULT = 'Company Default';
    public static final String PMT_LOCALE_GPTFY_CONSOLE_ACTIVE_USER = 'Active User';
    public static final String PMT_LOCALE_AUTOMATION_RECORD_OWNER = 'Record Owner';
    
    public static final String UT_RECTYPE_USER = 'User';
    public static final String UT_RECTYPE_PROFILE = 'Profile';
    public static final String UT_RECTYPE_PROMPT = 'Prompt';
    public static final String UT_RECTYPE_OBJECT = 'Object';
    public static final String UT_RECTYPE_USER_ROLE = 'User_Role';
    public static final String UT_RECTYPE_DEPT = 'Department';
    
    public static final String FIELD_TYPE_NUMBER = 'Number';
    
    public static final String AI_PMT_TYPE_AGENTIC = 'Agentic';
    public static final String AI_PMT_TYPE_CANVAS = 'Canvas';
    
    public static final String AI_MODEL_TYPE_CHAT = 'Chat';
    public static final String AI_MODEL_TYPE_VOICE = 'Voice';
    public static final String AI_MODEL_TYPE_AGENTIC = 'Agentic';
    public static final String AI_MODEL_TYPE_AI_SYNC = 'RAG Sync';
    
    public static final String ACTION_TYPE_UPDATE_FIELD = 'Update Field';
    public static final String ACTION_TYPE_CREATE_RECORD = 'Create Record';
    public static final String ACTION_TYPE_INVOKE_FLOW = 'Invoke Flow';
    public static final String ACTION_TYPE_INVOKE_APEX = 'Invoke Apex';
    public static final String ACTION_TYPE_OPEN_FORM = 'Open a Form';
    
    public static final String ACTION_DETAIL_TYPE_HARDCODED = 'Hardcoded';
    public static final String ACTION_DETAIL_TYPE_REF_FIELD = 'Reference Field';
    public static final String ACTION_DETAIL_TYPE_AI_RESP = 'AI Response';
    public static final String ACTION_DETAIL_TYPE_AI_EXTRACTED = 'AI Extracted';
    
    public static final String SECURITY_AUDIT_DETAIL_TYPE_PROMPT_ACTION = 'Prompt Action';
    public static final String SECURITY_AUDIT_DETAIL_TYPE_POLLING = 'Polling';
    
    public static final String SECURITY_AUDIT_DETAIL_STATUS_COMPLETED = 'Completed';
    public static final String SECURITY_AUDIT_DETAIL_STATUS_ERRORED = 'Errored';
    
    public static final String PROMPT_VALIDATION_ACTION_INCLUDE = 'Includes';
    public static final String PROMPT_VALIDATION_ACTION_EXCLUDE = 'Excludes';
    public static final String PROMPT_VALIDATION_ACTION_APEX = 'Apex';
    
    public static final String NAMESPACE = AIPromptController.getNameSpace();
    
    // Workspace Sync Notification Type (Custom Notification Types do NOT use namespace prefix)
    public static final String WORKSPACE_SYNC_NOTIFICATION_TYPE = 'AI_Workspace_Sync_Notification';
    
    public static final String CONTENT_VERSION_OBJECT_API = 'ContentVersion';
    public static final String CONTENT_VERSION_OBJECT_LABEL = 'Content Version';
    public static final String CDL_OBJECT_API = 'ContentDocumentLink';
    public static final String CDL_LINKED_ENTITY_FIELD_API = 'LinkedEntityId';
    public static final Set<String> EXTRACTION_OBJECTS_TO_SKIP = new Set<String>{
        'ContentDocumentLink', 'ContentVersion'
    };
    public static final String RESPONSES_API_INSTRUCTION = 'You are a helpful assistant. Retrieve the relevant answer from the vector store files based on the user query. Always prioritize the content of your most recent assistant response. When the user asks to “summarize it” or uses similar pronouns, assume they refer to that response first. Consult the uploaded records only if no prior answer exists or the user explicitly requests a fresh analysis of the records. If the records conflict with the last response, keep the response’s view and note the conflict.';

    public static Boolean enablePromptVersioning{
        get{
            Map<String, Object> maps = AIUtility.getCustomSettings();
            if(maps != null && maps.containsKey('enablePromptVersion') && maps.get('enablePromptVersion') != null && Boolean.valueOf(maps.get('enablePromptVersion'))){
                return true; 
            }
            return false;
        }
    }
    
    public static Boolean enableExceptionLog{
        get{
            Map<String, Object> maps = AIUtility.getCustomSettings();
            if(maps != null && maps.containsKey('enableExceptionLog') && maps.get('enableExceptionLog') != null && Boolean.valueOf(maps.get('enableExceptionLog'))){
                return true; 
            }
            return false;
        }
    }
    
    public static List<String> longerFields{
        get{
            List<String> fields = Label.Longer_Fields.split(';');
            List<String> formattedFields = new List<String>();
            for(String fName : fields){
                formattedFields.add(NAMESPACE+fName);
            }
            return formattedFields;
        }
    }
}