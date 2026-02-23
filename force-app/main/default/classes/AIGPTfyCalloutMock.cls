@isTest
private class AIGPTfyCalloutMock implements HttpCalloutMock {
    private String responseBody;
    private Integer statusCode;

    public AIGPTfyCalloutMock(String responseBody, Integer statusCode) {
        this.responseBody = responseBody;
        this.statusCode = statusCode;
    }

    public HTTPResponse respond(HTTPRequest request) {
        HttpResponse response = new HttpResponse();
        response.setBody(this.responseBody);
        response.setStatusCode(this.statusCode);
        return response;
    }
}