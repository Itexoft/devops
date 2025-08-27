For scripts in osx-run/tests use Bash with set -Eeuo pipefail
No comments allowed in any code
osx-run/tests/run-tests.sh and squid-cache/tests/run-tests.sh create isolated HOME and OSX_ROOT for each test and remove them
Run shellcheck on osx-run/osx-run.sh osx-run/tests/*.sh squid-cache/squid-cache.sh squid-cache/tests/*.sh testing/stub-env.sh
GitHub Action runs shellcheck and tests on push and pull requests
