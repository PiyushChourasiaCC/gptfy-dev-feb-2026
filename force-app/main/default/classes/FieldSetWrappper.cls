public with sharing class FieldSetWrappper {
    @AuraEnabled public String Label {get; set;}
    @AuraEnabled public String fieldPath {get; set;}
    @AuraEnabled public String Type {get; set;}
    @AuraEnabled public Boolean Required {get; set;}
    @AuraEnabled public String SObjectField {get; set;}
    
    public FieldSetWrappper(Schema.FieldSetMember member, String namespace){
        this.Label = member.getLabel();
        this.fieldPath = member.getFieldPath();
        this.Type = String.valueOf(member.getType());
        this.Required = (member.getRequired() || member.getDBRequired());
        this.SObjectField = String.valueOf(member.getSObjectField());
    }
}