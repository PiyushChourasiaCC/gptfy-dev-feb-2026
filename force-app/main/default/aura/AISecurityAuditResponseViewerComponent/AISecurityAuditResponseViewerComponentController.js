({
	onPageReferenceChange: function(cmp, evt, helper) {
        document.title = "Security Audit Response";
        var urlString = window.location.href;
        var id = urlString.substring(urlString.lastIndexOf("=")+1);
        cmp.set("v.id", id);
    }
})