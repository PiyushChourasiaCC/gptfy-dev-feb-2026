/**
* @description       : API Data Source that generates embeddings using Azure OpenAI. Takes extracted data, sends it to Azure OpenAI embedding API, and returns the data with vector embedding added.
* @author            : Sagar Alwani
* @group             : Plumcloud Labs
* @last modified on  : 12-29-2025
* @last modified by  : Sagar Alwani
* @Jira              : V2-7601
**/
global class EmbeddingDataSource implements AIDataSourceInterface {

    private static final String API_VERSION = '2025-03-01-preview';
    private static final String EMBEDDING_MODEL = 'text-embedding-ada-002';

    /**
     * Main method to fetch and process data with embedding generation.
     *
     * @param dataSource The AI Data Source configuration record
     * @param extractedData JSON string containing the data to process
     * @return JSON string with original data plus vector_text node
     */
    global String getExternalData(AI_Data_Source__c dataSource, String extractedData) {
        System.debug('EmbeddingDataSource - extractedData: ' + extractedData);
        System.debug('EmbeddingDataSource - dataSource: ' + dataSource);

        // Parse the incoming data
        Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(extractedData);

        // Convert the entire data to a string for embedding
        String textToEmbed = JSON.serialize(dataMap);

        // Get Named Credential from dataSource
        String namedCredential = dataSource.Named_Credential__c;

        // Generate embedding using Azure OpenAI
        List<Decimal> embedding = generateEmbedding(textToEmbed, namedCredential);

        // Add the vector embedding to the data
        dataMap.put('vector_text', embedding);

        // Remove fields specified in Custom Label
        removeIgnoredFields(dataMap);

        return JSON.serialize(dataMap);
    }

    /**
     * Generate embedding for text using Azure OpenAI REST API.
     *
     * @param text Text to generate embedding for
     * @param namedCredential Named Credential to use for the API call
     * @return List of Decimal representing the embedding vector
     */
    public List<Decimal> generateEmbedding(String text, String namedCredential) {
        // Build the endpoint using Named Credential from dataSource
        String endpoint = 'callout:' + namedCredential + '/openai/deployments/' + EMBEDDING_MODEL +
            '/embeddings?api-version=' + API_VERSION;
        System.debug('Endpoint@@: ' + endpoint);

        // Prepare the request payload
        Map<String, Object> payload = new Map<String, Object>{
            'input' => text
        };

        // Create and configure the HTTP request
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(120000); // 2 minute timeout

        // Send the request
        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug('EmbeddingDataSource - Response Status: ' + res.getStatusCode());
        System.debug('EmbeddingDataSource - Response Body: ' + res.getBody());

        if (res.getStatusCode() != 200) {
            String errorMessage = 'Embedding API error: ' + res.getStatusCode() + ' - ' + res.getBody();
            System.debug(errorMessage);
            throw new EmbeddingException(errorMessage);
        }

        // Parse the response
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> dataList = (List<Object>) result.get('data');

        if (dataList == null || dataList.isEmpty()) {
            throw new EmbeddingException('No embedding data returned from Azure OpenAI');
        }

        // Extract the embedding vector
        Map<String, Object> firstData = (Map<String, Object>) dataList[0];
        List<Object> embeddingList = (List<Object>) firstData.get('embedding');

        // Convert to List<Decimal>
        List<Decimal> embedding = new List<Decimal>();
        for (Object val : embeddingList) {
            embedding.add((Decimal) val);
        }

        System.debug('EmbeddingDataSource - Generated embedding with ' + embedding.size() + ' dimensions');

        return embedding;
    }

    /**
     * Removes fields from the data map based on the Custom Label configuration.
     * The Custom Label 'Embedding_Fields_To_Ignore' should contain comma-separated field names.
     *
     * @param dataMap The data map to remove fields from
     */
    private void removeIgnoredFields(Map<String, Object> dataMap) {
        String fieldsToIgnore = System.Label.Embedding_Fields_To_Ignore;

        if (String.isBlank(fieldsToIgnore)) {
            return;
        }

        List<String> fieldList = fieldsToIgnore.split(',');
        for (String field : fieldList) {
            String trimmedField = field.trim();
            if (dataMap.containsKey(trimmedField)) {
                dataMap.remove(trimmedField);
                System.debug('EmbeddingDataSource - Removed field: ' + trimmedField);
            }
        }
    }

    /**
     * Custom exception for embedding errors.
     */
    public class EmbeddingException extends Exception {}
}