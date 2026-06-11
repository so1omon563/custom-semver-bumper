#!/bin/bash

# Contract check: ensures every action.yml input env var is exercised in test_script.bats.
#
# Env var names are discovered dynamically from action.yml's runs.steps[].env block — no
# hardcoded list to maintain. If a new input is added to action.yml and wired through the
# env: block but no test in test_script.bats uses it (i.e. VAR=... assignment), this script
# will fail and block CI.
#
# GITHUB_TOKEN is intentionally excluded — it is handled by GitHub Actions infrastructure
# and cannot be meaningfully tested in the local test environment.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_FILE="$SCRIPT_DIR/test_script.bats"
ACTION_YML="$SCRIPT_DIR/../action.yml"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Dynamically discover env vars that action.yml passes to scripts/bump-version.sh.
# Parses lines of the form:   VARNAME: ${{ inputs.<name> }}
# GITHUB_TOKEN is excluded — it is handled by GitHub Actions infrastructure and
# cannot be meaningfully tested in the local environment.
REQUIRED_ENV_VARS=()
while IFS= read -r line; do
    REQUIRED_ENV_VARS+=("$line")
done < <(
    grep -E '^\s+[A-Z_][A-Z0-9_]+:[[:space:]]+\$\{\{[[:space:]]+inputs\.' "$ACTION_YML" \
        | sed 's/^[[:space:]]*//' \
        | cut -d: -f1 \
        | grep -v '^GITHUB_TOKEN$'
)

if [[ ${#REQUIRED_ENV_VARS[@]} -eq 0 ]]; then
    echo -e "${RED}❌ Contract check error: no env vars found in $ACTION_YML. Check the runs.steps[].env block.${NC}"
    exit 1
fi

MISSING=()

for var in "${REQUIRED_ENV_VARS[@]}"; do
    # Require the var to appear as an assignment (VAR=...) not just in a comment.
    # Match only non-comment lines where the variable is assigned, optionally via `export`.
    if ! grep -qE "^[[:space:]]*(export[[:space:]]+)?${var}=" "$TEST_FILE"; then
        MISSING+=("$var")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "${RED}❌ Contract check failed: the following action.yml inputs are not exercised in test_script.bats:${NC}"
    for var in "${MISSING[@]}"; do
        echo "   - $var"
    done
    echo ""
    echo "Add at least one test to tests/test_script.bats that uses each missing env var."
    exit 1
fi

echo -e "${GREEN}✅ Contract check passed: all action.yml inputs are referenced in test_script.bats.${NC}"
exit 0
