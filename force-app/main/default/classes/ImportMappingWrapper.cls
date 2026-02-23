/**
 * @description       : 
 * @author            : Adarsh Sharma
 * @group             : Plumcloud Labs
 * @last modified on  : 30-05-2025
 * @last modified by  : Adarsh Sharma
**/
public with sharing class ImportMappingWrapper {

    @AuraEnabled public Date exportedOn{get;set;}
    @AuraEnabled public String requestType{get;set;}
    @AuraEnabled public String orgId{get;set;}
    @AuraEnabled public String exportedBy{get;set;}
    @AuraEnabled public List<PromptWrapper> prompts{get;set;}
    @AuraEnabled public List<PromptWrapper> promptsVersion{get;set;}
    @AuraEnabled public List<CardConfigurationWrapper> catalogCards{get;set;}
    @AuraEnabled public List<ConnectionWrapper> connections{get;set;}
    @AuraEnabled public List<ExtractionWrapper> dataExtractionMappings{get;set;}
    @AuraEnabled public List<ExtractionSecurityFilterWrapper> securityFilters{get;set;}
    @AuraEnabled public List< DataSourceWrapper> dataSources{get;set;}
    //@Jira V2-7132
    public class PromptWrapper{
        @AuraEnabled public String salesforceId{get;set;}
        @AuraEnabled public String connectionId{get;set;}
        @AuraEnabled public String extractionMappingId{get;set;}
        @AuraEnabled public String promptName{get;set;}
        @AuraEnabled public String description{get;set;}
        @AuraEnabled public String objectName{get;set;}
        @AuraEnabled public String targetField{get;set;}
        @AuraEnabled public String profiles{get;set;}
        @AuraEnabled public String permissionSets{get;set;}
        @AuraEnabled public Decimal timeSavedCoefficient{get;set;}
        @AuraEnabled public String groundingEthical{get;set;}
        @AuraEnabled public String groundingContent{get;set;}
        @AuraEnabled public String localeAutomation{get;set;}
        @AuraEnabled public String localeGPTfyConsole{get;set;}
        @AuraEnabled public String promptCommand{get;set;}
        @AuraEnabled public String purpose{get;set;}
        @AuraEnabled public String recordTypes{get;set;}
        @AuraEnabled public String type{get;set;}
        @AuraEnabled public String connectionName{get;set;}
        @AuraEnabled public String extractionMappingName{get;set;}
        @AuraEnabled public String visibilityCondition{get;set;}
        @AuraEnabled public String promptRequestId{get;set;}
        @AuraEnabled public boolean appendTimestamp{get;set;}
        @AuraEnabled public boolean allowUserInput{get;set;}
        @AuraEnabled public boolean includeFiles{get;set;}
        @AuraEnabled public String howItWorks{get;set;}
        @AuraEnabled public Decimal promptVersion{get;set;}
        @AuraEnabled public Decimal topP{get;set;}
        @AuraEnabled public Decimal temperature{get;set;}
        @AuraEnabled public Decimal maxTokens{get;set;}
        @AuraEnabled public Integer autoRefreshDuration{get;set;}
        @AuraEnabled public Boolean enableLoopback{get;set;}
        @AuraEnabled public String loopbackMessage{get;set;}
        @AuraEnabled public String responseValidationCondition{get;set;}
        @AuraEnabled public String responseValidationMessage{get;set;}
        @AuraEnabled public String agenticFunctionClass{get;set;}
        @AuraEnabled public String aIModelFileProcessing{get;set;}
        @AuraEnabled public List<PromptComponentWrapper> promptComponents{get;set;}
        @AuraEnabled public List<PromptActionWrapper> promptActions{get;set;}
        @AuraEnabled public List<PromptElementWrapper> promptElements{get;set;}
        @AuraEnabled public List<PromptResponseValidationWrapper> promptResponseValidations{get;set;}
    }
    
    public class PromptComponentWrapper{
        @AuraEnabled public String salesforceId{get;set;}
        @AuraEnabled public String componentName{get;set;}
        @AuraEnabled public String actionName{get;set;}
        @AuraEnabled public String additionalInstructions{get;set;}
        @AuraEnabled public String constraintValue{get;set;}
        @AuraEnabled public String dataExtractionId{get;set;}
        @AuraEnabled public String format{get;set;}
        @AuraEnabled public String language{get;set;}
        @AuraEnabled public String length{get;set;}
        @AuraEnabled public String objectName{get;set;}
        @AuraEnabled public String tone{get;set;}
        @AuraEnabled public String userCustomizable{get;set;}
        @AuraEnabled public String phraseBeforeAction{get;set;}
        @AuraEnabled public String phraseAfterAction{get;set;}
        @AuraEnabled public String phraseBeforeContraints{get;set;}
        @AuraEnabled public String phraseAfterContraints{get;set;}
        @AuraEnabled public String phraseBeforeFormat{get;set;}
        @AuraEnabled public String phraseAfterFormat{get;set;}
        @AuraEnabled public String phraseBeforeLanguage{get;set;}
        @AuraEnabled public String phraseAfterLanguage{get;set;}
        @AuraEnabled public String phraseBeforeLength{get;set;}
        @AuraEnabled public String phraseAfterLength{get;set;}
        @AuraEnabled public String phraseBeforeObject{get;set;}
        @AuraEnabled public String phraseAfterObject{get;set;}
        @AuraEnabled public String phraseBeforeTone{get;set;}
        @AuraEnabled public String phraseAfterTone{get;set;}
        @AuraEnabled public List<ResponseProcessingWrapper> responseProcessings{get;set;}
    } 
    
    public class PromptActionWrapper{
        @AuraEnabled public String salesforceId{get;set;}
        @AuraEnabled public String actionType{get;set;}
        @AuraEnabled public String description{get;set;}
        @AuraEnabled public Decimal sequence{get;set;}
        @AuraEnabled public String objectName{get;set;}
        @AuraEnabled public String fieldAPIName{get;set;}
        @AuraEnabled public String flowAPIName{get;set;}
        @AuraEnabled public String apexClassName{get;set;}
        @AuraEnabled public Boolean appendTimestamp{get;set;}
        @AuraEnabled public String promptComponent{get;set;}
        @AuraEnabled public List<PromptActionDetailWrapper> promptActionDetails{get;set;}
    }
    
    public class PromptActionDetailWrapper{
        @AuraEnabled public String salesforceId{get;set;}
        @AuraEnabled public String fieldAPIName{get;set;}
        @AuraEnabled public String actionType{get;set;}
        @AuraEnabled public String value{get;set;}
    }
    
    public class ResponseProcessingWrapper{
        @AuraEnabled public String salesforceId{get;set;}
        @AuraEnabled public String actionName{get;set;}
        @AuraEnabled public String description{get;set;}
        @AuraEnabled public String destinationField{get;set;}
        @AuraEnabled public boolean appendTimestamp{get;set;}
    }
    //@Jira V2-7132
    public class ConnectionWrapper{
        @AuraEnabled public String salesforceId{get;set;}
        @AuraEnabled public String connectionName{get;set;}
        @AuraEnabled public String aiTechnology{get;set;}
        @AuraEnabled public String connectorClass{get;set;}
        @AuraEnabled public String processingClass{get;set;}
        @AuraEnabled public String endpointUrl{get;set;}
        @AuraEnabled public String key{get;set;}
        @AuraEnabled public Decimal maxTokens{get;set;}
        @AuraEnabled public String model{get;set;}
        @AuraEnabled public String namedCredential{get;set;}
        @AuraEnabled public String infrastructure{get;set;}
        @AuraEnabled public String securityLayer{get;set;}
        @AuraEnabled public Decimal temperature{get;set;}
        @AuraEnabled public Decimal topP{get;set;}
        @AuraEnabled public String version{get;set;}
        @AuraEnabled public Boolean active{get;set;}
        @AuraEnabled public CardConfigurationWrapper cardDetails{get;set;}
        // @Jira 7317: Global Import/Export Feedbacks
        @AuraEnabled public String type{get;set;}
    }
    
    public class ExtractionWrapper{
        @AuraEnabled public String salesforceId{get;set;}
        @AuraEnabled public String mappingName{get;set;}
        @AuraEnabled public String description{get;set;}
        @AuraEnabled public String objectName{get;set;}
        @AuraEnabled public String dataSourceId{get;set;}
        @AuraEnabled public String apexSecurityLayerId{get;set;}
        @AuraEnabled public List<ExtractionDetailWrapper> details{get;set;}
        @AuraEnabled public List<ExtractionFieldWrapper> fields{get;set;}
    }
    
    public class ExtractionDetailWrapper{
        @AuraEnabled public String salesforceId{get;set;}
        @AuraEnabled public String detailName{get;set;}
        @AuraEnabled public String objectHierarchy{get;set;}
        @AuraEnabled public String objectName{get;set;}
        @AuraEnabled public String orderBy{get;set;}
        @AuraEnabled public String parentDetailId{get;set;}
        @AuraEnabled public String relationshipField{get;set;}
        @AuraEnabled public String relationshipName{get;set;}
        @AuraEnabled public String type{get;set;}
        @AuraEnabled public String whereClause{get;set;}
        @AuraEnabled public Decimal recordLimit{get;set;}
        @AuraEnabled public Decimal runningIndex{get;set;}
    }
    
    public class ExtractionFieldWrapper{
        @AuraEnabled public String salesforceId{get;set;}
        @AuraEnabled public String fieldName{get;set;}
        @AuraEnabled public String fieldApi{get;set;}
        @AuraEnabled public String objectName{get;set;}
        @AuraEnabled public String type{get;set;}
        @AuraEnabled public String anonymizeWith{get;set;}
        @AuraEnabled public Boolean scanForPii{get;set;}
        @AuraEnabled public Boolean sendToAi{get;set;}
        @AuraEnabled public String maskingScope{get;set;}
        @AuraEnabled public String fieldType{get;set;}
        @AuraEnabled public String formula{get;set;}
    }
    
    public class ExtractionSecurityFilterWrapper{
        @AuraEnabled public String salesforceId{get;set;}
        @AuraEnabled public String filterName{get;set;}
        @AuraEnabled public String recordTypeName{get;set;}
        @AuraEnabled public String searchPattern{get;set;}
        @AuraEnabled public String status{get;set;}
        @AuraEnabled public String type{get;set;}
        @AuraEnabled public String blocklist{get;set;}
        @AuraEnabled public String comment{get;set;}
        @AuraEnabled public String apexClassName{get;set;}
    }
    
    public class DataSourceWrapper{
        @AuraEnabled public String salesforceId{get;set;}
        @AuraEnabled public String connectorClass{get;set;}
        @AuraEnabled public String name{get;set;}
        @AuraEnabled public String endpointUrl{get;set;}
        @AuraEnabled public String namedCredential{get;set;}
        @AuraEnabled public String source{get;set;}
        @AuraEnabled public CardConfigurationWrapper cardDetails{get;set;}
    }
    
    public class CardConfigurationWrapper{
        @AuraEnabled public String salesforceId{get;set;}
        @AuraEnabled public String configName{get;set;}
        @AuraEnabled public String description{get;set;}
        @AuraEnabled public String iconDetails{get;set;}
        @AuraEnabled public String iconSource{get;set;}
        @AuraEnabled public Integer sequence{get;set;}
        @AuraEnabled public String feature{get;set;}    
        @AuraEnabled public Boolean enabled{get;set;}
    }
    public class PromptElementWrapper{
        @AuraEnabled public String salesforceId{get;set;}
        @AuraEnabled public String parentPromptId{get;set;}
        @AuraEnabled public String parentPromptrequestId{get;set;}
        @AuraEnabled public String promptId{get;set;}
        @AuraEnabled public String promptRequestId{get;set;}
        @AuraEnabled public String summaryPromptId{get;set;}
        @AuraEnabled public String summaryPromptRequestId{get;set;}
        @AuraEnabled public String width{get;set;}
        @AuraEnabled public String icon{get;set;}
        @AuraEnabled public Decimal height{get;set;}
        @AuraEnabled public Integer sequence{get;set;}
        @AuraEnabled public Boolean inheritPromptSecurity{get;set;}
    }
    //@Jira V2-7132
    public class PromptResponseValidationWrapper{
        @AuraEnabled public String salesforceId{get;set;}
        @AuraEnabled public String promptId{get;set;}
        @AuraEnabled public String value{get;set;}
        @AuraEnabled public String action{get;set;}
        @AuraEnabled public Decimal sequence{get;set;}
    }
    
}