/**
 * AIStagingEmailMatcherScheduler - Schedulable class to run the email matching batch
 * 
 * Runs the AIStagingEmailMatcherBatch periodically to process pending staging records.
 * 
 * Usage:
 *   // Start the scheduler (runs every 15 minutes by default)
 *   AIStagingEmailMatcherScheduler.start();
 *   
 *   // Start with custom frequency (in minutes)
 *   AIStagingEmailMatcherScheduler.start(30);
 *   
 *   // Stop the scheduler
 *   AIStagingEmailMatcherScheduler.stop();
 *   
 *   // Run once immediately (for testing)
 *   AIStagingEmailMatcherScheduler.runNow();
 * 
 * @author GPTfy
 * @date 2026-01
 */
public with sharing class AIStagingEmailMatcherScheduler implements Schedulable {
    
    private static final String JOB_NAME = 'AI Staging Email Matcher';
    private static final Integer DEFAULT_FREQUENCY_MINUTES = 15;
    private static final Integer DEFAULT_BATCH_SIZE = 50;
    
    private Integer frequencyMinutes;
    private Integer batchSize;
    
    /**
     * Default constructor
     */
    public AIStagingEmailMatcherScheduler() {
        this.frequencyMinutes = DEFAULT_FREQUENCY_MINUTES;
        this.batchSize = DEFAULT_BATCH_SIZE;
    }
    
    /**
     * Constructor with custom settings
     */
    public AIStagingEmailMatcherScheduler(Integer frequencyMinutes, Integer batchSize) {
        this.frequencyMinutes = frequencyMinutes != null ? frequencyMinutes : DEFAULT_FREQUENCY_MINUTES;
        this.batchSize = batchSize != null ? batchSize : DEFAULT_BATCH_SIZE;
    }
    
    /**
     * Execute the scheduled job
     */
    public void execute(SchedulableContext ctx) {
        try {
            // Run the batch
            AIStagingEmailMatcherBatch.runBatch(batchSize);
            System.debug(LoggingLevel.INFO, 'Started AIStagingEmailMatcherBatch at ' + DateTime.now());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error starting AIStagingEmailMatcherBatch: ' + e.getMessage());
        }
        
        // Reschedule for next run
        reschedule();
    }
    
    /**
     * Reschedule the job for the next run
     */
    private void reschedule() {
        try {
            // Abort current job (if any)
            abortExistingJob();
            
            // Schedule next run
            DateTime nextRun = DateTime.now().addMinutes(frequencyMinutes);
            String cronExp = getCronExpression(nextRun);
            
            System.schedule(JOB_NAME + ' ' + nextRun.getTime(), cronExp, 
                new AIStagingEmailMatcherScheduler(frequencyMinutes, batchSize));
            
            System.debug(LoggingLevel.INFO, 'Rescheduled AIStagingEmailMatcherScheduler for ' + nextRun);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error rescheduling: ' + e.getMessage());
        }
    }
    
    /**
     * Build cron expression for a specific DateTime
     */
    private String getCronExpression(DateTime dt) {
        return String.format('{0} {1} {2} {3} {4} ? {5}', 
            new List<Object>{
                dt.second(),
                dt.minute(),
                dt.hour(),
                dt.day(),
                dt.month(),
                dt.year()
            });
    }
    
    /**
     * Abort existing scheduled job
     */
    private static void abortExistingJob() {
        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger 
            WHERE CronJobDetail.Name LIKE :JOB_NAME + '%'
        ];
        
        for (CronTrigger job : jobs) {
            try {
                System.abortJob(job.Id);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Could not abort job ' + job.Id + ': ' + e.getMessage());
            }
        }
    }
    
    /**
     * Start the scheduler with default frequency (15 minutes)
     */
    public static void start() {
        start(DEFAULT_FREQUENCY_MINUTES);
    }
    
    /**
     * Start the scheduler with custom frequency
     * @param frequencyMinutes Run frequency in minutes
     */
    public static void start(Integer frequencyMinutes) {
        // Abort any existing jobs first
        stop();
        
        // Schedule initial run in 1 minute
        DateTime nextRun = DateTime.now().addMinutes(1);
        String cronExp = new AIStagingEmailMatcherScheduler().getCronExpression(nextRun);
        
        System.schedule(JOB_NAME + ' ' + nextRun.getTime(), cronExp, 
            new AIStagingEmailMatcherScheduler(frequencyMinutes, DEFAULT_BATCH_SIZE));
        
        System.debug(LoggingLevel.INFO, 'Started AIStagingEmailMatcherScheduler, first run at ' + nextRun);
    }
    
    /**
     * Stop the scheduler
     */
    public static void stop() {
        abortExistingJob();
        System.debug(LoggingLevel.INFO, 'Stopped AIStagingEmailMatcherScheduler');
    }
    
    /**
     * Run the batch immediately (for testing or manual execution)
     * @return Batch job ID
     */
    public static Id runNow() {
        return AIStagingEmailMatcherBatch.runBatch();
    }
    
    /**
     * Check if the scheduler is currently running
     * @return true if a scheduled job exists
     */
    public static Boolean isRunning() {
        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger 
            WHERE CronJobDetail.Name LIKE :JOB_NAME + '%'
            LIMIT 1
        ];
        return !jobs.isEmpty();
    }
}