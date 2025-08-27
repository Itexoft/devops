For scripts in osx-install/tests use Bash with set -Eeuo pipefail
No comments allowed in any code
run-tests.sh creates isolated HOME and OSX_ROOT for each test and removes them
Run shellcheck on osx-install/osx-install.sh run-tests.sh and osx-install/tests/*.sh
run-tests.sh executes tests and stores logs in artifacts
