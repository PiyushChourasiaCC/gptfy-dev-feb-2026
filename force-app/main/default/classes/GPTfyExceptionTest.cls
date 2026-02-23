@isTest 
private with sharing class GPTfyExceptionTest {
    @isTest 
    private static void testCustomException(){
        test.startTest();
        GPTfyException objExcep = new GPTfyException();
        GPTfyException.log(objExcep, 'ExceptionUnitTestApplication', 'ExceptionUnitTestModule', 'ExceptionUnitTestClass', 'ExceptionUnitTestMethod','SupportData');
        System.assertNotEquals(null, objExcep);
        test.stopTest();
    }
}