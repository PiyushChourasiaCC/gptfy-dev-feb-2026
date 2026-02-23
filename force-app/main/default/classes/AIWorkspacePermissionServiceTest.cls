/**
 * Test class for AIWorkspacePermissionService
 * Tests permission checking for workspace sync related objects
 */
@isTest
private class AIWorkspacePermissionServiceTest {
    
    @isTest
    static void testCheckEmailMessagePermission_WithAccess() {
        Test.startTest();
        AIWorkspacePermissionService.PermissionResult result = 
            AIWorkspacePermissionService.checkEmailMessagePermission();
        Test.stopTest();
        
        // Result should always be returned (access depends on running user's profile)
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isNotNull(result.missingPermissions, 'Missing permissions list should not be null');
        
        // In test context, user typically has access
        if (result.hasAccess) {
            Assert.areEqual('', result.errorMessage, 'Error message should be empty when user has access');
            Assert.areEqual(0, result.missingPermissions.size(), 'Missing permissions should be empty');
        } else {
            Assert.isFalse(result.hasAccess, 'Should not have access');
            Assert.isTrue(result.errorMessage.contains('EmailMessage'), 'Error should mention EmailMessage');
            Assert.isTrue(result.missingPermissions.contains('Create EmailMessage'), 'Should list missing permission');
        }
    }
    
    @isTest
    static void testCheckEventPermission_WithAccess() {
        Test.startTest();
        AIWorkspacePermissionService.PermissionResult result = 
            AIWorkspacePermissionService.checkEventPermission();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isNotNull(result.missingPermissions, 'Missing permissions list should not be null');
        
        if (result.hasAccess) {
            Assert.areEqual('', result.errorMessage, 'Error message should be empty when user has access');
            Assert.areEqual(0, result.missingPermissions.size(), 'Missing permissions should be empty');
        } else {
            Assert.isFalse(result.hasAccess, 'Should not have access');
            Assert.isTrue(result.errorMessage.contains('Event'), 'Error should mention Event');
            Assert.isTrue(result.missingPermissions.contains('Create Event'), 'Should list missing permission');
        }
    }
    
    @isTest
    static void testCheckTaskPermission_WithAccess() {
        Test.startTest();
        AIWorkspacePermissionService.PermissionResult result = 
            AIWorkspacePermissionService.checkTaskPermission();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isNotNull(result.missingPermissions, 'Missing permissions list should not be null');
        
        if (result.hasAccess) {
            Assert.areEqual('', result.errorMessage, 'Error message should be empty when user has access');
            Assert.areEqual(0, result.missingPermissions.size(), 'Missing permissions should be empty');
        } else {
            Assert.isFalse(result.hasAccess, 'Should not have access');
            Assert.isTrue(result.errorMessage.contains('Task'), 'Error should mention Task');
            Assert.isTrue(result.missingPermissions.contains('Create Task'), 'Should list missing permission');
        }
    }
    
    @isTest
    static void testCheckStagingPermission_WithAccess() {
        Test.startTest();
        AIWorkspacePermissionService.PermissionResult result = 
            AIWorkspacePermissionService.checkStagingPermission();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isNotNull(result.missingPermissions, 'Missing permissions list should not be null');
        
        if (result.hasAccess) {
            Assert.areEqual('', result.errorMessage, 'Error message should be empty when user has access');
            Assert.areEqual(0, result.missingPermissions.size(), 'Missing permissions should be empty');
        } else {
            Assert.isFalse(result.hasAccess, 'Should not have access');
            Assert.isTrue(result.errorMessage.contains('Workspace Staging'), 'Error should mention Workspace Staging');
            Assert.isTrue(result.missingPermissions.contains('Create AI Workspace Staging'), 'Should list missing permission');
        }
    }
    
    @isTest
    static void testCheckEmailSyncPermissions_WithAccess() {
        Test.startTest();
        AIWorkspacePermissionService.PermissionResult result = 
            AIWorkspacePermissionService.checkEmailSyncPermissions();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isNotNull(result.missingPermissions, 'Missing permissions list should not be null');
        
        if (result.hasAccess) {
            Assert.areEqual('', result.errorMessage, 'Error message should be empty when user has access');
            Assert.areEqual(0, result.missingPermissions.size(), 'Missing permissions should be empty');
        } else {
            Assert.isFalse(result.hasAccess, 'Should not have access');
            Assert.isTrue(
                result.errorMessage.contains('AI Workspace Staging') || 
                result.errorMessage.contains('EmailMessage'),
                'Error message should mention missing object types'
            );
            Assert.isTrue(result.missingPermissions.size() > 0, 'Should have missing permissions');
        }
    }
    
    @isTest
    static void testCheckCalendarSyncPermissions_WithAccess() {
        Test.startTest();
        AIWorkspacePermissionService.PermissionResult result = 
            AIWorkspacePermissionService.checkCalendarSyncPermissions();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isNotNull(result.missingPermissions, 'Missing permissions list should not be null');
        
        if (result.hasAccess) {
            Assert.areEqual('', result.errorMessage, 'Error message should be empty when user has access');
            Assert.areEqual(0, result.missingPermissions.size(), 'Missing permissions should be empty');
        } else {
            Assert.isFalse(result.hasAccess, 'Should not have access');
            Assert.isTrue(
                result.errorMessage.contains('AI Workspace Staging') || 
                result.errorMessage.contains('Event'),
                'Error message should mention missing object types'
            );
            Assert.isTrue(result.missingPermissions.size() > 0, 'Should have missing permissions');
        }
    }
    
    @isTest
    static void testCheckTaskSyncPermissions_WithAccess() {
        Test.startTest();
        AIWorkspacePermissionService.PermissionResult result = 
            AIWorkspacePermissionService.checkTaskSyncPermissions();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isNotNull(result.missingPermissions, 'Missing permissions list should not be null');
        
        if (result.hasAccess) {
            Assert.areEqual('', result.errorMessage, 'Error message should be empty when user has access');
            Assert.areEqual(0, result.missingPermissions.size(), 'Missing permissions should be empty');
        } else {
            Assert.isFalse(result.hasAccess, 'Should not have access');
            Assert.isTrue(
                result.errorMessage.contains('AI Workspace Staging') || 
                result.errorMessage.contains('Task'),
                'Error message should mention missing object types'
            );
            Assert.isTrue(result.missingPermissions.size() > 0, 'Should have missing permissions');
        }
    }
    
    @isTest
    static void testCheckSchedulerPermissions_WithAccess() {
        Test.startTest();
        AIWorkspacePermissionService.PermissionResult result = 
            AIWorkspacePermissionService.checkSchedulerPermissions();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isNotNull(result.missingPermissions, 'Missing permissions list should not be null');
        
        if (result.hasAccess) {
            Assert.areEqual('', result.errorMessage, 'Error message should be empty when user has access');
            Assert.areEqual(0, result.missingPermissions.size(), 'Missing permissions should be empty');
        } else {
            Assert.isFalse(result.hasAccess, 'Should not have access');
            Assert.isTrue(result.errorMessage.length() > 0, 'Error message should be present when access is denied');
            Assert.isTrue(result.missingPermissions.size() > 0, 'Should have missing permissions');
        }
    }
    
    @isTest
    static void testPermissionResultInitialization() {
        Test.startTest();
        AIWorkspacePermissionService.PermissionResult result = 
            new AIWorkspacePermissionService.PermissionResult();
        Test.stopTest();
        
        // Default values
        Assert.isTrue(result.hasAccess, 'Default hasAccess should be true');
        Assert.areEqual('', result.errorMessage, 'Default errorMessage should be empty');
        Assert.isNotNull(result.missingPermissions, 'Missing permissions list should be initialized');
        Assert.areEqual(0, result.missingPermissions.size(), 'Missing permissions list should be empty by default');
    }
    
    @isTest
    static void testPermissionResultFields() {
        Test.startTest();
        AIWorkspacePermissionService.PermissionResult result = 
            new AIWorkspacePermissionService.PermissionResult();
        
        // Test setting fields
        result.hasAccess = false;
        result.errorMessage = 'Test error message';
        result.missingPermissions.add('Test Permission');
        Test.stopTest();
        
        Assert.isFalse(result.hasAccess, 'hasAccess should be false');
        Assert.areEqual('Test error message', result.errorMessage, 'Error message should match');
        Assert.areEqual(1, result.missingPermissions.size(), 'Should have one missing permission');
        Assert.areEqual('Test Permission', result.missingPermissions[0], 'Permission should match');
    }
    
    @isTest
    static void testAllPermissionChecks_Comprehensive() {
        // Test all methods in a single test to ensure they all execute
        Test.startTest();
        
        AIWorkspacePermissionService.PermissionResult emailResult = 
            AIWorkspacePermissionService.checkEmailMessagePermission();
        AIWorkspacePermissionService.PermissionResult eventResult = 
            AIWorkspacePermissionService.checkEventPermission();
        AIWorkspacePermissionService.PermissionResult taskResult = 
            AIWorkspacePermissionService.checkTaskPermission();
        AIWorkspacePermissionService.PermissionResult stagingResult = 
            AIWorkspacePermissionService.checkStagingPermission();
        AIWorkspacePermissionService.PermissionResult emailSyncResult = 
            AIWorkspacePermissionService.checkEmailSyncPermissions();
        AIWorkspacePermissionService.PermissionResult calendarSyncResult = 
            AIWorkspacePermissionService.checkCalendarSyncPermissions();
        AIWorkspacePermissionService.PermissionResult taskSyncResult = 
            AIWorkspacePermissionService.checkTaskSyncPermissions();
        AIWorkspacePermissionService.PermissionResult schedulerResult = 
            AIWorkspacePermissionService.checkSchedulerPermissions();
        
        Test.stopTest();
        
        // Verify all results are not null
        Assert.isNotNull(emailResult, 'Email result should not be null');
        Assert.isNotNull(eventResult, 'Event result should not be null');
        Assert.isNotNull(taskResult, 'Task result should not be null');
        Assert.isNotNull(stagingResult, 'Staging result should not be null');
        Assert.isNotNull(emailSyncResult, 'Email sync result should not be null');
        Assert.isNotNull(calendarSyncResult, 'Calendar sync result should not be null');
        Assert.isNotNull(taskSyncResult, 'Task sync result should not be null');
        Assert.isNotNull(schedulerResult, 'Scheduler result should not be null');
        
        // Verify all have initialized missing permissions lists
        Assert.isNotNull(emailResult.missingPermissions, 'Email missing permissions should be initialized');
        Assert.isNotNull(eventResult.missingPermissions, 'Event missing permissions should be initialized');
        Assert.isNotNull(taskResult.missingPermissions, 'Task missing permissions should be initialized');
        Assert.isNotNull(stagingResult.missingPermissions, 'Staging missing permissions should be initialized');
        Assert.isNotNull(emailSyncResult.missingPermissions, 'Email sync missing permissions should be initialized');
        Assert.isNotNull(calendarSyncResult.missingPermissions, 'Calendar sync missing permissions should be initialized');
        Assert.isNotNull(taskSyncResult.missingPermissions, 'Task sync missing permissions should be initialized');
        Assert.isNotNull(schedulerResult.missingPermissions, 'Scheduler missing permissions should be initialized');
    }
    
    @isTest
    static void testPermissionChecks_WithRestrictedUser() {
        // Create a user with minimal permissions to test negative scenarios
        Profile minAccessProfile = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        User restrictedUser = new User(
            Alias = 'testmin',
            Email = 'testminimum@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = minAccessProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testminimum' + System.currentTimeMillis() + '@test.com'
        );
        insert restrictedUser;
        
        Test.startTest();
        System.runAs(restrictedUser) {
            // Test individual permission checks
            AIWorkspacePermissionService.PermissionResult emailResult = 
                AIWorkspacePermissionService.checkEmailMessagePermission();
            AIWorkspacePermissionService.PermissionResult eventResult = 
                AIWorkspacePermissionService.checkEventPermission();
            AIWorkspacePermissionService.PermissionResult taskResult = 
                AIWorkspacePermissionService.checkTaskPermission();
            AIWorkspacePermissionService.PermissionResult stagingResult = 
                AIWorkspacePermissionService.checkStagingPermission();
            
            // Test combined permission checks
            AIWorkspacePermissionService.PermissionResult emailSyncResult = 
                AIWorkspacePermissionService.checkEmailSyncPermissions();
            AIWorkspacePermissionService.PermissionResult calendarSyncResult = 
                AIWorkspacePermissionService.checkCalendarSyncPermissions();
            AIWorkspacePermissionService.PermissionResult taskSyncResult = 
                AIWorkspacePermissionService.checkTaskSyncPermissions();
            AIWorkspacePermissionService.PermissionResult schedulerResult = 
                AIWorkspacePermissionService.checkSchedulerPermissions();
            
            // Verify results are not null (actual permissions depend on profile)
            Assert.isNotNull(emailResult, 'Email result should not be null');
            Assert.isNotNull(eventResult, 'Event result should not be null');
            Assert.isNotNull(taskResult, 'Task result should not be null');
            Assert.isNotNull(stagingResult, 'Staging result should not be null');
            Assert.isNotNull(emailSyncResult, 'Email sync result should not be null');
            Assert.isNotNull(calendarSyncResult, 'Calendar sync result should not be null');
            Assert.isNotNull(taskSyncResult, 'Task sync result should not be null');
            Assert.isNotNull(schedulerResult, 'Scheduler result should not be null');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testMultiplePermissionChecks_Sequential() {
        // Test calling methods multiple times to ensure consistency
        Test.startTest();
        
        AIWorkspacePermissionService.PermissionResult result1 = 
            AIWorkspacePermissionService.checkEmailMessagePermission();
        AIWorkspacePermissionService.PermissionResult result2 = 
            AIWorkspacePermissionService.checkEmailMessagePermission();
        
        Test.stopTest();
        
        // Results should be consistent
        Assert.areEqual(result1.hasAccess, result2.hasAccess, 'Results should be consistent');
        Assert.areEqual(result1.errorMessage, result2.errorMessage, 'Error messages should be consistent');
        Assert.areEqual(result1.missingPermissions.size(), result2.missingPermissions.size(), 'Missing permissions should be consistent');
    }
    
    @isTest
    static void testPermissionResult_AllFields() {
        Test.startTest();
        AIWorkspacePermissionService.PermissionResult result = 
            new AIWorkspacePermissionService.PermissionResult();
        
        // Test all field assignments
        result.hasAccess = true;
        Assert.isTrue(result.hasAccess, 'hasAccess should be true');
        
        result.hasAccess = false;
        Assert.isFalse(result.hasAccess, 'hasAccess should be false');
        
        result.errorMessage = 'Test Error 1';
        Assert.areEqual('Test Error 1', result.errorMessage, 'Error message should match');
        
        result.errorMessage = 'Test Error 2';
        Assert.areEqual('Test Error 2', result.errorMessage, 'Error message should be updated');
        
        result.missingPermissions.add('Permission 1');
        Assert.areEqual(1, result.missingPermissions.size(), 'Should have 1 permission');
        
        result.missingPermissions.add('Permission 2');
        Assert.areEqual(2, result.missingPermissions.size(), 'Should have 2 permissions');
        
        result.missingPermissions.clear();
        Assert.areEqual(0, result.missingPermissions.size(), 'Should have 0 permissions after clear');
        
        Test.stopTest();
    }
    
    @isTest
    static void testAllCombinedPermissionChecks() {
        // Test all combined permission check methods to ensure complete coverage
        Test.startTest();
        
        // Test email sync permissions (checks staging + email)
        AIWorkspacePermissionService.PermissionResult emailSync1 = 
            AIWorkspacePermissionService.checkEmailSyncPermissions();
        Assert.isNotNull(emailSync1, 'Email sync result should not be null');
        Assert.isNotNull(emailSync1.missingPermissions, 'Missing permissions should be initialized');
        
        // Test calendar sync permissions (checks staging + event)
        AIWorkspacePermissionService.PermissionResult calendarSync1 = 
            AIWorkspacePermissionService.checkCalendarSyncPermissions();
        Assert.isNotNull(calendarSync1, 'Calendar sync result should not be null');
        Assert.isNotNull(calendarSync1.missingPermissions, 'Missing permissions should be initialized');
        
        // Test task sync permissions (checks staging + task)
        AIWorkspacePermissionService.PermissionResult taskSync1 = 
            AIWorkspacePermissionService.checkTaskSyncPermissions();
        Assert.isNotNull(taskSync1, 'Task sync result should not be null');
        Assert.isNotNull(taskSync1.missingPermissions, 'Missing permissions should be initialized');
        
        // Test scheduler permissions (checks all: staging + email + event + task)
        AIWorkspacePermissionService.PermissionResult scheduler1 = 
            AIWorkspacePermissionService.checkSchedulerPermissions();
        Assert.isNotNull(scheduler1, 'Scheduler result should not be null');
        Assert.isNotNull(scheduler1.missingPermissions, 'Missing permissions should be initialized');
        
        // Call again to test consistency
        AIWorkspacePermissionService.PermissionResult emailSync2 = 
            AIWorkspacePermissionService.checkEmailSyncPermissions();
        AIWorkspacePermissionService.PermissionResult calendarSync2 = 
            AIWorkspacePermissionService.checkCalendarSyncPermissions();
        AIWorkspacePermissionService.PermissionResult taskSync2 = 
            AIWorkspacePermissionService.checkTaskSyncPermissions();
        AIWorkspacePermissionService.PermissionResult scheduler2 = 
            AIWorkspacePermissionService.checkSchedulerPermissions();
        
        // Verify consistency
        Assert.areEqual(emailSync1.hasAccess, emailSync2.hasAccess, 'Email sync results should be consistent');
        Assert.areEqual(calendarSync1.hasAccess, calendarSync2.hasAccess, 'Calendar sync results should be consistent');
        Assert.areEqual(taskSync1.hasAccess, taskSync2.hasAccess, 'Task sync results should be consistent');
        Assert.areEqual(scheduler1.hasAccess, scheduler2.hasAccess, 'Scheduler results should be consistent');
        
        Test.stopTest();
    }
    
    @isTest
    static void testIndividualPermissionChecks_Complete() {
        // Comprehensive test of all individual permission checks
        Test.startTest();
        
        // Check EmailMessage permission
        AIWorkspacePermissionService.PermissionResult emailMsg = 
            AIWorkspacePermissionService.checkEmailMessagePermission();
        Assert.isNotNull(emailMsg, 'EmailMessage result should not be null');
        
        // Check Event permission
        AIWorkspacePermissionService.PermissionResult event = 
            AIWorkspacePermissionService.checkEventPermission();
        Assert.isNotNull(event, 'Event result should not be null');
        
        // Check Task permission
        AIWorkspacePermissionService.PermissionResult task = 
            AIWorkspacePermissionService.checkTaskPermission();
        Assert.isNotNull(task, 'Task result should not be null');
        
        // Check Staging permission
        AIWorkspacePermissionService.PermissionResult staging = 
            AIWorkspacePermissionService.checkStagingPermission();
        Assert.isNotNull(staging, 'Staging result should not be null');
        
        // Verify all results have proper structure
        Assert.isNotNull(emailMsg.missingPermissions, 'EmailMessage missing permissions should be initialized');
        Assert.isNotNull(event.missingPermissions, 'Event missing permissions should be initialized');
        Assert.isNotNull(task.missingPermissions, 'Task missing permissions should be initialized');
        Assert.isNotNull(staging.missingPermissions, 'Staging missing permissions should be initialized');
        
        // If any don't have access, verify error messages are present
        if (!emailMsg.hasAccess) {
            Assert.isTrue(emailMsg.errorMessage.length() > 0, 'EmailMessage should have error message');
        }
        if (!event.hasAccess) {
            Assert.isTrue(event.errorMessage.length() > 0, 'Event should have error message');
        }
        if (!task.hasAccess) {
            Assert.isTrue(task.errorMessage.length() > 0, 'Task should have error message');
        }
        if (!staging.hasAccess) {
            Assert.isTrue(staging.errorMessage.length() > 0, 'Staging should have error message');
        }
        
        Test.stopTest();
    }
}