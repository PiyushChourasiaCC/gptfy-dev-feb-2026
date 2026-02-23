/**
 * Service class for checking user permissions on workspace sync related objects.
 * Provides friendly error messages when users lack required permissions.
 */
public with sharing class AIWorkspacePermissionService {
    
    /**
     * Permission check result wrapper
     */
    public class PermissionResult {
        @AuraEnabled public Boolean hasAccess { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public List<String> missingPermissions { get; set; }
        
        public PermissionResult() {
            this.hasAccess = true;
            this.errorMessage = '';
            this.missingPermissions = new List<String>();
        }
    }
    
    /**
     * Check if the current user has permission to create EmailMessage records
     * @return PermissionResult with access status and any error messages
     */
    @AuraEnabled(cacheable=true)
    public static PermissionResult checkEmailMessagePermission() {
        PermissionResult result = new PermissionResult();
        
        if (!Schema.sObjectType.EmailMessage.isCreateable()) {
            result.hasAccess = false;
            result.missingPermissions.add('Create EmailMessage');
            result.errorMessage = 'You do not have permission to create Email Message records. Please contact your Salesforce administrator to grant access to the EmailMessage object.';
        }
        
        return result;
    }
    
    /**
     * Check if the current user has permission to create Event records
     * @return PermissionResult with access status and any error messages
     */
    @AuraEnabled(cacheable=true)
    public static PermissionResult checkEventPermission() {
        PermissionResult result = new PermissionResult();
        
        if (!Schema.sObjectType.Event.isCreateable()) {
            result.hasAccess = false;
            result.missingPermissions.add('Create Event');
            result.errorMessage = 'You do not have permission to create Event records. Please contact your Salesforce administrator to grant access to the Event object.';
        }
        
        return result;
    }
    
    /**
     * Check if the current user has permission to create Task records
     * @return PermissionResult with access status and any error messages
     */
    @AuraEnabled(cacheable=true)
    public static PermissionResult checkTaskPermission() {
        PermissionResult result = new PermissionResult();
        
        if (!Schema.sObjectType.Task.isCreateable()) {
            result.hasAccess = false;
            result.missingPermissions.add('Create Task');
            result.errorMessage = 'You do not have permission to create Task records. Please contact your Salesforce administrator to grant access to the Task object.';
        }
        
        return result;
    }
    
    /**
     * Check if the current user has permission to create AI_Workspace_Staging__c records
     * @return PermissionResult with access status and any error messages
     */
    @AuraEnabled(cacheable=true)
    public static PermissionResult checkStagingPermission() {
        PermissionResult result = new PermissionResult();
        
        if (!Schema.sObjectType.AI_Workspace_Staging__c.isCreateable()) {
            result.hasAccess = false;
            result.missingPermissions.add('Create AI Workspace Staging');
            result.errorMessage = 'You do not have permission to create Workspace Staging records. Please contact your Salesforce administrator to grant access.';
        }
        
        return result;
    }
    
    /**
     * Check all permissions required for email sync (staging + email message)
     * @return PermissionResult with combined access status and any error messages
     */
    @AuraEnabled(cacheable=true)
    public static PermissionResult checkEmailSyncPermissions() {
        PermissionResult result = new PermissionResult();
        List<String> missingObjects = new List<String>();
        
        if (!Schema.sObjectType.AI_Workspace_Staging__c.isCreateable()) {
            missingObjects.add('AI Workspace Staging');
        }
        
        if (!Schema.sObjectType.EmailMessage.isCreateable()) {
            missingObjects.add('EmailMessage');
        }
        
        if (!missingObjects.isEmpty()) {
            result.hasAccess = false;
            result.missingPermissions = missingObjects;
            result.errorMessage = 'You do not have permission to create the following record types: ' + 
                String.join(missingObjects, ', ') + 
                '. Please contact your Salesforce administrator to grant the required access for Email Sync.';
        }
        
        return result;
    }
    
    /**
     * Check all permissions required for calendar sync (staging + event)
     * @return PermissionResult with combined access status and any error messages
     */
    @AuraEnabled(cacheable=true)
    public static PermissionResult checkCalendarSyncPermissions() {
        PermissionResult result = new PermissionResult();
        List<String> missingObjects = new List<String>();
        
        if (!Schema.sObjectType.AI_Workspace_Staging__c.isCreateable()) {
            missingObjects.add('AI Workspace Staging');
        }
        
        if (!Schema.sObjectType.Event.isCreateable()) {
            missingObjects.add('Event');
        }
        
        if (!missingObjects.isEmpty()) {
            result.hasAccess = false;
            result.missingPermissions = missingObjects;
            result.errorMessage = 'You do not have permission to create the following record types: ' + 
                String.join(missingObjects, ', ') + 
                '. Please contact your Salesforce administrator to grant the required access for Calendar Sync.';
        }
        
        return result;
    }
    
    /**
     * Check all permissions required for task sync (staging + task)
     * @return PermissionResult with combined access status and any error messages
     */
    @AuraEnabled(cacheable=true)
    public static PermissionResult checkTaskSyncPermissions() {
        PermissionResult result = new PermissionResult();
        List<String> missingObjects = new List<String>();
        
        if (!Schema.sObjectType.AI_Workspace_Staging__c.isCreateable()) {
            missingObjects.add('AI Workspace Staging');
        }
        
        if (!Schema.sObjectType.Task.isCreateable()) {
            missingObjects.add('Task');
        }
        
        if (!missingObjects.isEmpty()) {
            result.hasAccess = false;
            result.missingPermissions = missingObjects;
            result.errorMessage = 'You do not have permission to create the following record types: ' + 
                String.join(missingObjects, ', ') + 
                '. Please contact your Salesforce administrator to grant the required access for Task Sync.';
        }
        
        return result;
    }
    
    /**
     * Check all permissions required for scheduler (email, event, task, staging)
     * @return PermissionResult with combined access status and any error messages
     */
    @AuraEnabled(cacheable=true)
    public static PermissionResult checkSchedulerPermissions() {
        PermissionResult result = new PermissionResult();
        List<String> missingObjects = new List<String>();
        
        if (!Schema.sObjectType.AI_Workspace_Staging__c.isCreateable()) {
            missingObjects.add('AI Workspace Staging');
        }
        
        if (!Schema.sObjectType.EmailMessage.isCreateable()) {
            missingObjects.add('EmailMessage');
        }
        
        if (!Schema.sObjectType.Event.isCreateable()) {
            missingObjects.add('Event');
        }
        
        if (!Schema.sObjectType.Task.isCreateable()) {
            missingObjects.add('Task');
        }
        
        if (!missingObjects.isEmpty()) {
            result.hasAccess = false;
            result.missingPermissions = missingObjects;
            result.errorMessage = 'You do not have permission to create the following record types: ' + 
                String.join(missingObjects, ', ') + 
                '. Please contact your Salesforce administrator to grant the required access for Workspace Sync.';
        }
        
        return result;
    }
}