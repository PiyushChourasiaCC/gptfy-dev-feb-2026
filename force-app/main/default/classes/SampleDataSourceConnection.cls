global class SampleDataSourceConnection extends DataSource.Connection {
    
    private DataSource.ConnectionParams connectionInfo;
    global SampleDataSourceConnection(DataSource.ConnectionParams connectionParams) {
        this.connectionInfo = connectionParams;
	}
        
    override global List<DataSource.Table> sync() {
        List<DataSource.Table> tables =
            new List<DataSource.Table>();
        List<DataSource.Column> columns;
        columns = new List<DataSource.Column>();
        columns.add(DataSource.Column.text('Price', 255));
        columns.add(DataSource.Column.text('OrderStatus', 255));
        columns.add(DataSource.Column.number('Sequence', 10,1));
        columns.add(DataSource.Column.number('Quantity', 10,1));
        columns.add(DataSource.Column.text('ExternalId', 255));
        columns.add(DataSource.Column.url('DisplayUrl'));
        tables.add(DataSource.Table.get('ORDERTABLETEST2', 'Price',columns));
        return tables;
    }
        
        override global DataSource.TableResult query( DataSource.QueryContext context) {
        if (context.tableSelection.columnsSelected.size() == 1 &&
            context.tableSelection.columnsSelected.get(0).aggregation ==
                DataSource.QueryAggregation.COUNT) {
                List<Map<String,Object>> rows = getRows(context);
                List<Map<String,Object>> response =
                    DataSource.QueryUtils.filter(context, getRows(context));
                List<Map<String, Object>> countResponse =
                    new List<Map<String, Object>>();
                Map<String, Object> countRow =
                    new Map<String, Object>();
                countRow.put(
                    context.tableSelection.columnsSelected.get(0).columnName,
                    response.size());
                countResponse.add(countRow);
                return DataSource.TableResult.get(context,
                    countResponse);
        } else {
            List<Map<String,Object>> filteredRows =
                DataSource.QueryUtils.filter(context, getRows(context));
            List<Map<String,Object>> sortedRows =
                DataSource.QueryUtils.sort(context, filteredRows);
            List<Map<String,Object>> limitedRows =
                DataSource.QueryUtils.applyLimitAndOffset(context,
                    sortedRows);
            return DataSource.TableResult.get(context, limitedRows);
        }
    }
        
    /* override global List<DataSource.TableResult> search(DataSource.SearchContext context) {
        List<DataSource.TableResult> results =
            new List<DataSource.TableResult>();
        for (DataSource.TableSelection tableSelection :
            context.tableSelections) {
            results.add(DataSource.TableResult.get(tableSelection,getRows(context)));
        }
        return results;
    }    */
        
     private List<Map<String, Object>> getRows (DataSource.QueryContext context) {
        // Get row field values for the Sample table from the external system via a callout.
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:Snowflake'); //create a named credential for the external system you are calling
        request.setMethod('POST');

        request.setHeader('accept', 'application/json');
        request.setHeader('content-type', 'application/json');
        
        Map<String, Object> bodym = new Map<String, Object>();
        bodym.put('statement','select * from ORDERTABLETEST2');
        bodym.put('database','TESTDB');
        bodym.put('schema','INFORMATION_SCHEMA');
        bodym.put('warehouse','TESTWAREHOUSE');
        String body = JSON.serialize(bodym);
        
        request.setBody(body);

        Http http = new Http();
        HttpResponse response = http.send(request);
        System.debug('response : '+response.getBody());
        // Parse the JSON response and populate the rows.
        Map<String, Object> m = (Map<String, Object>)JSON.deserializeUntyped(
                response.getBody());
        Map<String, Object> error = (Map<String, Object>)m.get('error');
        if (error != null) {
            throwException(string.valueOf(error.get('message')));
        }
        List<Map<String,Object>> rows = new List<Map<String,Object>>();
        List<Object> jsonRows = (List<Object>)m.get('data');
        if (jsonRows == null) {
           // rows.add(foundRow(m));
        } else {
            for (Object jsonRow : jsonRows) {
                Map<String,Object> row = (Map<String,Object>)jsonRow;
                rows.add(row);
            }
        }
         System.debug('rows : '+rows);
        return rows;
    }
    
}