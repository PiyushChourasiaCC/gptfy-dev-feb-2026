/**
 * @description       : Queueable class to execute prompt scheduler batches sequentially.
 *                      This avoids the Salesforce limit of 5 concurrent batch jobs and
 *                      eliminates CPU timeout issues from busy-wait loops.
 * @author            : Sohit Sharma
 * @jira              : Jira v2/7712 Issue: AI Mass Processing with more than 7 Prompts
 *                      V2-7889 Added skipBatchExecution flag for improved test coverage
 * @group             : Plumcloud Labs
 * @last modified on  : 03-20-2026
 * @last modified by  : Piyush Chourasia
 **/
public class AIPromptSchedulerQueueable implements Queueable, Finalizer {
    
    private List<AI_Prompt_Scheduler__c> schedulers;
    private Integer currentIndex;
    private AI_Scheduled_Run__c scheduledRun;
    
    // Flag for finalizer to know if chaining is needed
    private Boolean needsChaining = false;
    
    // Test support
    @TestVisible
    private static Boolean disableChaining = false;
    
    @TestVisible
    private static Boolean skipBatchExecution = false;
    
    /**
     * Constructor for initial execution with list of schedulers
     * @param schedulers List of AI_Prompt_Scheduler__c records to process
     * @param scheduledRun The AI_Scheduled_Run__c record for this run
     */
    public AIPromptSchedulerQueueable(List<AI_Prompt_Scheduler__c> schedulers, AI_Scheduled_Run__c scheduledRun) {
        this.schedulers = schedulers;
        this.currentIndex = 0;
        this.scheduledRun = scheduledRun;
    }
    
    /**
     * Constructor for chained execution
     * @param schedulers List of AI_Prompt_Scheduler__c records to process
     * @param currentIndex The index of the next scheduler to process
     * @param scheduledRun The AI_Scheduled_Run__c record for this run
     */
    public AIPromptSchedulerQueueable(List<AI_Prompt_Scheduler__c> schedulers, Integer currentIndex, AI_Scheduled_Run__c scheduledRun) {
        this.schedulers = schedulers;
        this.currentIndex = currentIndex;
        this.scheduledRun = scheduledRun;
    }
    
    /**
     * Executes the queueable job - processes one scheduler at a time
     * @param context The QueueableContext
     */
    public void execute(QueueableContext context) {
        // Attach finalizer to handle chaining without depth limits
        if (!Test.isRunningTest()) {
            System.attachFinalizer(this);
        }
        
        try {
            // Check if there are more schedulers to process
            if (currentIndex >= schedulers.size()) {
                return; // All done
            }
            
            // Get current scheduler and execute its batch
            AI_Prompt_Scheduler__c currentScheduler = schedulers[currentIndex];
            if (!skipBatchExecution) {
                Database.executeBatch(new AIPromptCountRequestBatch(currentScheduler, scheduledRun), 2000);
            }
            
            // Move to next index
            currentIndex++;
            
            // Determine if we need to chain for more schedulers
            if (currentIndex < schedulers.size()) {
                needsChaining = true;
            }
            
        } catch (Exception e) {
            GPTfyException.log(e, 'GPTfy', '', 'AIPromptSchedulerQueueable', 'execute', '');
            // Continue to next scheduler even if this one fails
            currentIndex++;
            if (currentIndex < schedulers.size()) {
                needsChaining = true;
            }
        }
    }
    
    /**
     * Finalizer execute - Called after queueable completes
     * Uses finalizer to chain, which avoids stack depth issues
     * @param context The FinalizerContext
     */
    public void execute(FinalizerContext context) {
        if (needsChaining && !disableChaining) {
            System.debug('Finalizer: Chaining to process scheduler index ' + currentIndex + ' of ' + schedulers.size());
            
            AIPromptSchedulerQueueable nextJob = new AIPromptSchedulerQueueable(
                schedulers,
                currentIndex,
                scheduledRun
            );
            
            System.enqueueJob(nextJob);
        }
    }
}