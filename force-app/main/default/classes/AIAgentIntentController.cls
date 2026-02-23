/**
 * @description Controller for AI Agent Intent Manager LWC.
 *   Provides CRUD operations for AI_Agent_Intent__c and AI_Intent_Action__c,
 *   as well as schema-describe helpers for object/field pickers.
 *
 * @author            : Sagar Alwani
 * @group             : Plumcloud Labs
 * @last modified on  : 20-02-2026
 * @last modified by  : Sagar Alwani
 */
public with sharing class AIAgentIntentController {

    private static final String APPLICATION_NAME = 'GPTfy';
    private static final String CLASS_NAME = 'AIAgentIntentController';

    // ─── Wrapper classes ───────────────────────────────────────────

    public class IntentDataWrapper {
        @AuraEnabled public IntentWrapper intent { get; set; }
        @AuraEnabled public List<ActionWrapper> actions { get; set; }
        @AuraEnabled public List<PicklistOption> actionTypeOptions { get; set; }
        @AuraEnabled public List<PicklistOption> apexReturnTypeOptions { get; set; }
        @AuraEnabled public List<PicklistOption> languageOptions { get; set; }
    }

    public class IntentWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public Integer sequence { get; set; }
        @AuraEnabled public String agentId { get; set; }
        @AuraEnabled public String agentName { get; set; }
    }

    public class ActionWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String actionType { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public Integer sequence { get; set; }
        @AuraEnabled public String objectName { get; set; }
        @AuraEnabled public String fieldApiName { get; set; }
        @AuraEnabled public String cannedResponse { get; set; }
        @AuraEnabled public String language { get; set; }
        @AuraEnabled public String apexClassName { get; set; }
        @AuraEnabled public String apexReturnType { get; set; }
        @AuraEnabled public String flowApiName { get; set; }
        @AuraEnabled public List<ActionDetailWrapper> fieldMappings { get; set; }
    }

    public class ActionDetailWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String fieldApiName { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public Integer sequence { get; set; }
    }

    public class PicklistOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }

        public PicklistOption() {}

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    // ─── Intent CRUD ───────────────────────────────────────────────

    /**
     * Fetches a single intent with its child actions and picklist metadata.
     * @param intentId The AI_Agent_Intent__c record Id
     * @return IntentDataWrapper
     */
    @AuraEnabled
    public static IntentDataWrapper getIntentWithActions(Id intentId) {
        try {
            AI_Agent_Intent__c rec = [
                SELECT Id, Name, Description__c, Is_Active__c, Sequence__c,
                       AI_Agent__c, AI_Agent__r.Name,
                       (SELECT Id, Action_Type__c, Description__c, Is_Active__c, Sequence__c,
                               Object_Name__c, Field_API_Name__c, Canned_Response__c,
                               Language__c, Apex_Class_Name__c, Apex_Return_Type__c,
                               Flow_API_Name__c,
                               (SELECT Id, Field_API_Name__c, Type__c, Value__c, Sequence__c
                                FROM Intent_Action_Details__r
                                ORDER BY Sequence__c ASC NULLS LAST)
                        FROM AI_Intent_Actions__r
                        ORDER BY Sequence__c ASC NULLS LAST)
                FROM AI_Agent_Intent__c
                WHERE Id = :intentId
                WITH USER_MODE
                LIMIT 1
            ];

            IntentDataWrapper wrapper = new IntentDataWrapper();

            // Map intent fields
            IntentWrapper iw = new IntentWrapper();
            iw.id = rec.Id;
            iw.name = rec.Name;
            iw.description = rec.Description__c;
            iw.isActive = rec.Is_Active__c;
            iw.sequence = rec.Sequence__c != null ? Integer.valueOf(rec.Sequence__c) : null;
            iw.agentId = rec.AI_Agent__c;
            iw.agentName = rec.AI_Agent__r.Name;
            wrapper.intent = iw;

            // Map actions
            List<ActionWrapper> actionList = new List<ActionWrapper>();
            for (AI_Intent_Action__c a : rec.AI_Intent_Actions__r) {
                actionList.add(mapAction(a));
            }
            wrapper.actions = actionList;

            // Picklist metadata
            wrapper.actionTypeOptions = getPicklistOptions('AI_Intent_Action__c', 'Action_Type__c');
            wrapper.apexReturnTypeOptions = getPicklistOptions('AI_Intent_Action__c', 'Apex_Return_Type__c');
            wrapper.languageOptions = getPicklistOptions('AI_Intent_Action__c', 'Language__c');

            return wrapper;
        } catch (Exception e) {
            GPTfyException.log(e, APPLICATION_NAME, '', CLASS_NAME, 'getIntentWithActions', '');
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Upserts an AI_Agent_Intent__c record.
     * @param intentJson Serialised IntentWrapper
     * @return IntentWrapper with populated Id
     */
    @AuraEnabled
    public static IntentWrapper upsertIntent(String intentJson) {
        try {
            IntentWrapper iw = (IntentWrapper) JSON.deserialize(intentJson, IntentWrapper.class);

            AI_Agent_Intent__c rec = new AI_Agent_Intent__c();
            rec.Name = iw.name;
            rec.Description__c = iw.description;
            rec.Is_Active__c = iw.isActive != null ? iw.isActive : false;
            rec.Sequence__c = iw.sequence;

            if (String.isNotBlank(iw.id)) {
                rec.Id = iw.id;
                FLSCheck.getInstance().updateDML(new List<AI_Agent_Intent__c>{ rec });
            } else {
                rec.AI_Agent__c = iw.agentId;
                rec = (AI_Agent_Intent__c) FLSCheck.getInstance().insertDML(new List<AI_Agent_Intent__c>{ rec }).get(0);
            }

            iw.id = rec.Id;
            return iw;
        } catch (Exception e) {
            GPTfyException.log(e, APPLICATION_NAME, '', CLASS_NAME, 'upsertIntent', '');
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ─── Action CRUD ───────────────────────────────────────────────

    /**
     * Upserts an AI_Intent_Action__c record.
     * @param actionJson Serialised ActionWrapper
     * @param intentId   Parent AI_Agent_Intent__c Id (for inserts)
     * @return ActionWrapper with populated Id
     */
    @AuraEnabled
    public static ActionWrapper upsertAction(String actionJson, Id intentId) {
        try {
            ActionWrapper aw = (ActionWrapper) JSON.deserialize(actionJson, ActionWrapper.class);

            AI_Intent_Action__c rec = new AI_Intent_Action__c();
            rec.Action_Type__c = aw.actionType;
            rec.Description__c = aw.description;
            rec.Is_Active__c = aw.isActive != null ? aw.isActive : false;
            rec.Sequence__c = aw.sequence;
            rec.Object_Name__c = aw.objectName;
            rec.Field_API_Name__c = aw.fieldApiName;
            rec.Canned_Response__c = aw.cannedResponse;
            rec.Language__c = aw.language;
            rec.Apex_Class_Name__c = aw.apexClassName;
            rec.Apex_Return_Type__c = aw.apexReturnType;
            rec.Flow_API_Name__c = aw.flowApiName;

            // Validate Flow API Name exists, is active, and is AutoLaunched
            if (aw.actionType == 'Flow' && String.isNotBlank(aw.flowApiName)) {
                List<FlowDefinitionView> flows = [
                    SELECT ApiName
                    FROM FlowDefinitionView
                    WHERE ApiName = :aw.flowApiName
                      AND IsActive = true
                      AND ProcessType = 'AutoLaunchedFlow'
                    LIMIT 1
                ];
                if (flows.isEmpty()) {
                    throw new AuraHandledException(
                        'Either the Flow "' + aw.flowApiName + '" does not exist, is inactive, or is not of type Autolaunched.'
                    );
                }
            }

            if (String.isNotBlank(aw.id)) {
                rec.Id = aw.id;
                FLSCheck.getInstance().updateDML(new List<AI_Intent_Action__c>{ rec });
            } else {
                rec.AI_Agent_Intent__c = intentId;
                rec = (AI_Intent_Action__c) FLSCheck.getInstance().insertDML(new List<AI_Intent_Action__c>{ rec }).get(0);
            }

            aw.id = rec.Id;

            // Sync child detail records for Create Record actions
            if (aw.actionType == 'Create Record') {
                syncActionDetails(rec.Id, aw.fieldMappings);
            }

            return aw;
        } catch (Exception e) {
            GPTfyException.log(e, APPLICATION_NAME, '', CLASS_NAME, 'upsertAction', '');
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Syncs AI_Intent_Action_Detail__c records for a given action.
     * Upserts submitted details and deletes any that are no longer in the list.
     * @param actionId Parent AI_Intent_Action__c Id
     * @param fieldMappings List of ActionDetailWrapper from the LWC
     */
    private static void syncActionDetails(Id actionId, List<ActionDetailWrapper> fieldMappings) {
        if (fieldMappings == null) {
            fieldMappings = new List<ActionDetailWrapper>();
        }

        // Build records to upsert
        List<AI_Intent_Action_Detail__c> toUpsert = new List<AI_Intent_Action_Detail__c>();
        Set<Id> submittedIds = new Set<Id>();

        for (ActionDetailWrapper dw : fieldMappings) {
            AI_Intent_Action_Detail__c detail = new AI_Intent_Action_Detail__c();
            detail.AI_Intent_Action__c = actionId;
            detail.Field_API_Name__c = dw.fieldApiName;
            detail.Type__c = dw.type;
            detail.Value__c = dw.value;
            detail.Sequence__c = dw.sequence;

            if (String.isNotBlank(dw.id)) {
                detail.Id = dw.id;
                submittedIds.add(dw.id);
            }
            toUpsert.add(detail);
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }

        // Delete orphaned details (removed by the user in the UI)
        List<AI_Intent_Action_Detail__c> existing = [
            SELECT Id FROM AI_Intent_Action_Detail__c
            WHERE AI_Intent_Action__c = :actionId
        ];
        List<AI_Intent_Action_Detail__c> toDelete = new List<AI_Intent_Action_Detail__c>();
        for (AI_Intent_Action_Detail__c ex : existing) {
            if (!submittedIds.contains(ex.Id) && !containsNewlyInsertedId(toUpsert, ex.Id)) {
                toDelete.add(ex);
            }
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
    }

    /**
     * Checks if a detail ID exists in the upserted list (covers newly inserted records).
     */
    private static Boolean containsNewlyInsertedId(List<AI_Intent_Action_Detail__c> records, Id targetId) {
        for (AI_Intent_Action_Detail__c rec : records) {
            if (rec.Id == targetId) {
                return true;
            }
        }
        return false;
    }

    /**
     * Deletes an AI_Intent_Action__c record.
     * @param actionId The record Id to delete
     */
    @AuraEnabled
    public static void deleteAction(Id actionId) {
        try {
            AI_Intent_Action__c rec = new AI_Intent_Action__c(Id = actionId);
            FLSCheck.getInstance().deleteDML(new List<AI_Intent_Action__c>{ rec });
        } catch (Exception e) {
            GPTfyException.log(e, APPLICATION_NAME, '', CLASS_NAME, 'deleteAction', '');
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ─── Schema helpers ────────────────────────────────────────────

    /**
     * Returns all createable & updateable SObjects for the object picker.
     * Delegates to existing AIPromptActionController.getSObjects().
     */
    @AuraEnabled(cacheable=true)
    public static List<AIPromptActionController.PicklistAttributeWrapper> getObjectOptions() {
        return AIPromptActionController.getSObjects();
    }

    /**
     * Returns field options for a given object.
     * Delegates to existing AIPromptActionController.getFieldOptions().
     */
    @AuraEnabled(cacheable=true)
    public static List<AIPromptActionController.PicklistAttributeWrapper> getFieldOptions(String objectName) {
        return AIPromptActionController.getFieldOptions(objectName, false);
    }

    /**
     * Returns active Autolaunched Flows for the flow picker.
     * Queries FlowDefinitionView — only active AutoLaunchedFlow types.
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getFlows() {
        List<PicklistOption> options = new List<PicklistOption>();
        try {
            for (FlowDefinitionView fdv : [
                SELECT ApiName, Label
                FROM FlowDefinitionView
                WHERE IsActive = true
                  AND ProcessType = 'AutoLaunchedFlow'
                ORDER BY Label ASC
            ]) {
                options.add(new PicklistOption(fdv.Label + ' (' + fdv.ApiName + ')', fdv.ApiName));
            }
        } catch (Exception e) {
            GPTfyException.log(e, APPLICATION_NAME, '', CLASS_NAME, 'getFlows', '');
            throw new AuraHandledException('Error loading flows: ' + e.getMessage());
        }
        return options;
    }

    // ─── Private helpers ───────────────────────────────────────────

    private static ActionWrapper mapAction(AI_Intent_Action__c a) {
        ActionWrapper aw = new ActionWrapper();
        aw.id = a.Id;
        aw.actionType = a.Action_Type__c;
        aw.description = a.Description__c;
        aw.isActive = a.Is_Active__c;
        aw.sequence = a.Sequence__c != null ? Integer.valueOf(a.Sequence__c) : null;
        aw.objectName = a.Object_Name__c;
        aw.fieldApiName = a.Field_API_Name__c;
        aw.cannedResponse = a.Canned_Response__c;
        aw.language = a.Language__c;
        aw.apexClassName = a.Apex_Class_Name__c;
        aw.apexReturnType = a.Apex_Return_Type__c;
        aw.flowApiName = a.Flow_API_Name__c;

        // Map child detail records (field mappings for Create Record)
        aw.fieldMappings = new List<ActionDetailWrapper>();
        if (a.Intent_Action_Details__r != null) {
            for (AI_Intent_Action_Detail__c d : a.Intent_Action_Details__r) {
                ActionDetailWrapper dw = new ActionDetailWrapper();
                dw.id = d.Id;
                dw.fieldApiName = d.Field_API_Name__c;
                dw.type = d.Type__c;
                dw.value = d.Value__c;
                dw.sequence = d.Sequence__c != null ? Integer.valueOf(d.Sequence__c) : null;
                aw.fieldMappings.add(dw);
            }
        }
        return aw;
    }

    private static List<PicklistOption> getPicklistOptions(String objectName, String fieldName) {
        List<PicklistOption> options = new List<PicklistOption>();
        try {
            Schema.DescribeFieldResult dfr = Schema.getGlobalDescribe()
                .get(objectName).getDescribe()
                .fields.getMap().get(fieldName).getDescribe();
            for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                if (pe.isActive()) {
                    // Filter out Invoke Agent — not supported yet
                    if (fieldName == 'Action_Type__c' && pe.getValue() == 'Invoke Agent') {
                        continue;
                    }
                    options.add(new PicklistOption(pe.getLabel(), pe.getValue()));
                }
            }
        } catch (Exception e) {
            // Fail silently for picklist describe — non-critical
            System.debug('Error describing picklist ' + objectName + '.' + fieldName + ': ' + e.getMessage());
        }
        return options;
    }
}