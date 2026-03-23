/**
 * AIWorkspaceSyncOrchestrator - Orchestrator for workspace-based sync
 * 
 * Replaces the old Named Credential approach with token-based sync
 * using AI_Workspace_User__c stored refresh tokens.
 * 
 * Two modes:
 * 1. startScheduledSync() - Called by scheduler, processes ALL workspace users
 * 2. runNowForCurrentUser() - Called by "Run Now" button, processes ONLY current user
 * 
 * @author GPTfy
 * @date 2026-01-16
 * @Jira V2-7695, V2-7696, V2-7796
 */
public with sharing class AIWorkspaceSyncOrchestrator {
    
    /**
     * Start scheduled sync for ALL workspace users.
     * Called by AIEmailSyncScheduler.
     * V2-7889: Fixed to start with the first enabled sync type (Email, Calendar, or Task)
     */
    public static void startScheduledSync() {
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        
        Boolean emailEnabled = settings != null && settings.Sync_Enabled__c;
        Boolean calendarEnabled = settings != null && settings.Calendar_Sync_Enabled__c;
        Boolean taskEnabled = settings != null && settings.Task_Sync_Enabled__c;
        
        if (!emailEnabled && !calendarEnabled && !taskEnabled) {
            createSystemSyncLog('Skipped', 'All sync types are disabled');
            return;
        }
        
        // Query ALL workspace users with active users and auto sync enabled
        // Note: Refresh_Token__c is encrypted so we can't filter on it in SOQL
        List<AI_Workspace_User__c> allWorkspaceUsers = [
            SELECT Id, User__c, Provider__c, Refresh_Token__c
            FROM AI_Workspace_User__c
            WHERE User__r.IsActive = true
            AND Auto_Sync_Enabled__c = true
            ORDER BY Provider__c, CreatedDate ASC
            LIMIT :getMaxUsersPerBatch()
        ];
        
        // Filter to only those with valid refresh tokens (Apex filter since encrypted field)
        List<Id> workspaceUserIds = new List<Id>();
        for (AI_Workspace_User__c wu : allWorkspaceUsers) {
            if (String.isNotBlank(wu.Refresh_Token__c)) {
                workspaceUserIds.add(wu.Id);
            }
        }
        
        if (workspaceUserIds.isEmpty()) {
            createSystemSyncLog('Skipped', 'No workspace users with valid tokens found');
            return;
        }
        
        // V2-7889: Determine the first enabled sync type to start with
        AIWorkspaceSyncQueueable.SyncType startSyncType;
        if (emailEnabled) {
            startSyncType = AIWorkspaceSyncQueueable.SyncType.EMAIL;
        } else if (calendarEnabled) {
            startSyncType = AIWorkspaceSyncQueueable.SyncType.CALENDAR;
        } else if (taskEnabled) {
            startSyncType = AIWorkspaceSyncQueueable.SyncType.TASK;
        } else {
            // This should never happen due to the check above, but default to EMAIL
            startSyncType = AIWorkspaceSyncQueueable.SyncType.EMAIL;
        }
        
        // Start queueable chain with the correct starting sync type
        System.enqueueJob(new AIWorkspaceSyncQueueable(workspaceUserIds, 0, startSyncType));
    }
    
    /**
     * Run sync NOW for current user only.
     * Called by "Run Now" button in LWC.
     * NOTE: Auto_Sync_Enabled__c is NOT checked here - "Run Now" should sync ALL providers for current user
     */
    @AuraEnabled
    public static void runNowForCurrentUser() {
        Id currentUserId = UserInfo.getUserId();
        
        // Query ALL workspace users for current user (regardless of Auto_Sync_Enabled__c)
        // Run Now should sync all connected providers, not just auto-sync enabled ones
        // Note: Refresh_Token__c is encrypted so we can't filter on it in SOQL
        List<AI_Workspace_User__c> allWorkspaceUsers = [
            SELECT Id, User__c, Provider__c, Refresh_Token__c
            FROM AI_Workspace_User__c
            WHERE User__c = :currentUserId
            ORDER BY Provider__c ASC
        ];
        
        // Filter to only those with valid refresh tokens (Apex filter since encrypted field)
        List<Id> workspaceUserIds = new List<Id>();
        for (AI_Workspace_User__c wu : allWorkspaceUsers) {
            if (String.isNotBlank(wu.Refresh_Token__c)) {
                workspaceUserIds.add(wu.Id);
            }
        }
        
        if (workspaceUserIds.isEmpty()) {
            throw new AuraHandledException('No authenticated email providers found. Please connect your Outlook or Gmail account first.');
        }
        
        // Determine which sync type to start with based on settings
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        AIWorkspaceSyncQueueable.SyncType startSyncType;
        
        if (settings != null && settings.Sync_Enabled__c) {
            startSyncType = AIWorkspaceSyncQueueable.SyncType.EMAIL;
        } else if (settings != null && settings.Calendar_Sync_Enabled__c) {
            startSyncType = AIWorkspaceSyncQueueable.SyncType.CALENDAR;
        } else if (settings != null && settings.Task_Sync_Enabled__c) {
            startSyncType = AIWorkspaceSyncQueueable.SyncType.TASK;
        } else {
            // Default to EMAIL if no settings found
            startSyncType = AIWorkspaceSyncQueueable.SyncType.EMAIL;
        }
        
        // Start queueable in run-now mode (won't chain to other users)
        System.enqueueJob(new AIWorkspaceSyncQueueable(
            workspaceUserIds, 0, startSyncType, true
        ));
    }
    
    /**
     * Check if current user has any workspace connections
     */
    @AuraEnabled(cacheable=true)
    public static Boolean hasWorkspaceConnection() {
        // Note: Refresh_Token__c is encrypted so we filter in Apex
        List<AI_Workspace_User__c> workspaceUsers = [
            SELECT Id, Refresh_Token__c
            FROM AI_Workspace_User__c
            WHERE User__c = :UserInfo.getUserId()
        ];
        
        for (AI_Workspace_User__c wu : workspaceUsers) {
            if (String.isNotBlank(wu.Refresh_Token__c)) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * Get list of connected providers for current user
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getConnectedProviders() {
        List<String> providers = new List<String>();
        
        // Note: Refresh_Token__c is encrypted so we filter in Apex
        List<AI_Workspace_User__c> workspaceUsers = [
            SELECT Provider__c, Refresh_Token__c
            FROM AI_Workspace_User__c
            WHERE User__c = :UserInfo.getUserId()
        ];
        
        for (AI_Workspace_User__c wu : workspaceUsers) {
            if (String.isNotBlank(wu.Refresh_Token__c)) {
                providers.add(wu.Provider__c);
            }
        }
        
        return providers;
    }
    
    /**
     * Get sync status for current user
     */
    @AuraEnabled
    public static SyncStatus getSyncStatusForCurrentUser() {
        SyncStatus status = new SyncStatus();
        Id currentUserId = UserInfo.getUserId();
        
        // Check for workspace connections
        // Note: Refresh_Token__c is encrypted so we filter in Apex
        List<AI_Workspace_User__c> workspaceUsers = [
            SELECT Id, Provider__c, Refresh_Token__c
            FROM AI_Workspace_User__c
            WHERE User__c = :currentUserId
        ];
        
        status.connectedProviders = new List<String>();
        for (AI_Workspace_User__c wu : workspaceUsers) {
            if (String.isNotBlank(wu.Refresh_Token__c)) {
                status.connectedProviders.add(wu.Provider__c);
            }
        }
        status.hasConnection = !status.connectedProviders.isEmpty();
        
        // Get last sync info
        List<AI_Workspace_Sync_Log__c> lastLogs = [
            SELECT Id, Status__c, End_Time__c, Emails_Imported__c, Provider_Type__c
            FROM AI_Workspace_Sync_Log__c
            WHERE User__c = :currentUserId
            ORDER BY End_Time__c DESC
            LIMIT 1
        ];
        
        if (!lastLogs.isEmpty()) {
            AI_Workspace_Sync_Log__c lastLog = lastLogs[0];
            status.lastSyncTime = lastLog.End_Time__c;
            status.lastSyncStatus = lastLog.Status__c;
            status.lastSyncProvider = lastLog.Provider_Type__c;
            status.lastEmailsImported = lastLog.Emails_Imported__c != null ? 
                Integer.valueOf(lastLog.Emails_Imported__c) : 0;
        }
        
        return status;
    }
    
    /**
     * Get max users per batch from settings
     */
    private static Integer getMaxUsersPerBatch() {
        AI_Workspace_Sync_Settings__c settings = AI_Workspace_Sync_Settings__c.getOrgDefaults();
        return settings != null && settings.Max_Users_Per_Batch__c != null
            ? (Integer) settings.Max_Users_Per_Batch__c
            : 1000;
    }
    
    /**
     * Create a system-level sync log entry
     */
    private static void createSystemSyncLog(String status, String message) {
        try {
            AI_Workspace_Sync_Log__c log = new AI_Workspace_Sync_Log__c(
                Sync_Type__c = 'Scheduled',
                Status__c = status,
                Start_Time__c = DateTime.now(),
                End_Time__c = DateTime.now(),
                Error_Message__c = message
            );
            
            // Use FLSCheck for security enforcement
            List<AI_Workspace_Sync_Log__c> logsToInsert = new List<AI_Workspace_Sync_Log__c>{ log };
            FLSCheck.getInstance().insertDML(logsToInsert);
        } catch (Exception e) {
            // Ignore
        }
    }
    
    /**
     * Sync status wrapper for UI
     */
    public class SyncStatus {
        @AuraEnabled public Boolean hasConnection { get; set; }
        @AuraEnabled public List<String> connectedProviders { get; set; }
        @AuraEnabled public DateTime lastSyncTime { get; set; }
        @AuraEnabled public String lastSyncStatus { get; set; }
        @AuraEnabled public String lastSyncProvider { get; set; }
        @AuraEnabled public Integer lastEmailsImported { get; set; }
        
        public SyncStatus() {
            this.hasConnection = false;
            this.connectedProviders = new List<String>();
            this.lastEmailsImported = 0;
        }
    }
}