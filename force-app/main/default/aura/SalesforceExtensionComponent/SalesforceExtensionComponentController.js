({
    handlePeopleChange: function(component, event, helper){
        var people = component.get("v.people");
        console.log('people::: '+JSON.stringify(people));
        
        var source = component.get("v.source");
        console.log('source::: '+JSON.stringify(source));
    },
    
    handleSubjectChange: function(component, event, helper){
    	var subject = component.get("v.subject");
        console.log('subject::: '+JSON.stringify(subject));
	},
    
    handleMessageBodyChange: function(component, event, helper){
    	var messageBody = component.get("v.messageBody");
        console.log('messageBody::: '+JSON.stringify(messageBody));
	}
    
    
})