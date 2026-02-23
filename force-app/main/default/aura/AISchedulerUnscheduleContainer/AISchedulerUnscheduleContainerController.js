({
	doInit : function(cmp, event, helper) {
        var action = cmp.get("c.unscheduleJob");
        action.setParams({recordId : cmp.get("v.recordId")});
 
        action.setCallback(this, function(response) {
            var state = response.getState();
            var resp = response.getReturnValue();
            if(state === "SUCCESS"){
                var toastEvent = $A.get("e.force:showToast");
                toastEvent.setParams({
                    "title": "Success!",
                    "message": "Job has been successfully unscheduled.",
                    "type": "success"
                });
                toastEvent.fire();
            }else if (state === "ERROR") {
                var toastEvent = $A.get("e.force:showToast");
                toastEvent.setParams({
                    "title": "Error!",
                    "message": "Operation was unsuccessful",
                    "type": "error"
                });
                toastEvent.fire();
            }
            $A.get("e.force:closeQuickAction").fire();
			$A.get('e.force:refreshView').fire();
        });
        $A.enqueueAction(action);
    }
})