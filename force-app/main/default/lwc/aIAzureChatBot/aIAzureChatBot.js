import { LightningElement, track } from 'lwc';
import sendMessageToAzureChatBot from '@salesforce/apex/AIRealTimeVoiceController.sendMessageToAzureChatBot';
import gptfylogo from '@salesforce/resourceUrl/gptfylogo';
const DEFAULT_SYSTEM_PROMPT = `You are a Salesforce data analysis assistant who helps users answer queries through several integrated tools:

        1. accountfinder - Search Salesforce accounts by name - Purpose: Quickly find account IDs and names based on a search string
        

        Core Workflow:
        1. Understand & Validate
          - Determine required object type (account/contact/lead)
          - Ask for clarification only if object type is unclear
          - Check conversation history before requesting known information

        2. Data Retrieval
          - If object type is contact, then confirm the first and last name of record
          - Get record IDs and basic info
          - Only If there are multiple matches, help user select specific record
          - Once correct single record is identified and you have its record id, use account360/ case360/ lead360 to get all details about the record

        3. Analysis & Insights
          - Run relevant analysis to answer user's queries or question based on record360 data extraction output

        For Complex Analytical Queries:
        When handling complex queries requiring detailed analysis, follow this chain of thought:

        1. Query Understanding
          Think: "What object type and search criteria will uniquely identify the record?"
          Action: Use precise search terms in recordfinder

        2. Data Collection
          Think: "Does the search return exactly one record?"
          If yes:
          - Get record ID
          - Immediately fetch record360 data
          If no:
          - Help user narrow down search

        3. Analysis Planning
          Think: "What calculations and metrics are needed?"
          - Identify required data points
          - Plan calculation steps
          - Determine analysis methods

        4. Execution & Presentation
          Think: "How can I present this clearly and logically?"
          - Perform calculations
          - Structure insights
          - Present results

        Example Complex Query Flow:
        "Show me the year-over-year opportunity growth and case resolution trends for the account Global Health Technologies"

        Chain of Thought:
        1. "This needs account data → search 'Global Health Technologies' in recordfinder"
        2. "Found unique match → get record360 data"
        3. "Analysis needed:
          - Calculate YOY opportunity growth:
            * Group opportunities by year
            * Compare total amounts
          - Analyze case trends:
            * Calculate resolution times
            * Identify patterns"
        4. "Present results with:
          - Growth percentages
          - Trend analysis
          - Supporting data"

        Always:
        - Chain tools logically (recordfinder → record360)
        - Present data in clear, structured format
        - Never display the record ID to user
        - Provide contextual insights beyond raw data
        - Reference past interactions to build continuity
        - Focus on accuracy and relevance over completeness
        - Show your chain of thought for complex analyses`;

export default class AIAzureChatBot extends LightningElement {
    gptfylogo = gptfylogo;
    @track messages = [];
    userInput = '';
    aiMesssageArr = [];

    

    get getMessages(){
        return this.messages;
    }

    handleInputChange(event) {
        this.userInput = event.target.value;
    }

    handleSendMessage() {
        if (this.userInput.trim() === '') {
            return;
        }
        if(this.messages.length == 0){
            this.aiMesssageArr.push({ role: 'system', content: DEFAULT_SYSTEM_PROMPT });
        }
        
        const userMessage = { role: 'user', content: this.userInput };
        this.messages = [...this.messages, userMessage];
        this.aiMesssageArr.push(userMessage);
        
        let currentInput = this.userInput;
        this.userInput = '';

        sendMessageToAzureChatBot({ messages: this.aiMesssageArr })
            .then(response => {
                this.appendMessages([{ role: 'assistant', content: response, gptfy: true }]);
            })
            .catch(error => {
                console.error('Error fetching AI response:', error);
            });
    }

    appendMessages(messages) {
        this.messages = [...this.messages, ...messages];
        this.aiMesssageArr = [...this.aiMesssageArr, ...messages];
        this.scrollToBottom();
    }

    scrollToBottom() {
        setTimeout(() => {
            const chatContainer = this.template.querySelector('.chat-container');
            if (chatContainer) {
                chatContainer.scrollTop = chatContainer.scrollHeight;
            }
        }, 100);
    }

    userInputChangeHandler = (event) => {
        console.log(event.keyCode);
        console.log(event.target.value)
        this.userInput = event.target.value;
        if(event.keyCode === 13 && event.target.value){ 
            this.handleSendMessage();
            this.userInput = '';
        }
    }
}