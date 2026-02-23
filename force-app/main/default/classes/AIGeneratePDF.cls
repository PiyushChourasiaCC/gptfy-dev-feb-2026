public class AIGeneratePDF {
    public Account recentAccount { get; private set; }
    public AI_Response__c recentAIResponse { get; private set; }

    public AIGeneratePDF() {
        // Fetch the most recent Account
        recentAccount = [SELECT Id, Name FROM Account ORDER BY CreatedDate DESC LIMIT 1];
        // Check for 'id' parameter in the URL
        Id aiResponseId = (Id)ApexPages.currentPage().getParameters().get('id');
        if (aiResponseId != null) {
            recentAIResponse = [SELECT Id, AI_Processed_Data_PII_Added__c FROM AI_Response__c WHERE Id = :aiResponseId LIMIT 1];
        } else {
            recentAIResponse = [SELECT Id, AI_Processed_Data_PII_Added__c FROM AI_Response__c ORDER BY CreatedDate DESC LIMIT 1];
        }
    }

    // Static method to fetch AI_Processed_Data_PII_Added__c by Id
    public static String getHtmlContentById(Id aiResponseId) {
        if (aiResponseId == null) return null;
        AI_Response__c resp = [SELECT AI_Processed_Data_PII_Added__c FROM AI_Response__c WHERE Id = :aiResponseId LIMIT 1];
        return resp != null ? resp.AI_Processed_Data_PII_Added__c : null;
    }

    @AuraEnabled
    public static Id generateAndAttachPdf(Id aiResponseId, Boolean isLandscape) {
        if (aiResponseId == null) {
            throw new AuraHandledException('AI_Response__c Id is required');
        }
        try {
            // Fetch the AI_Response__c record
            AI_Response__c aiResp = [SELECT AI_Processed_Data_PII_Added__c FROM AI_Response__c WHERE Id = :aiResponseId LIMIT 1];
            // Fetch the most recent Account
            Account acc = [SELECT Id, Name FROM Account WHERE Name = 'abc INC.' ORDER BY CreatedDate DESC LIMIT 1];

            // Prepare the VF page for PDF rendering
            PageReference pdfPage = Page.AIGeneratePDF;
            
            // Set the parameters
            pdfPage.getParameters().put('id', aiResponseId);
            //pdfPage.getParameters().put('landscape', String.valueOf(isLandscape));

            // Render as PDF
            Blob pdfBlob = pdfPage.getContentAsPDF();

            // Create ContentVersion
            ContentVersion cv = new ContentVersion();
            cv.Title = 'AI Response PDF - ' + (isLandscape ? 'Landscape' : 'Portrait');
            cv.PathOnClient = 'AI_Response_' + (isLandscape ? 'Landscape' : 'Portrait') + '.pdf';
            cv.VersionData = pdfBlob;
            cv.FirstPublishLocationId = acc.Id;
            insert cv;

            // Query ContentDocumentId
            cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
            return cv.ContentDocumentId;
        } catch (Exception e) {
            throw new AuraHandledException('Error generating PDF: ' + e.getMessage());
        }
    }

}