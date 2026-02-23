/**
* @description       : 
* @author            : Rishabh Goel
* @group             : Plumcloud Labs
* @last modified on  : 03-28-2023
* @last modified by  : Rishabh Goel
**/
@isTest
public class AIMockCallout implements HttpCalloutMock {
    protected String body;
    
    /**
     * Constructs an instance of AIMockCallout with the provided body.
     *
     * @param body The body content to be associated with the AIMockCallout.
     *             This could represent data or content needed for the callout.
     */
    public AIMockCallout(String body) {
        this.body = body;
    }
    
    /**
     * Responds to an HTTP request.
     *
     * This method takes an HTTPRequest object as a parameter and generates
     * an appropriate HTTPResponse based on the request. The response is
     * encapsulated in an HTTPResponse object, which includes information
     * such as the response status code, headers, and content.
     *
     * @param req The HTTPRequest object representing the incoming request.
     * @return An HTTPResponse object containing the response details.
     */
    public HTTPResponse respond(HTTPRequest req) {
        HttpResponse resp = new HttpResponse();
        resp.setStatusCode(200);
        resp.setStatus('OK');
        resp.setBody(body);
        return resp;
    }
}