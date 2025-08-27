For scripts in osx-run/tests use Bash with set -Eeuo pipefail
No comments allowed in any code
testing/run-tests.sh creates isolated HOME and OSX_ROOT for each test and removes them
Run shellcheck on osx-run/osx-run.sh testing/run-tests.sh and osx-run/tests/*.sh
testing/run-tests.sh executes tests and stores logs in artifacts
