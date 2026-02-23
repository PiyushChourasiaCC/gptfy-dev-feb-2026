({
	reInit : function(component, event, helper) {
        $A.get('e.force:refreshView').fire();
    },
    
    handleCancel : function(component, event, helper) {
        var recId = event.getParam('value');
        if(recId){
            var navEvt = $A.get("e.force:navigateToSObject");
            navEvt.setParams({
            	"recordId": recId
            });
            navEvt.fire();
            window.setTimeout($A.getCallback(function(){
                $A.get('e.force:refreshView').fire();
            }), 1000);
        }
    },
})