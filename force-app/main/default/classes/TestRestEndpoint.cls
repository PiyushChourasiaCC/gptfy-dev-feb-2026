@RestResource(urlMapping='/OutlookEmailHook/*')
global with sharing class TestRestEndpoint {
    
    global class EmailRequest {
        public String to;
        public String subject;
        public String body;
        public String fromAddress;
        public String hasAttachments;
    }

    @HttpPost
    global static EmailRequest handleEmail() {
        String rawBody = RestContext.request.requestBody.toString();
        System.debug('RAW REQUEST BODY: ' + rawBody);

        EmailRequest er = (EmailRequest) JSON.deserialize(rawBody, EmailRequest.class);
        System.debug('To: ' + er.to);
        System.debug('SUBJECT: ' + er.subject);
        System.debug('FROM: ' + er.fromAddress);
        System.debug('HAS ATT: ' + er.hasAttachments);

        return er;
    }
}