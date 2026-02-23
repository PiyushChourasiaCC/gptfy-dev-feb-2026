/**
 * @description: 
 * AICanvasViewDesignDataSource is a custom dynamic picklist data source used 
 * within Salesforce's VisualEditor design-time context.
 * 
 * It provides available AI Canvas Templates filtered by object and user context.
 * These templates are shown in a dropdown to configure components or flows.
 *
 * @author            : Piyush Chourasia
 * @group             : Plumcloud Labs
 * @last modified on  : 04-09-2025
 * @last modified by  : Piyush Chourasia
 **/
global with sharing class AICanvasViewDesignDataSource extends VisualEditor.DynamicPickList {
    
    // Holds the list of AI Canvas Templates available for the context object
    List<AI_Canvas_Template__c> canvasTemplates;

    // Design-time context containing entity (object) name and other configuration info
    VisualEditor.DesignTimePageContext context;

    /**
     * @description
     *  Constructor to initialize the picklist data source with the design-time context.
     *  It fetches AI Canvas Templates relevant to the selected object and active status.
     *
     * @param context - The VisualEditor.DesignTimePageContext object provided by the Lightning App Builder
     */
    global AICanvasViewDesignDataSource(VisualEditor.DesignTimePageContext context) {
        this.context = context;
        this.fetchCanvasTemplates();
    }

    /**
     * @description
     *  Queries all active AI Canvas Template records for the specified entity name,
     *  limited to the current user's profile.
     */
    private void fetchCanvasTemplates(){
        String entityName = this.context.entityName;

        // Get current user's profile ID
        Id currentUserProfileId = UserInfo.getProfileId();
        
        // (Optional extension: could be used to filter templates based on profile logic)
        List<Profile> currentUserProfile = [
            SELECT Id, Name 
            FROM Profile 
            WHERE Id = :currentUserProfileId 
            LIMIT 1
        ];

        // Fetch active canvas templates associated with the current object
        if (!currentUserProfile.isEmpty()) {
            this.canvasTemplates = [
                SELECT Id, Name 
                FROM AI_Canvas_Template__c
                WHERE Object__c = :entityName  
                    AND Status__c = 'Active' 
                ORDER BY CreatedDate DESC
                LIMIT 50000
            ];
        }
    }

    /**
     * @description
     *  Returns the default value for the dynamic picklist.
     *  This is used when no option has been selected – typically the first available option.
     *
     * @return VisualEditor.DataRow representing the default canvas template (first in list)
     */
    public override VisualEditor.DataRow getDefaultValue() {
        if (!canvasTemplates.isEmpty()) {
            return new VisualEditor.DataRow(canvasTemplates[0].Name, String.valueOf(canvasTemplates[0].Id));
        } else {
            return new VisualEditor.DataRow('', '');
        }
    }

    /**
     * @description
     *  Returns a list of available canvas templates as picklist rows for display in component config panel.
     *
     * @return VisualEditor.DynamicPickListRows - a list of template names and corresponding IDs
     */
    public override VisualEditor.DynamicPickListRows getValues() {
        VisualEditor.DynamicPickListRows picklistOptions = new VisualEditor.DynamicPickListRows();
    
        for (AI_Canvas_Template__c template : canvasTemplates) {
            picklistOptions.addRow(new VisualEditor.DataRow(template.Name, String.valueOf(template.Id)));
        }

        return picklistOptions;
    }
}