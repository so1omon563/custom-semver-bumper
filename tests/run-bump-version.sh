#!/usr/bin/env bash
# Thin runner for scripts/bump-version.sh.
#
# When COVERAGE_DIR is set, wraps the script with kcov so that each
# individual test invocation is instrumented directly. This bypasses the
# kcov subprocess-tracking limitation where bats clears BASH_ENV before
# spawning child processes, which prevents coverage data from reaching
# the production script when kcov wraps bats at the top level.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${REPO_ROOT}/scripts/bump-version.sh"

if [ -n "${COVERAGE_DIR:-}" ] && command -v kcov >/dev/null 2>&1; then
    # Run the script directly (not via 'bash script') so kcov reads the shebang
    # and activates its bash-script engine rather than treating bash as an ELF binary.
    exec kcov \
         --include-path="${SCRIPT_PATH}" \
         "${COVERAGE_DIR}" \
         "${SCRIPT_PATH}"
else
    exec bash "${SCRIPT_PATH}"
fi
