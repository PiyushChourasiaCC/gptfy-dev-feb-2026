import { api, LightningElement,wire } from 'lwc';
import { CurrentPageReference } from "lightning/navigation";
import getPromptOptions from '@salesforce/apex/AITeamsBotsController.getPromptOptions';
import simpleupdatein from '@salesforce/resourceUrl/simpleupdatein';
import wc from '@salesforce/resourceUrl/webchat';
import { loadScript } from 'lightning/platformResourceLoader';

export default class Teamsbots extends LightningElement {

    @api recordId;
    isRecordIdNotNull = false;
    jsonData = {}


    @wire(CurrentPageReference)
    wireCurrentPageReference(currentPageReference) {
        if (currentPageReference) {
            this.recordId = currentPageReference.attributes.recordId;
            console.log('recordId : '+this.recordId);
            console.log('currentPageReference : '+currentPageReference);
            console.log('currentPageReference.attributes : '+JSON.stringify(currentPageReference.attributes));
            if(this.recordId && this.recordId !== ''){
                this.isRecordIdNotNull = true;
                const myHeaders = new Headers();
                    myHeaders.append("Authorization", "Bearer T4wZHp1qaHc.ujRM1CjBiGu8uLcT3q1WsqoyqqGtC1ck_2LQEhNa0_4");
                    fetch('https://directline.botframework.com/v3/directline/tokens/generate', { method: 'POST', headers: myHeaders })
                    .then(res => res.json())
                    .then((res)=> {
                        const { token } =  res	
                        this.loadPrompts(this.recordId,currentPageReference.attributes.objectApiName,token);
                    });	
               
            }else{
                this.isRecordIdNotNull = false;
            }
        }
    }


    loadPrompts(recordId,objectName,token){

        

        getPromptOptions({ "recordId": recordId, "objectApiName" : objectName }).then((result) => {
            if(result){
                this.jsonData = {
                    "promptOptions": result.options,
                    "recordId": recordId,
                    "objectName": objectName
                }
               // console.log(JSON.stringify(this.jsonData));
               
                this.loadFrame(this.jsonData,token)
            }
            

        }).catch(error => {
            console.log('error : '+JSON.stringify(error));
        })


}

         loadFrame(jsonData,token){
            try{
               // let mydiv = this.template.querySelector("div[data-my-id=webchat]")
                Promise.all([
                        loadScript(this, wc),
                        loadScript(this, simpleupdatein)
                    ]).then(() => {
                        //console.log('all js loaded');
                        const store = WebChat.createStore({}, ({ dispatch }) => next => action => {
                        if (action.type === 'DIRECT_LINE/POST_ACTIVITY') {
                            action = simpleUpdateIn(
                            action,
                            ['payload', 'activity', 'channelData', 'jsonData'],
                            () => jsonData
                            );
                        }

                        return next(action);
                        });

                        WebChat.renderWebChat(
                        {
                            directLine: WebChat.createDirectLine({ token }),
                            store
                        },
                        this.template.querySelector('.webchat')
                        );

                        this.template.querySelector('.webchat > *').focus();

                    });
                    		
                       
                 

            }catch(err){
                console.error(err)
            }
        }
}