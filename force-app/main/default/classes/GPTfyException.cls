public with sharing class GPTfyException extends Exception {

    public static void Log(Exception excp , String applicationName , String moduleName , String className , String methodName,String supportData){
        
        String queryLimit = '1. SOQL Queries used / SOQL Queries allowed: ' + Limits.getQueries() + '/' + Limits.getLimitQueries();
        String dmlLimit = '2. Number of records queried so far /  Number allowed: ' + Limits.getDmlRows() + '/' + Limits.getLimitDmlRows();
        String dmlStat = '3. Number of DML statements used so far / Number allowed: ' +  Limits.getDmlStatements() + '/' + Limits.getLimitDmlStatements();
        String cpuUsage = '4. Amount of CPU time (in ms) used so far / CPU usage time (in ms) allowed: ' + Limits.getCpuTime() + '/' + Limits.getLimitCpuTime();
        
        List<String> lstSalesforceLimit = new List<String>();
        lstSalesforceLimit.add(queryLimit);
        lstSalesforceLimit.add(dmlLimit);
        lstSalesforceLimit.add(dmlStat);
        lstSalesforceLimit.add(cpuUsage);
        
        
        //Create exception record
        Exception_Log__c exc = new Exception_Log__c();
        exc.Salesforce_Limits__c = String.format( '{0}\n{1}\n{2}\n{3}', lstSalesforceLimit);
        if(excp != null){
            exc.Error_Message__c = excp.getMessage();
            exc.Exception_Type__c = excp.getTypeName();
            exc.Line_Number__c = String.valueOf(excp.getLineNumber());
            exc.Stack_Trace__c = excp.getStackTraceString();
        }
        exc.Application_Name__c = applicationName;
        exc.Module_Name__c = moduleName;
        exc.Class_Name__c  = className;
        exc.Method_Name__c = methodName;
        exc.Exception_Running_User__c = UserInfo.getUserId();
        exc.Error_Support_Data__c = supportData;
        if(AIConstants.enableExceptionLog){
            FLSCheck.getInstance().insertDML(new List<Exception_Log__c>{exc});
        }
    }
}