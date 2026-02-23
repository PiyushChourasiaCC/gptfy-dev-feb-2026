/**
 * @description:
 *   AIAgenticInterface defines the contract for any agentic handler class responsible for
 *   processing or executing generic AI agent function calls.
 *   Implementations must handle invocation requests based on method name and input parameters,
 *   supporting a standardized execution pattern for AI agentic operations.
 *
 *   Optional example (commented out) for fuzzy search method signature is provided for extensibility.
 *
 * @author              : Piyush Chourasia
 * @group               : Plumcloud Labs
 * @last modified on    : 30-07-2025
 * @last modified by    : Piyush Chourasia
 */
global interface AIAgenticInterface {
    /**
     * @description
     *   Executes a handler method based on provided method name and input parameters.
     *   Implementing classes must provide supported logic as per methodName and should handle
     *   parameter validation and error signaling.
     *
     * @param methodName      The name of the operation or function to execute.
     * @param parameters      Input map containing parameters for the execution.
     * @return String         A JSON-encoded response representing the result (success/error).
     */
    String executeMethod(String methodName, Map<String, Object> parameters);
    // String doFuzzySearch(String searchTerm, List<String> objectsToSearch, String fieldToSearchIn, Map<String,String> returnFields){
    //     Map<String, Object> resultsMap = new Map<String, Object>();
    //     List<String> returningClauses = new List<String>();

    //     for (String objName : objectsToSearch) {
    //         if (!returnFields.containsKey(objName)) {
    //             continue;
    //         }
    //         String returnFields = returnFields.get(objName);
            
    //         returningClauses.add(
    //             objName + '(' + returnFields + ')'
    //         );
    //     }

    //     String sosl = 'FIND \'' + searchTerm + '\' IN ' + fieldToSearchIn +
    //             ' FIELDS RETURNING ' + String.join(returningClauses, ',');

    //     List<List<SObject>> searchList = Search.query(sosl);

    //     Boolean hasSomeResult = false;
    //     for(List<SObject> obj : searchList){
    //         if(obj.size() > 0){
    //             hasSomeResult = true;
    //             break;
    //         }
    //     }
    //     if(hasSomeResult == true){
    //         return JSON.serialize(new Map<String,Object> {
    //             'message' => 'Found these results maching your search term.',
    //             'records' => searchList
    //         });
    //     }
    //     return JSON.serialize(new Map<String,Object> {
    //         'message' => 'Found no Results maching your search term'
    //     });
    // }
}