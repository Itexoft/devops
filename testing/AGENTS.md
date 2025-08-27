run-tests.sh is bash with set -Eeuo pipefail and no comments
Set TRACE=1 to trace test execution
First argument directory runs all *.sh; otherwise run specified scripts
Use INSTALL or SQUID to point to scripts under test
Creates isolated HOME and OSX_ROOT for each test and removes them
