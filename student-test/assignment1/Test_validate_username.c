#include "../../examples/autotest-validate/autotest-validate.h"
#include "../../assignment-autotest/test/assignment1/username-from-conf-file.h"
#include "unity.h"

 HEAD

/**
* This function should:
*   1) Call the my_username() function in Test_assignment_validate.c to get your hard coded username.
*   2) Obtain the value returned from function malloc_username_from_conf_file() in username-from-conf-file.h within
*       the assignment autotest submodule at assignment-autotest/test/assignment1/
*   3) Use unity assertion TEST_ASSERT_EQUAL_STRING_MESSAGE the two strings are equal.  See
*       the [unity assertion reference](https://github.com/ThrowTheSwitch/Unity/blob/master/docs/UnityAssertionsReference.md)
*/
 assignments-base/assignment2
void test_validate_my_username()
{
    const char *expected = my_username();
    const char *actual = malloc_username_from_conf_file();
    TEST_ASSERT_EQUAL_STRING_MESSAGE(expected, actual, "Username mismatch between config and source");
}

