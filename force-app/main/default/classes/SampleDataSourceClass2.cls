global class SampleDataSourceClass2 implements AIDataSourceInterface {
	
    global String getExternalData(AI_Data_Source__c dataSource, String extractedData){
      /*  Map<String, Object> maps = (Map<String, Object>)JSON.deserializeUntyped(extractedData);
        maps.put('Industry', 'Agriculture');
        return JSON.serialize(maps); */
        Map<String, Object> maps = (Map<String, Object>)JSON.deserializeUntyped(extractedData);
        System.debug('extractedData : '+maps.get('Id'));
         HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:'+dataSource.Named_Credential__c);  // Replace with your Named Credential name
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(60000);

        String sql = 'SELECT t1.EID,t1.EmployeeName, t1.Email,t2.did, t2.departmentname FROM TESTDB.myschema.Employee as t1 '+ 
					'INNER JOIN TESTDB.myschema.Department t2 ON t1.department_id = t2.did WHERE t2.ExternalId = \''+maps.get('Id')+'\'';
        Map<String, Object> body = new Map<String, Object>{
            'statement' => sql,
            'timeout' => 60,
            'warehouse' => 'COMPUTE_WH',
            'database' => 'TESTDB',
            'schema' => 'MYSCHEMA',
            'role' => 'SYSADMIN'
        };
        req.setBody(JSON.serialize(body));
		Http http = new Http();
        HttpResponse res = http.send(req);
        if (res.getStatusCode() == 200) {
            // Parse response: res.getBody() contains JSON with 'resultSet' for data
            Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Object o = (object)  response.get('data');
            System.debug('Query Result: ' + o);
            return o.toString();
        } else {
            System.debug('Error: ' + res.getStatusCode() + ' - ' + res.getBody());
            return 'Error: ' + res.getStatusCode() + ' - ' + res.getBody();
        }
    }
    
}