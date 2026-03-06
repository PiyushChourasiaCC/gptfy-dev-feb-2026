/**
 * @description Builds context packages at runtime for the AI Prompt Factory meta-prompt.
 * Simplified version without template support, using AISchemaHelper for schema discovery
 * @author Piyush Chourasia
 * @group Plumcloud Labs
 * @last modified on 03-02-2026
 * @last modified by Piyush Chourasia
 * @jira V2-7823
 */
public with sharing class AIContextAssembler {

    private static final String LOG_PREFIX = '[AIContextAssembler]';

    // System fields to skip in root field tables
    private static final Set<String> SKIP_ROOT_FIELDS = new Set<String>{
        'attributes', 'IsDeleted', 'SystemModstamp',
        'CreatedById', 'LastModifiedById', 'LastModifiedDate', 'CreatedDate',
        'LastReferencedDate', 'LastViewedDate', 'MasterRecordId',
        'PhotoUrl', 'JigsawCompanyId', 'Jigsaw', 'OwnerId',
        'BillingAddress', 'ShippingAddress',
        'BillingGeocodeAccuracy', 'BillingLatitude', 'BillingLongitude',
        'ShippingGeocodeAccuracy', 'ShippingLatitude', 'ShippingLongitude',
        'CleanStatus', 'DunsNumber', 'Tradestyle', 'NaicsCode',
        'NaicsDesc', 'YearStarted', 'DandbCompanyId', 'Sic',
        'OperatingHoursId', 'Fax'
    };

    // System fields to skip in child record output
    private static final Set<String> SKIP_CHILD_FIELDS = new Set<String>{
        'attributes', 'Id', 'IsDeleted', 'SystemModstamp',
        'CreatedById', 'LastModifiedById', 'LastModifiedDate',
        'LastReferencedDate', 'LastViewedDate', 'MasterRecordId',
        'PhotoUrl', 'OwnerId'
    };

    // Priority child objects to query (business-relevant)
    private static final Set<String> PRIORITY_CHILDREN = new Set<String>{
        'Opportunity', 'Case', 'Contact', 'Task', 'Event', 'Note',
        'OpportunityContactRole', 'AccountContactRole', 'Asset',
        'Contract', 'Order', 'OrderItem', 'Quote', 'QuoteLineItem', 'QuoteDocument',
        'Lead', 'CampaignMember', 'EmailMessage'
    };

    // Child objects where CreatedDate is meaningful
    private static final Set<String> MEANINGFUL_DATE_OBJECTS = new Set<String>{
        'Case', 'Task', 'Event', 'Note', 'EmailMessage'
    };

    private static final Integer MAX_CHILD_RECORDS = 3;
    private static final Integer MAX_SAMPLE_VALUE_LENGTH = 200;

    /**
     * @description Assemble a complete context package for the meta-prompt.
     * @param objectName Salesforce object API name (e.g., 'Account')
     * @param sampleRecordId ID of sample record for data shape discovery
     * @param businessContext User's business context description
     * @return Complete context markdown string ready for meta-prompt
     */
    public static String assembleContext(String objectName, String sampleRecordId, String businessContext) {
        // Analyze business context to detect intent and object priorities
        AIBusinessContextAnalyzer.AnalysisResult analysis = 
            AIBusinessContextAnalyzer.analyzeBusinessContext(businessContext, objectName);
        
        System.debug(LOG_PREFIX + ' Business Context Analysis: ' + analysis.analysisNotes);
        
        // Build data contract from live schema + sample data with intelligent priorities
        Map<String, Object> dataContract = buildDataContract(objectName, sampleRecordId, analysis.priorityChildObjects);

        // From-scratch mode: generate full context from schema discovery
        return buildFullContext(objectName, dataContract, businessContext);
    }

    /**
     * @description Build a data contract from live schema and sample data.
     * Returns a map with 'fields', 'children', 'sampleRecord', 'childData', 'quirks' keys.
     * @param objectName Salesforce object API name
     * @param sampleRecordId ID of sample record
     * @param priorityChildObjects List of priority child objects to include (optional)
     * @return Map containing schema and sample data
     */
    public static Map<String, Object> buildDataContract(String objectName, String sampleRecordId, List<String> priorityChildObjects) {
        Map<String, Object> contract = new Map<String, Object>();

        // Get schema info
        List<AISchemaHelper.FieldMetadata> fields = AISchemaHelper.getFields(objectName);
        List<AISchemaHelper.ChildRelationship> children = AISchemaHelper.getChildRelationships(objectName);

        contract.put('fields', fields);
        contract.put('children', children);
        contract.put('objectName', objectName);
        contract.put('priorityChildObjects', priorityChildObjects);

        // Query sample record if provided
        if (String.isNotBlank(sampleRecordId)) {
            Map<String, Object> sampleData = querySampleRecord(objectName, fields, sampleRecordId);
            contract.put('sampleRecord', sampleData.get('record'));

            // Query child records with priority filtering
            Map<String, Object> childData = querySampleChildren(
                objectName, children, sampleRecordId, priorityChildObjects
            );
            contract.put('childData', childData);

            // Detect data quirks
            Map<String, Object> sampleRecord = (Map<String, Object>) sampleData.get('record');
            List<String> quirks = detectDataQuirks(fields, sampleRecord, childData);
            contract.put('quirks', quirks);
        }

        return contract;
    }
    
    /**
     * @description Overloaded method for backward compatibility
     */
    public static Map<String, Object> buildDataContract(String objectName, String sampleRecordId) {
        return buildDataContract(objectName, sampleRecordId, null);
    }

    /**
     * @description Build markdown table of root-level fields.
     */
    public static String buildRootFieldsTable(List<AISchemaHelper.FieldMetadata> fields,
                                               Map<String, Object> sampleRecord) {
        List<String> lines = new List<String>();
        lines.add('| Field | Type | Notes |');
        lines.add('|-------|------|-------|');

        Set<String> sampleFields = sampleRecord != null
            ? sampleRecord.keySet()
            : new Set<String>();

        for (AISchemaHelper.FieldMetadata field : fields) {
            if (SKIP_ROOT_FIELDS.contains(field.name)) {
                continue;
            }
            // Only show fields present in sample data (if available)
            if (!sampleFields.isEmpty() && !sampleFields.contains(field.name)) {
                continue;
            }

            String displayType = fieldTypeDisplay(field.type);
            String notes = '';

            // Detect string-encoded booleans/numbers from sample data
            if (sampleRecord != null && sampleRecord.containsKey(field.name)) {
                Object val = sampleRecord.get(field.name);
                if (val != null) {
                    String strVal = String.valueOf(val);
                    if (field.type == 'BOOLEAN') {
                        displayType = '**string**';
                        notes = 'STRING not boolean — "true"/"false"';
                    } else if (field.type == 'CURRENCY' || field.type == 'DOUBLE' ||
                               field.type == 'INTEGER' || field.type == 'PERCENT') {
                        displayType = '**string**';
                        notes = 'STRING not number — e.g. "' + strVal + '"';
                    } else if (strVal.length() > 50) {
                        notes = 'May be long (' + strVal.length() + ' chars)';
                    }
                }
            }

            lines.add('| `' + field.name + '` | ' + displayType + ' | ' + notes + ' |');
        }

        return String.join(lines, '\n');
    }

    /**
     * @description Build child arrays section of the data contract.
     */
    public static String buildChildArraysSection(List<AISchemaHelper.ChildRelationship> children,
                                                   Map<String, Object> childData) {
        List<String> sections = new List<String>();

        for (AISchemaHelper.ChildRelationship child : children) {
            if (String.isBlank(child.relationshipName)) {
                continue;
            }

            // Only include children we have data for
            if (childData == null || !childData.containsKey(child.relationshipName)) {
                continue;
            }

            Map<String, Object> childInfo = (Map<String, Object>) childData.get(child.relationshipName);
            List<Object> records = (List<Object>) childInfo.get('records');

            if (records == null || records.isEmpty()) {
                continue;
            }

            sections.add('### ' + child.relationshipName + ' Array (' + child.childObject + ')');
            sections.add('');
            sections.add('Each record in `' + child.relationshipName + '[]`:');
            sections.add('');
            sections.add(buildChildFieldTable(records, child.childObject));
            sections.add('');
        }

        return String.join(sections, '\n');
    }

    /**
     * @description Detect data quirks from schema + sample data.
     */
    public static List<String> detectDataQuirks(List<AISchemaHelper.FieldMetadata> fields,
                                                  Map<String, Object> sampleRecord,
                                                  Map<String, Object> childData) {
        List<String> quirks = new List<String>();
        if (sampleRecord == null) {
            return quirks;
        }

        // Check for string-encoded booleans
        List<String> stringBooleans = new List<String>();
        List<String> stringNumbers = new List<String>();

        for (String fieldName : sampleRecord.keySet()) {
            Object val = sampleRecord.get(fieldName);
            if (val == null) {
                continue;
            }
            String strVal = String.valueOf(val);
            String lower = strVal.toLowerCase();

            if (lower == 'true' || lower == 'false') {
                stringBooleans.add(fieldName);
            } else if (fieldName != 'Id' && fieldName != 'Name' && isNumericString(strVal)) {
                stringNumbers.add(fieldName);
            }
        }

        if (!stringBooleans.isEmpty()) {
            List<String> shown = new List<String>();
            for (Integer i = 0; i < Math.min(3, stringBooleans.size()); i++) {
                shown.add(stringBooleans[i]);
            }
            quirks.add('**All values are strings** — booleans like ' +
                       String.join(shown, ', ') + ' are "true"/"false" strings, not actual booleans');
        }

        if (!stringNumbers.isEmpty()) {
            List<String> shown = new List<String>();
            for (Integer i = 0; i < Math.min(3, stringNumbers.size()); i++) {
                shown.add(stringNumbers[i]);
            }
            String example = String.valueOf(sampleRecord.get(stringNumbers[0]));
            quirks.add('**Numeric fields are strings** — fields like ' +
                       String.join(shown, ', ') + ' are string-typed (e.g. "' + example + '")');
        }

        // Missing fields detection
        if (fields != null) {
            Set<String> schemaNames = new Set<String>();
            for (AISchemaHelper.FieldMetadata f : fields) {
                schemaNames.add(f.name);
            }
            Set<String> sampleNames = sampleRecord.keySet();
            List<String> interestingAbsent = new List<String>();
            Set<String> systemPrefixes = new Set<String>{
                'System', 'Last', 'Created', 'Is', 'Master', 'Photo', 'Jigsaw'
            };

            for (String name : schemaNames) {
                if (!sampleNames.contains(name)) {
                    Boolean isSystem = false;
                    for (String prefix : systemPrefixes) {
                        if (name.startsWith(prefix)) {
                            isSystem = true;
                            break;
                        }
                    }
                    if (!isSystem) {
                        interestingAbsent.add(name);
                    }
                }
            }

            if (!interestingAbsent.isEmpty()) {
                List<String> shown = new List<String>();
                for (Integer i = 0; i < Math.min(5, interestingAbsent.size()); i++) {
                    shown.add(interestingAbsent[i]);
                }
                quirks.add('**Missing fields are ABSENT** — not null, the key literally doesn\'t exist. ' +
                           'Examples: ' + String.join(shown, ', '));
            }
        }

        // Data bloat detection
        if (childData != null) {
            for (String relName : childData.keySet()) {
                // Skip the __warnings__ key as it's not a child relationship
                if (relName == '__warnings__') {
                    continue;
                }
                
                Map<String, Object> childInfo = (Map<String, Object>) childData.get(relName);
                Integer count = childInfo.containsKey('count')
                    ? (Integer) childInfo.get('count') : 0;
                if (count >= 5) {
                    String childObj = childInfo.containsKey('objectName')
                        ? (String) childInfo.get('objectName') : '?';
                    quirks.add('**Potential data bloat** — ' + relName + ' (' + childObj +
                               ') has ' + count + '+ records');
                }
            }
        }

        return quirks;
    }

    /**
     * @description Build truncated sample JSON for the context file.
     */
    public static String buildSampleJson(Map<String, Object> sampleRecord,
                                           Map<String, Object> childData) {
        if (sampleRecord == null) {
            return 'No sample data available.';
        }

        Map<String, Object> output = new Map<String, Object>();

        // Add root fields (skip system fields, truncate long values)
        for (String fieldName : sampleRecord.keySet()) {
            if (SKIP_ROOT_FIELDS.contains(fieldName)) {
                continue;
            }
            Object val = sampleRecord.get(fieldName);
            if (val == null) {
                continue;
            }
            String strVal = String.valueOf(val);
            if (strVal.length() > MAX_SAMPLE_VALUE_LENGTH) {
                output.put(fieldName, strVal.substring(0, 100) + '...');
            } else {
                output.put(fieldName, val);
            }
        }

        // Add child arrays (truncated to MAX_CHILD_RECORDS)
        if (childData != null) {
            for (String relName : childData.keySet()) {
                // Skip the __warnings__ key as it's not a child relationship
                if (relName == '__warnings__') {
                    continue;
                }
                
                Map<String, Object> childInfo = (Map<String, Object>) childData.get(relName);
                List<Object> records = (List<Object>) childInfo.get('records');
                if (records == null || records.isEmpty()) {
                    continue;
                }

                List<Map<String, Object>> truncated = new List<Map<String, Object>>();
                Integer limit_i = Math.min(MAX_CHILD_RECORDS, records.size());
                for (Integer i = 0; i < limit_i; i++) {
                    Map<String, Object> rec = (Map<String, Object>) records[i];
                    Map<String, Object> cleanRec = new Map<String, Object>();
                    for (String k : rec.keySet()) {
                        if (SKIP_CHILD_FIELDS.contains(k) || rec.get(k) == null) {
                            continue;
                        }
                        Object v = rec.get(k);
                        String sv = String.valueOf(v);
                        if (sv.length() > 150) {
                            cleanRec.put(k, sv.substring(0, 80) + '...');
                        } else {
                            cleanRec.put(k, v);
                        }
                    }
                    truncated.add(cleanRec);
                }
                output.put(relName, truncated);
            }
        }

        return JSON.serializePretty(output);
    }

    // ============================================================
    // Private Helper Methods
    // ============================================================

    /**
     * @description Build full context from scratch (no template).
     */
    private static String buildFullContext(String objectName, Map<String, Object> dataContract,
                                            String businessContext) {
        List<AISchemaHelper.FieldMetadata> fields =
            (List<AISchemaHelper.FieldMetadata>) dataContract.get('fields');
        List<AISchemaHelper.ChildRelationship> children =
            (List<AISchemaHelper.ChildRelationship>) dataContract.get('children');
        Map<String, Object> sampleRecord = (Map<String, Object>) dataContract.get('sampleRecord');
        Map<String, Object> childData = (Map<String, Object>) dataContract.get('childData');
        List<String> quirks = (List<String>) dataContract.get('quirks');

        List<String> sections = new List<String>();

        // Header
        sections.add('# ' + objectName + ' 360 Context Package');
        sections.add('');
        String article = objectName.startsWith('A') || objectName.startsWith('E') ||
                         objectName.startsWith('I') || objectName.startsWith('O') ||
                         objectName.startsWith('U') ? 'an' : 'a';
        sections.add('This file provides the object-specific inputs for the meta-prompt to generate ' +
                     article + ' ' + objectName + ' 360 golden prompt.');
        sections.add('');
        sections.add('---');
        sections.add('');

        // Object type
        sections.add('## OBJECT TYPE');
        sections.add('');
        sections.add(objectName);
        sections.add('');

        // Report purpose
        sections.add('## REPORT PURPOSE');
        sections.add('');
        if (String.isNotBlank(businessContext)) {
            sections.add(businessContext);
        } else {
            sections.add(objectName + ' Intelligence — a single-page view of ' +
                        objectName.toLowerCase() + ' health, key metrics, and recommended actions.');
        }
        sections.add('');
        sections.add('---');
        sections.add('');

        // Data contract
        sections.add('## DATA CONTRACT');
        sections.add('');
        sections.add('The executing LLM receives a flat JSON object with ' + objectName +
                     ' fields at the root and child arrays nested.');
        sections.add('');
        sections.add('> **IMPORTANT**: GPTfy serializes ALL values as strings. Booleans become "true"/"false", ' +
                     'numbers become "750000.00", dates include time "2024-09-15 00:00:00".');
        sections.add('');

        // Root fields
        sections.add('### Root-Level ' + objectName + ' Fields');
        sections.add('');
        sections.add(buildRootFieldsTable(fields, sampleRecord));
        sections.add('');

        // Child arrays
        if (childData != null && !childData.isEmpty()) {
            sections.add(buildChildArraysSection(children, childData));
        }

        // Data quirks
        if (quirks != null && !quirks.isEmpty()) {
            sections.add('### Critical Data Quirks');
            sections.add('');
            for (Integer i = 0; i < quirks.size(); i++) {
                sections.add((i + 1) + '. ' + quirks[i]);
            }
            sections.add('');
        }

        sections.add('---');
        sections.add('');

        // Object-specific rules (stubs for from-scratch mode)
        sections.add('## OBJECT-SPECIFIC RULES (' + objectName + ' 360)');
        sections.add('');
        sections.add(generateRuleStubs(objectName, fields, children));
        sections.add('');
        sections.add('---');
        sections.add('');

        // Data quality warnings (from child query failures)
        if (childData != null && childData.containsKey('__warnings__')) {
            List<String> warnings = (List<String>) childData.get('__warnings__');
            if (!warnings.isEmpty()) {
                sections.add('## DATA QUALITY WARNINGS');
                sections.add('');
                sections.add('The following child objects could not be queried (permission or schema issues):');
                sections.add('');
                for (String w : warnings) {
                    sections.add('- ' + w);
                }
                sections.add('');
                sections.add('The generated prompt should handle missing data gracefully for these objects.');
                sections.add('');
                sections.add('---');
                sections.add('');
            }
        }

        // Sample data
        sections.add('## SAMPLE DATA (Auto-Generated — Truncated)');
        sections.add('');
        sections.add('This shows the JSON shape. The actual data will vary per record.');
        sections.add('');
        sections.add('```json');
        sections.add(buildSampleJson(sampleRecord, childData));
        sections.add('```');

        return String.join(sections, '\n');
    }

    /**
     * @description Query a sample record with all accessible fields.
     */
    private static Map<String, Object> querySampleRecord(String objectName,
                                                           List<AISchemaHelper.FieldMetadata> fields,
                                                           String recordId) {
        Map<String, Object> result = new Map<String, Object>();

        List<String> fieldNames = new List<String>();
        for (AISchemaHelper.FieldMetadata f : fields) {
            fieldNames.add(f.name);
        }

        // Filter to safe queryable fields
        Set<String> safeFields = AISchemaHelper.getSafeQueryableFields(objectName);
        if (!safeFields.isEmpty()) {
            List<String> filtered = new List<String>();
            for (String fn : fieldNames) {
                if (safeFields.contains(fn)) {
                    filtered.add(fn);
                }
            }
            fieldNames = filtered;
        }

        if (fieldNames.isEmpty()) {
            result.put('record', new Map<String, Object>());
            return result;
        }

        String query = 'SELECT ' + String.join(fieldNames, ', ') +
                       ' FROM ' + String.escapeSingleQuotes(objectName) +
                       ' WHERE Id = :recordId LIMIT 1';

        List<SObject> records = Database.query(query);
        if (records.isEmpty()) {
            result.put('record', new Map<String, Object>());
            return result;
        }

        // Convert SObject to flat map
        SObject record = records[0];
        Map<String, Object> recordData = new Map<String, Object>();
        for (String fieldName : fieldNames) {
            Object val = record.get(fieldName);
            if (val != null) {
                recordData.put(fieldName, val);
            }
        }
        result.put('record', recordData);

        return result;
    }

    /**
     * @description Query child records for a sample record.
     */
    private static Map<String, Object> querySampleChildren(String objectName,
                                                             List<AISchemaHelper.ChildRelationship> children,
                                                             String recordId,
                                                             List<String> priorityChildObjects) {
        Map<String, Object> childData = new Map<String, Object>();
        List<String> warnings = new List<String>();
        
        // Build priority set from provided list or use defaults
        Set<String> prioritySet = new Set<String>();
        if (priorityChildObjects != null && !priorityChildObjects.isEmpty()) {
            for (String obj : priorityChildObjects) {
                prioritySet.add(obj.toLowerCase());
            }
            System.debug(LOG_PREFIX + ' Using intelligent priority objects: ' + priorityChildObjects);
        } else {
            // Fallback to hardcoded priorities
            for (String obj : PRIORITY_CHILDREN) {
                prioritySet.add(obj.toLowerCase());
            }
            System.debug(LOG_PREFIX + ' Using default priority objects');
        }

        for (AISchemaHelper.ChildRelationship child : children) {
            if (String.isBlank(child.relationshipName)) {
                continue;
            }

            // Check if child object is in priority set or is a custom object from our namespace
            Boolean isPriority = prioritySet.contains(child.childObject.toLowerCase()) ||
                                child.childObject.startsWith(AIConstants.NAMESPACE);
            
            if (!isPriority) {
                continue;
            }

            try {
                List<AISchemaHelper.FieldMetadata> childFields = AISchemaHelper.getFields(child.childObject);
                Set<String> safeFields = AISchemaHelper.getSafeQueryableFields(child.childObject);

                List<String> childFieldNames = new List<String>();
                Boolean hasCreatedDate = false;
                for (AISchemaHelper.FieldMetadata f : childFields) {
                    if (safeFields.isEmpty() || safeFields.contains(f.name)) {
                        // Skip CreatedDate for child objects - it often can't be sorted
                        if (f.name != 'CreatedDate' || MEANINGFUL_DATE_OBJECTS.contains(child.childObject)) {
                            childFieldNames.add(f.name);
                            if (f.name == 'CreatedDate' && f.isAccessible) {
                                hasCreatedDate = true;
                            }
                        }
                    }
                }

                if (childFieldNames.isEmpty()) {
                    warnings.add(child.childObject + ': no accessible fields');
                    continue;
                }

                String query = 'SELECT ' + String.join(childFieldNames, ', ') +
                               ' FROM ' + String.escapeSingleQuotes(child.childObject) +
                               ' WHERE ' + String.escapeSingleQuotes(child.field) +
                               ' = :recordId';
                
                // Add ORDER BY only for meaningful date objects where CreatedDate is included
                if (hasCreatedDate && MEANINGFUL_DATE_OBJECTS.contains(child.childObject)) {
                    query += ' ORDER BY CreatedDate DESC';
                }
                
                query += ' LIMIT 5';
                
                List<SObject> records = Database.query(query);

                if (!records.isEmpty()) {
                    List<Object> recordList = new List<Object>();
                    for (SObject rec : records) {
                        Map<String, Object> recMap = new Map<String, Object>();
                        for (String fn : childFieldNames) {
                            Object val = rec.get(fn);
                            if (val != null) {
                                recMap.put(fn, val);
                            }
                        }
                        recordList.add(recMap);
                    }

                    Map<String, Object> childInfo = new Map<String, Object>();
                    childInfo.put('objectName', child.childObject);
                    childInfo.put('records', recordList);
                    childInfo.put('count', records.size());
                    childData.put(child.relationshipName, childInfo);
                }
            } catch (Exception e) {
                String errMsg = child.childObject + ': ' + e.getMessage();
                warnings.add(errMsg);
                System.debug(LOG_PREFIX + ' Skipping child ' + errMsg);
            }
        }

        // Store warnings in the result map for downstream consumption
        if (!warnings.isEmpty()) {
            childData.put('__warnings__', warnings);
        }

        return childData;
    }

    /**
     * @description Build a field table for child records.
     */
    private static String buildChildFieldTable(List<Object> records, String childObjectName) {
        List<String> lines = new List<String>();
        lines.add('| Field | Type | Notes |');
        lines.add('|-------|------|-------|');

        // Collect all field names from sample records
        Set<String> allFields = new Set<String>();
        for (Object recObj : records) {
            Map<String, Object> rec = (Map<String, Object>) recObj;
            allFields.addAll(rec.keySet());
        }

        // Remove system fields, but keep CreatedDate for meaningful objects
        Set<String> skipFields = new Set<String>(SKIP_CHILD_FIELDS);
        if (!MEANINGFUL_DATE_OBJECTS.contains(childObjectName)) {
            skipFields.add('CreatedDate');
        }

        List<String> displayFields = new List<String>();
        for (String f : allFields) {
            if (!skipFields.contains(f)) {
                displayFields.add(f);
            }
        }
        displayFields.sort();

        for (String field : displayFields) {
            String displayType = 'string';
            String notes = '';

            // Check how many records have this field
            Integer presentCount = 0;
            for (Object recObj : records) {
                Map<String, Object> rec = (Map<String, Object>) recObj;
                if (rec.containsKey(field) && rec.get(field) != null) {
                    presentCount++;
                }
            }
            if (presentCount < records.size()) {
                notes = 'May be ABSENT';
            }

            lines.add('| `' + field + '` | ' + displayType + ' | ' + notes + ' |');
        }

        return String.join(lines, '\n');
    }

    /**
     * @description Map Salesforce schema types to display types.
     */
    private static String fieldTypeDisplay(String schemaType) {
        if (String.isBlank(schemaType)) {
            return 'unknown';
        }
        // GPTfy serializes ALL values as strings
        Map<String, String> mapping = new Map<String, String>{
            'STRING' => 'string',
            'TEXTAREA' => 'string',
            'PHONE' => 'string',
            'EMAIL' => 'string',
            'URL' => 'string',
            'ID' => 'string',
            'REFERENCE' => 'string (ID)',
            'BOOLEAN' => 'string',
            'CURRENCY' => 'string',
            'DOUBLE' => 'string',
            'INTEGER' => 'string',
            'PERCENT' => 'string',
            'DATE' => 'string',
            'DATETIME' => 'string',
            'PICKLIST' => 'string',
            'MULTIPICKLIST' => 'string',
            'COMBOBOX' => 'string'
        };
        return mapping.containsKey(schemaType) ? mapping.get(schemaType) : schemaType.toLowerCase();
    }

    /**
     * @description Generate rules for from-scratch mode.
     */
    private static String generateRuleStubs(String objectName,
                                               List<AISchemaHelper.FieldMetadata> fields,
                                               List<AISchemaHelper.ChildRelationship> children) {
        String prefix = objectName.length() >= 3
            ? objectName.substring(0, 3).toUpperCase()
            : objectName.toUpperCase();

        // Classify fields by type for schema-aware rules
        List<String> currencyFields = new List<String>();
        List<String> numberFields = new List<String>();
        List<String> dateFields = new List<String>();
        List<String> picklistFields = new List<String>();
        List<String> booleanFields = new List<String>();

        for (AISchemaHelper.FieldMetadata f : fields) {
            if (!f.isAccessible || SKIP_ROOT_FIELDS.contains(f.name)) continue;
            if (f.type == 'CURRENCY') currencyFields.add(f.name);
            else if (f.type == 'DOUBLE' || f.type == 'INTEGER' || f.type == 'PERCENT') numberFields.add(f.name);
            else if (f.type == 'DATE' || f.type == 'DATETIME') dateFields.add(f.name);
            else if (f.type == 'PICKLIST') picklistFields.add(f.name);
            else if (f.type == 'BOOLEAN') booleanFields.add(f.name);
        }

        // Collect child object names
        List<String> childNames = new List<String>();
        for (AISchemaHelper.ChildRelationship child : children) {
            if (String.isNotBlank(child.relationshipName) && PRIORITY_CHILDREN.contains(child.childObject)) {
                childNames.add(child.childObject);
            }
        }

        List<String> rules = new List<String>();

        // Object-specific rules generated from schema analysis
        rules.add('### Report Identity\n');
        rules.add('[' + prefix + '-ID-1] Report type: ' + objectName + ' 360 Intelligence Report');
        rules.add('[' + prefix + '-ID-2] Header label: ' + objectName.toUpperCase() + ' INTELLIGENCE');
        rules.add('[' + prefix + '-ID-3] Header metadata: Show record Name + key status fields\n');

        // Schema-aware KPI rules
        rules.add('### KPI Definitions\n');
        Integer kpiNum = 1;
        if (!currencyFields.isEmpty()) {
            rules.add('[' + prefix + '-KPI-' + kpiNum++ + '] Primary value metric: ' + currencyFields[0] + ' formatted as currency');
        }
        if (!numberFields.isEmpty()) {
            String numSample = numberFields.size() > 1 ? numberFields[0] + ', ' + numberFields[1] : numberFields[0];
            rules.add('[' + prefix + '-KPI-' + kpiNum++ + '] Numeric metrics from fields: ' + numSample);
        }
        if (!picklistFields.isEmpty()) {
            rules.add('[' + prefix + '-KPI-' + kpiNum++ + '] Status indicator from: ' + picklistFields[0] + ' (color-coded badge)');
        }
        if (!dateFields.isEmpty()) {
            rules.add('[' + prefix + '-KPI-' + kpiNum++ + '] Age/timeline metric: today minus ' + dateFields[0] + ' (days)');
        }
        if (!childNames.isEmpty()) {
            rules.add('[' + prefix + '-KPI-' + kpiNum++ + '] Child record count: COUNT(' + childNames[0] + ')');
        }
        rules.add('[' + prefix + '-KPI-' + kpiNum + '] Each KPI: large number on top, uppercase label below, variant color for risk states\n');

        // Schema-aware segmentation rules
        if (!picklistFields.isEmpty()) {
            rules.add('### Segmentation Rules\n');
            for (Integer i = 0; i < Math.min(picklistFields.size(), 3); i++) {
                rules.add('[' + prefix + '-SEG-' + (i + 1) + '] Group or badge by ' + picklistFields[i] + ' values. Use distinct colors per value.');
            }
            rules.add('');
        }

        // Schema-aware date/aging rules
        if (!dateFields.isEmpty()) {
            rules.add('### Date & Aging Rules\n');
            for (Integer i = 0; i < Math.min(dateFields.size(), 3); i++) {
                rules.add('[' + prefix + '-AGE-' + (i + 1) + '] Calculate age from ' + dateFields[i] + ': "X days old/ago/since". Flag if > 30 days.');
            }
            rules.add('');
        }

        // Schema-aware cross-reference rules if child objects exist
        if (!childNames.isEmpty()) {
            rules.add('### Cross-Reference Analysis\n');
            rules.add('[' + prefix + '-XREF-1] Analyze child ' + String.join(childNames, ', ') + ' for patterns and trends');
            if (childNames.size() >= 2) {
                rules.add('[' + prefix + '-XREF-2] Connect insights across ' + childNames[0] + ' and ' + childNames[1] + ' (e.g., link activity to outcomes)');
            }
            rules.add('');
        }

        // Embed universal rules inline (critical guardrails)
        rules.add('---\n');
        rules.add('## UNIVERSAL RULES (Apply to ALL reports)\n');

        // Anti-Hallucination
        rules.add('### Anti-Hallucination (STRICT)\n');
        rules.add('[U-STRICT-1] NEVER invent, fabricate, or mock any Salesforce records. If a data array is empty or missing, show "No [records] on record" and display 0 or $0 in KPI cards.');
        rules.add('[U-STRICT-2] The LLM MAY generate narrative content for: company profile, strategic insights, strength/risk bullets, and recommendations. Narrative must be grounded in available data and NEVER contradict Salesforce data.');
        rules.add('[U-STRICT-3] If a structured data section has zero records: show the section header, display "No [records] on record", show $0/0 in KPI. Do NOT skip the section.');
        rules.add('[U-STRICT-4] BEFORE building any table or metric, COUNT the records. If output row count does not match data record count, the LLM has DROPPED data — fix before outputting.\n');

        // Type Handling
        rules.add('### Type Handling\n');
        rules.add('[U-TYPE-1] IsClosed is a STRING "true"/"false", not a boolean. Check: IF IsClosed = "false" OR IsClosed = false.');
        rules.add('[U-TYPE-2] Amount and numeric fields are STRINGS (e.g., "750000.00"). Use parseFloat() for arithmetic. May be ABSENT.');
        rules.add('[U-TYPE-3] Dates include time: "2024-09-15 00:00:00". Handle this format in date comparisons.');
        rules.add('[U-TYPE-4] When a field has no value, the key is ABSENT from JSON — not null, not "". Check "if missing or null".\n');

        // Forbidden Language
        rules.add('### Forbidden Language\n');
        rules.add('[U-LANG-1] BANNED phrases (zero tolerance): "follow up" (all forms), "touch base", "ensure alignment", "circle back", "engage stakeholders", "maintain momentum", "consider scheduling", "reinforce value proposition", "reach out to", "address concerns", "leverage" (verb), "synergy", "utilize", "proactive/proactively"');
        rules.add('[U-LANG-2] REPLACEMENTS: Use strong verbs — Schedule, Review, Present, Resolve, Negotiate, Brief, Prepare, Confirm, Deliver, Escalate. Every action must name specific data.\n');

        // Date Analysis
        rules.add('### Date Analysis\n');
        rules.add('[U-DATE-1] Use today\'s date as EVALUATION_DATE for ALL date calculations.');
        rules.add('[U-DATE-2] Include AT LEAST 5 date calculations. Each MUST use keywords AFTER number+unit: "old", "overdue", "ago", "since", "open". Example: "15 days old" not just "15 days".\n');

        // Design System
        rules.add('### Design System (Professional Navy)\n');
        rules.add('[U-DESIGN-1] Bloomberg financial intelligence style: clean, authoritative, minimalistic. Navy blue (#1e3a5f) accent.');
        rules.add('[U-DESIGN-2] Palette: Navy #1e3a5f, Dark text #111827, Secondary #64748b, Borders #e2e8f0, Light bg #f8fafc');
        rules.add('[U-DESIGN-3] Status colors: Critical bg #fef2f2 text #dc2626 border #fecaca. Caution bg #fff7ed text #c2410c. Healthy bg #f0fdf4 text #166534.');
        rules.add('[U-DESIGN-4] KPI cards: flex row with gap 1.5rem, each flex:1. Status badges: border-radius 4px (NOT 12px).');
        rules.add('[U-DESIGN-5] Strength vs Risk: side-by-side cards. Strengths bg #f0fdf4 (green). Risks bg #fef2f2 (red). NEVER both gray.\n');

        // Analytical Depth
        rules.add('### Analytical Depth\n');
        rules.add('[U-DEPTH-1] The output MUST contain analytical statements connecting multiple data points. Use: "suggests", "indicates", "despite", "combined with", "risk of", "pattern of", "momentum".');
        rules.add('[U-DEPTH-2] READ Description fields and extract themes/conversation topics. Do NOT just list subjects — synthesize meaning.');
        rules.add('[U-DEPTH-3] Every recommendation MUST reference a specific record name, dollar amount, date, or contact. Generic advice is forbidden.');
        rules.add('[U-DEPTH-4] Assessment sections MUST connect insights across multiple data arrays (e.g., linking case trends to opportunity risk).\n');

        // Output Format
        rules.add('### Output Format\n');
        rules.add('[U-FORMAT-1] Single continuous HTML string. Inline CSS only. No <style> tags, no line breaks, no markdown, no backticks.');
        rules.add('[U-FORMAT-2] Output MUST start with: <div style="font-family: \'Helvetica Neue\', Arial, sans-serif; max-width: 1200px; margin: 0 auto; padding: 1.5rem; background: #ffffff; color: #2c3e50;">');

        return String.join(rules, '\n');
    }

    /**
     * @description Check if a string looks numeric.
     */
    private static Boolean isNumericString(String s) {
        if (String.isBlank(s)) {
            return false;
        }
        Boolean hasDot = false;
        for (Integer i = 0; i < s.length(); i++) {
            String ch = s.substring(i, i + 1);
            if (i == 0 && ch == '-') {
                continue;
            }
            if (ch == '.' && !hasDot) {
                hasDot = true;
                continue;
            }
            if (ch < '0' || ch > '9') {
                return false;
            }
        }
        return true;
    }

    /**
     * @description Custom exception for context assembly errors.
     */
    public class AIContextAssemblerException extends Exception {}
}
