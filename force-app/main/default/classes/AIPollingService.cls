public with sharing class AIPollingService implements Queueable, Database.AllowsCallouts {
	
    public AIAudioProcessingService.ProcessAudioWrapper wrap;
    
    public AIPollingService(AIAudioProcessingService.ProcessAudioWrapper wrap){
        this.wrap = wrap;
    }
    
    public void execute(QueueableContext context) {
        AIAudioProcessingService.performPolling(wrap);
    }
    
}