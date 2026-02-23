global class SimilarDealFinderDataSource implements AIDataSourceInterface {

    private static final String API_VERSION = '2025-03-01-preview';
    private static final String EMBEDDING_MODEL = 'text-embedding-ada-002';
    private static final String DEFAULT_NAMED_CREDENTIAL = 'Azure_OpenAI';

    private static final String SEARCH_API_VERSION = '2023-11-01';
    private static final String SEARCH_INDEX_NAME = 'snpindex';
    private static final String SEARCH_NAMED_CREDENTIAL = 'Azure_AI_Search';

    private static final String DATA_EXTRACTION_PROMPT_ID = 'a05J7000005nrqyIAA';

    private static final Boolean USE_SALESFORCE_DCM = false;

    global String getExternalData(AI_Data_Source__c dataSource, String extractedData) {
        Map<String, Object> inputData = (Map<String, Object>) JSON.deserializeUntyped(extractedData);
        String opportunityId = (String) inputData.get('Id');
        System.debug('Extracted Data: ' + extractedData);
        System.debug('Data Source: ' + dataSource);
        String apiDataSourceId = dataSource.Id;

        Map<String, Object> resultMap = new Map<String, Object>();

        Map<String, Object> benchmarks = getBenchmarksFromAttachment(apiDataSourceId);
        resultMap.put('benchmarks', benchmarks);

        Map<String, Object> cleanedData;
        if (USE_SALESFORCE_DCM) {
            Map<String, Object> dataContextMapping = getDataContextMapping(opportunityId);
            cleanedData = cleanDataForEmbedding(dataContextMapping);
        } else {
            cleanedData = getFakeDCMForAzureIndex();
        }

        String namedCredential = DEFAULT_NAMED_CREDENTIAL;
        List<Decimal> embedding = generateEmbedding(JSON.serialize(cleanedData), namedCredential);

        Set<String> dcmFields = cleanedData.keySet();

        List<Map<String, Object>> closedWonDeals = searchSimilarDeals(
            embedding,
            'won',
            dcmFields
        );
        resultMap.put('closedWonOpportunities', closedWonDeals);

        List<Map<String, Object>> closedLostDeals = searchSimilarDeals(
            embedding,
            'lost',
            dcmFields
        );
        resultMap.put('closedLostOpportunities', closedLostDeals);

        return JSON.serialize(resultMap);
    }

    private Map<String, Object> getBenchmarksFromAttachment(String apiDataSourceId) {
        if (String.isBlank(apiDataSourceId)) {
            return new Map<String, Object>();
        }

        List<AI_Prompt__c> prompts = [
           SELECT Id, Name
            FROM AI_Prompt__c
            WHERE AI_Data_Extraction_Mapping__c IN (
                SELECT Id
                FROM AI_Data_Extraction_Mapping__c
                WHERE AI_Data_Source__c = :apiDataSourceId
                )

        ];

        if (prompts.isEmpty()) {
            return new Map<String, Object>();
        }

        Set<Id> promptIds = new Set<Id>();
        for (AI_Prompt__c prompt : prompts) {
            promptIds.add(prompt.Id);
        }
            List<ContentDocumentLink> docLinks = [
                SELECT ContentDocumentId, LinkedEntityId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :promptIds
            ];
            System.debug('ContentDocumentLinks@@: ' + docLinks);
            if (!docLinks.isEmpty()) {
                Set<Id> contentDocIds = new Set<Id>();
                for (ContentDocumentLink link : docLinks) {
                    contentDocIds.add(link.ContentDocumentId);
                }
                System.debug('ContentDocumentIds@@: ' + contentDocIds);
                List<ContentVersion> versions = [
                    SELECT Id, Title, VersionData
                    FROM ContentVersion
                    WHERE ContentDocumentId IN :contentDocIds
                    AND Title LIKE '%benchmarks%'
                    AND IsLatest = true
                    LIMIT 1
                ];

                if (!versions.isEmpty()) {
                    String jsonContent = versions[0].VersionData.toString();
                    return (Map<String, Object>) JSON.deserializeUntyped(jsonContent);
                }
            }

            return new Map<String, Object>();
    }

    private Map<String, Object> getDataContextMapping(String opportunityId) {
        AI_Response__c aiResponse = AIGlobalUtility.getExtractedData(opportunityId, DATA_EXTRACTION_PROMPT_ID);

        if (aiResponse == null || String.isBlank(aiResponse.Extracted_Data__c)) {
            return new Map<String, Object>();
        }

        return (Map<String, Object>) JSON.deserializeUntyped(aiResponse.Extracted_Data__c);
    }

    private Map<String, Object> cleanDataForEmbedding(Map<String, Object> dataContextMapping) {
        Map<String, Object> cleanedData = dataContextMapping.clone();

        cleanedData.remove('Object Name');
        cleanedData.remove('Id');
        return cleanedData;
    }

    private Map<String, Object> getFakeDCMForAzureIndex() {
        Map<String, Object> fakeDCM = new Map<String, Object>();

        fakeDCM.put('OpportunityName', 'Sample Opportunity');
        fakeDCM.put('AccountName', 'Sample Account');
        fakeDCM.put('OwnerFullName', 'John Doe');
        fakeDCM.put('OpportunityType', 'New Business');
        fakeDCM.put('Industry', 'Technology');
        fakeDCM.put('BusinessDivision', 'Enterprise');
        fakeDCM.put('DealSize', 'Large');
        fakeDCM.put('AccountTier', 'Tier 1');
        fakeDCM.put('CompetitivePosition', 'Strong');
        fakeDCM.put('DealStage', 'Negotiation');
        fakeDCM.put('LossReason', '');
        fakeDCM.put('EmbeddingContent', 'Sample embedding content for similarity search');

        fakeDCM.put('AnnualContractValue', 100000.00);
        fakeDCM.put('TotalContractValue', 500000.00);

        fakeDCM.put('DaysInPipeline', 45);
        fakeDCM.put('MeetingCount', 5);
        fakeDCM.put('EmailCount', 20);
        fakeDCM.put('CallCount', 10);
        fakeDCM.put('EngagementScore', 75);
        fakeDCM.put('OpportunityScore', 80);

        fakeDCM.put('CloseDate', String.valueOf(Date.today().addDays(30)));

        fakeDCM.put('DemoCompleted', true);
        fakeDCM.put('POCCompleted', false);
        fakeDCM.put('ProposalSent', true);
        fakeDCM.put('BudgetConfirmed', true);
        fakeDCM.put('DecisionMakerEngaged', true);

        return fakeDCM;
    }

    private List<Decimal> generateEmbedding(String text, String namedCredential) {
        String endpoint = 'callout:' + namedCredential + '/openai/deployments/' + EMBEDDING_MODEL +
            '/embeddings?api-version=' + API_VERSION;

        Map<String, Object> payload = new Map<String, Object>{
            'input' => text
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(120000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new SimilarDealFinderException('Embedding API error: ' + res.getStatusCode() + ' - ' + res.getBody());
        }

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> dataList = (List<Object>) result.get('data');

        if (dataList == null || dataList.isEmpty()) {
            throw new SimilarDealFinderException('No embedding data returned from Azure OpenAI');
        }

        Map<String, Object> firstData = (Map<String, Object>) dataList[0];
        List<Object> embeddingList = (List<Object>) firstData.get('embedding');

        List<Decimal> embedding = new List<Decimal>();
        for (Object val : embeddingList) {
            embedding.add((Decimal) val);
        }

        return embedding;
    }

    private List<Map<String, Object>> searchSimilarDeals(
        List<Decimal> embedding,
        String dealStage,
        Set<String> selectFields
    ) {
        String endpoint = 'callout:' + SEARCH_NAMED_CREDENTIAL + '/indexes/' + SEARCH_INDEX_NAME + '/docs/search?api-version=' + SEARCH_API_VERSION;

        String selectClause = String.join(new List<String>(selectFields), ', ');

        Map<String, Object> searchPayload = new Map<String, Object>{
            'count' => true,
            'top' => 10,
            'select' => selectClause,
            'filter' => 'DealStage eq \'' + dealStage + '\'',
            'vectorQueries' => new List<Object>{
                new Map<String, Object>{
                    'kind' => 'vector',
                    'vector' => embedding,
                    'fields' => 'ContentVector',
                    'k' => 10
                }
            }
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(searchPayload));
        req.setTimeout(120000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new SimilarDealFinderException('Azure Search API error: ' + res.getStatusCode() + ' - ' + res.getBody());
        }

        Map<String, Object> searchResult = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> valueList = (List<Object>) searchResult.get('value');

        List<Map<String, Object>> deals = new List<Map<String, Object>>();
        if (valueList != null) {
            for (Object item : valueList) {
                deals.add((Map<String, Object>) item);
            }
        }

        return deals;
    }

    public class SimilarDealFinderException extends Exception {}
}