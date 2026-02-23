({
	doInit : function(cmp, event, helper) {
        var action = cmp.get("c.runNow");
        action.setParams({recordId : cmp.get("v.recordId")});
 
        action.setCallback(this, function(response) {
            var state = response.getState();
            var resp = response.getReturnValue();
            if(state === "SUCCESS"){
                var toastEvent = $A.get("e.force:showToast");
                toastEvent.setParams({
                    "title": "Success!",
                    "message": "Job has been successfully submitted.",
                    "type": "success"
                });
                toastEvent.fire();
            }else if (state === "ERROR") {
                var errors = response.getError();
                var message = "Operation was unsuccessful"; // default
    
                if (errors && errors.length > 0 && errors[0].message) {
                    message = errors[0].message;   // Apex exception message
                }
                var toastEvent = $A.get("e.force:showToast");
                toastEvent.setParams({
                    "title": "Error!",
                    "message": message,
                    "type": "error"
                });
                toastEvent.fire();
            }
            $A.get("e.force:closeQuickAction").fire();
        });
        $A.enqueueAction(action);
    }
})