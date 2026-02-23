global class SnowfakeryRAGDataSource implements AIDataSourceInterface {
    // Entry method to process data and call the Snowflake API
    global String getExternalData(AI_Data_Source__c dataSource, String extractedData) {
        // Deserialize the extractedData JSON to extract the Case Description
        System.debug('Extracted Data: ' + extractedData);
        Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(extractedData);
        String caseDescription = (String) dataMap.get('Description'); // Case Description is the question

        // Validate that Description (question) is present
        if (String.isEmpty(caseDescription)) {
            throw new IllegalArgumentException('Case Description (question) cannot be null or empty.');
        }

        // Use Case Description as the question for the Snowflake API
        String apiResponse = callSnowflakeAPI(caseDescription);

        // Add the API response directly to the map
        dataMap.put('SnowflakeResponse', apiResponse);

        // Serialize and return the updated map
        return JSON.serialize(dataMap);
    }

    // Helper method to call the Snowflake API
    public static String callSnowflakeAPI(String question) {
        // Named Credential and API Endpoint
        String namedCredential = 'SnowflakeRAG'; // Replace with your Named Credential name
        String apiEndpoint = '/CC_QUICKSTART_CORTEX_DOCS/schemas/DATA/cortex-search-services/SagarSearchService:query';

        // Construct the request body
        Map<String, Object> requestBody = new Map<String, Object>{
            'query' => question,
            'columns' => new List<String>{'chunk', 'relative_path'},
            'limit' => 5
        };

        // HTTP Callout
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:' + namedCredential + apiEndpoint);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Accept', 'application/json');
        request.setBody(JSON.serialize(requestBody));

        try {
            HttpResponse response = http.send(request);

            // Return the API response if successful
            if (response.getStatusCode() == 200) {
                System.debug('Snowflake API Response: ' + response.getBody());
                return response.getBody(); // Return the raw API response
            } else {
                // Handle errors with appropriate debugging
                String errorMessage = 'Error calling Snowflake API: HTTP ' + response.getStatusCode() + ' - ' + response.getBody();
                System.debug(errorMessage);
                throw new CalloutException(errorMessage);
            }
        } catch (Exception e) {
            System.debug('Exception during Snowflake API call: ' + e.getMessage());
            throw e;
        }
    }
}