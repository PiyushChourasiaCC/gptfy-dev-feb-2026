/**
 * @description Test class for AIBusinessContextAnalyzer
 * @author Piyush Chourasia
 * @group Plumcloud Labs
 * @last modified on 03-04-2026
 * @last modified by Piyush Chourasia
 * @jira V2-7823
 */
@isTest
private class AIBusinessContextAnalyzerTest {
    
    @isTest
    static void testAnalyzeBusinessContext_WithExplicitObjectReferences() {
        Test.startTest();
        
        String businessContext = 'Create an Account prompt that will show me opportunities with their opportunity roles';
        AIBusinessContextAnalyzer.AnalysisResult result = 
            AIBusinessContextAnalyzer.analyzeBusinessContext(businessContext, 'Account');
        
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isTrue(result.hasExplicitObjectReferences, 'Should detect explicit object references');
        Assert.isTrue(!result.priorityChildObjects.isEmpty(), 'Should have priority child objects');
    }
    
    @isTest
    static void testAnalyzeBusinessContext_WithSalesKeywords() {
        Test.startTest();
        
        String businessContext = 'Show me sales pipeline and revenue information';
        AIBusinessContextAnalyzer.AnalysisResult result = 
            AIBusinessContextAnalyzer.analyzeBusinessContext(businessContext, 'Account');
        
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isTrue(!result.priorityChildObjects.isEmpty(), 'Should infer priority objects from keywords');
    }
    
    @isTest
    static void testAnalyzeBusinessContext_WithServiceKeywords() {
        Test.startTest();
        
        String businessContext = 'Display customer support cases and email communications';
        AIBusinessContextAnalyzer.AnalysisResult result = 
            AIBusinessContextAnalyzer.analyzeBusinessContext(businessContext, 'Account');
        
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isTrue(!result.priorityChildObjects.isEmpty(), 'Should detect service-related objects');
    }
    
    @isTest
    static void testAnalyzeBusinessContext_EmptyContext() {
        Test.startTest();
        
        AIBusinessContextAnalyzer.AnalysisResult result = 
            AIBusinessContextAnalyzer.analyzeBusinessContext('', 'Account');
        
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isFalse(result.hasExplicitObjectReferences, 'Should not have explicit references');
        Assert.isTrue(!result.priorityChildObjects.isEmpty(), 'Should use default priorities');
    }
    
    @isTest
    static void testAnalyzeBusinessContext_NullContext() {
        Test.startTest();
        
        AIBusinessContextAnalyzer.AnalysisResult result = 
            AIBusinessContextAnalyzer.analyzeBusinessContext(null, 'Contact');
        
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isTrue(!result.priorityChildObjects.isEmpty(), 'Should use default priorities for Contact');
    }
    
    @isTest
    static void testAnalyzeBusinessContext_MultipleKeywords() {
        Test.startTest();
        
        String businessContext = 'Show opportunities, cases, and email activity for this account';
        AIBusinessContextAnalyzer.AnalysisResult result = 
            AIBusinessContextAnalyzer.analyzeBusinessContext(businessContext, 'Account');
        
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isTrue(result.priorityChildObjects.size() > 0, 'Should detect multiple objects');
    }
    
    @isTest
    static void testFilterChildRelationships() {
        Test.startTest();
        
        List<AISchemaHelper.ChildRelationship> allChildren = AISchemaHelper.getChildRelationships('Account');
        List<String> priorities = new List<String>{'Opportunity', 'Contact', 'Case'};
        
        List<AISchemaHelper.ChildRelationship> filtered = 
            AIBusinessContextAnalyzer.filterChildRelationships(allChildren, priorities);
        
        Test.stopTest();
        
        Assert.isNotNull(filtered, 'Filtered list should not be null');
        // Verify that filtered list only contains objects from priorities
        Set<String> prioritySet = new Set<String>(priorities);
        for (AISchemaHelper.ChildRelationship child : filtered) {
            Assert.isTrue(prioritySet.contains(child.childObject), 
                         'Filtered child should be in priority list: ' + child.childObject);
        }
    }
    
    @isTest
    static void testAnalyzeBusinessContext_OpportunityObject() {
        Test.startTest();
        
        String businessContext = 'Show me product line items and quotes';
        AIBusinessContextAnalyzer.AnalysisResult result = 
            AIBusinessContextAnalyzer.analyzeBusinessContext(businessContext, 'Opportunity');
        
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isTrue(!result.priorityChildObjects.isEmpty(), 'Should have priority objects for Opportunity');
    }
    
    @isTest
    static void testAnalyzeBusinessContext_CaseObject() {
        Test.startTest();
        
        String businessContext = 'Display case comments and email messages';
        AIBusinessContextAnalyzer.AnalysisResult result = 
            AIBusinessContextAnalyzer.analyzeBusinessContext(businessContext, 'Case');
        
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isTrue(result.hasExplicitObjectReferences || !result.priorityChildObjects.isEmpty(), 
                     'Should detect case-related objects');
    }
    
    @isTest
    static void testAnalyzeBusinessContext_ActivityKeywords() {
        Test.startTest();
        
        String businessContext = 'Show all activity and engagement history';
        AIBusinessContextAnalyzer.AnalysisResult result = 
            AIBusinessContextAnalyzer.analyzeBusinessContext(businessContext, 'Account');
        
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isTrue(!result.priorityChildObjects.isEmpty(), 'Should detect activity-related objects');
    }
}