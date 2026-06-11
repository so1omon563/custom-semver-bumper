#!/bin/bash

# GitHub Action Test Suite
# Comprehensive test runner for the Custom Version Bumper Action

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results tracking
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0

print_header() {
    echo -e "\n${BLUE}================================${NC}"
    echo -e "${BLUE}  Custom Version Bumper Tests  ${NC}"
    echo -e "${BLUE}================================${NC}\n"
}

print_section() {
    echo -e "\n${YELLOW}--- $1 ---${NC}"
}

print_result() {
    local test_name="$1"
    local exit_code="$2"
    local test_count="$3"
    
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✓ $test_name passed ($test_count tests)${NC}"
        TOTAL_PASSED=$((TOTAL_PASSED + test_count))
    else
        echo -e "${RED}✗ $test_name failed${NC}"
        TOTAL_FAILED=$((TOTAL_FAILED + test_count))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + test_count))
}

run_test_suite() {
    local test_file="$1"
    local test_name="$2"
    
    # Use absolute path
    local full_path="$SCRIPT_DIR/$test_file"
    
    if [[ -f "$full_path" ]]; then
        echo -e "Running $test_name..."
        
        # Make test file executable
        chmod +x "$full_path"
        
        # Capture output so we can both parse counts and re-display on failure.
        # test.sh and integration_test.sh emit "Tests passed: N" / "Tests failed: M"
        # lines; parse those for accurate per-test counts.
        # set +e so a non-zero exit from the suite (or from grep finding no matches)
        # does not trigger the top-level `set -e` and kill the runner prematurely.
        local suite_output exit_code
        set +e
        suite_output=$("$full_path" 2>&1)
        exit_code=$?
        set -e

        # Strip ANSI colour codes before parsing so colour-wrapped numbers are readable.
        # sed is required here; ${var//pattern} cannot match ESC[...m sequences.
        local clean_output
        # shellcheck disable=SC2001
        clean_output=$(sed $'s/\033\\[[0-9;]*m//g' <<< "$suite_output")

        local passed failed
        passed=$(echo "$clean_output" | grep -oE 'Tests passed: [0-9]+' | grep -oE '[0-9]+$' | tail -1)
        failed=$(echo "$clean_output"  | grep -oE 'Tests failed: [0-9]+' | grep -oE '[0-9]+$' | tail -1)

        # Fall back to counting function calls if the script doesn't emit those lines
        if [[ -z "$passed" && -z "$failed" ]]; then
            local total
            total=$(grep -c "run_test\|run_integration_test" "$full_path" 2>/dev/null || echo "1")
            if [[ $exit_code -eq 0 ]]; then
                passed=$total; failed=0
            else
                passed=0; failed=$total
            fi
        fi
        passed=${passed:-0}
        failed=${failed:-0}
        local total=$(( passed + failed ))

        TOTAL_TESTS=$((TOTAL_TESTS   + total))
        TOTAL_PASSED=$((TOTAL_PASSED + passed))
        TOTAL_FAILED=$((TOTAL_FAILED + failed))

        if [[ $exit_code -eq 0 ]]; then
            echo -e "${GREEN}✓ $test_name passed ($total tests)${NC}"
        else
            echo -e "${RED}✗ $test_name: $failed of $total tests failed${NC}"
            echo -e "${RED}Detailed output:${NC}"
            printf '%s\n' "$suite_output" | sed 's/^/  /'
        fi
    else
        echo -e "${RED}✗ $test_name: Test file not found: $full_path${NC}"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    fi
}

check_dependencies() {
    local missing_deps=()
    
    # Check for Git
    if ! command -v git &> /dev/null; then
        missing_deps+=("git")
    fi
    
    # Check for BATS (optional)
    if ! command -v bats &> /dev/null; then
        echo -e "${YELLOW}⚠ BATS not found. Skipping BATS tests.${NC}"
        echo -e "  Install with: ${BLUE}brew install bats-core${NC} (macOS) or see https://github.com/bats-core/bats-core"
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}Missing dependencies: ${missing_deps[*]}${NC}"
        echo "Please install the missing dependencies and try again."
        exit 1
    fi
}

# Main execution
print_header

# Check dependencies
check_dependencies

# Change to tests directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

print_section "Running Contract Check"
chmod +x "$SCRIPT_DIR/check_contract.sh"
contract_exit=0
if ! "$SCRIPT_DIR/check_contract.sh"; then
    contract_exit=1
fi
print_result "Contract Check" $contract_exit "1"

print_section "Running Unit Tests"
run_test_suite "test.sh" "Unit Tests"

print_section "Running Integration Tests"
run_test_suite "integration_test.sh" "Integration Tests"

# Run BATS tests if available
if command -v bats &> /dev/null; then
    # run_bats_file <file> <label>
    run_bats_file() {
        local bats_file="$1"
        local label="$2"
        if [[ -f "$bats_file" ]]; then
            echo "Running $label..."
            # TAP output gives one "ok N - desc" or "not ok N - desc" line per test,
            # so we can count exact pass/fail rather than treating the suite as binary.
            # set +e so that a non-zero bats exit code (test failures) or a grep exit
            # code of 1 (no matches found) does not trigger the top-level `set -e`.
            local tap_output bats_exit_code passed failed
            set +e
            tap_output=$(bats --tap "$bats_file" 2>&1)
            bats_exit_code=$?
            passed=$(echo "$tap_output" | grep -c "^ok ")
            failed=$(echo "$tap_output"  | grep -c "^not ok ")
            set -e
            local total=$(( passed + failed ))

            TOTAL_TESTS=$((TOTAL_TESTS   + total))
            TOTAL_PASSED=$((TOTAL_PASSED + passed))
            TOTAL_FAILED=$((TOTAL_FAILED + failed))

            if [[ $bats_exit_code -eq 0 ]]; then
                echo -e "${GREEN}✓ $label passed ($total tests)${NC}"
            else
                echo -e "${RED}✗ $label: $failed of $total tests failed${NC}"
                echo -e "${RED}Detailed BATS output:${NC}"
                # Re-run in pretty mode for human-readable failure details
                bats "$bats_file" 2>&1 | sed 's/^/  /'
            fi
        else
            echo -e "${RED}✗ $label: $bats_file not found${NC}"
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
        fi
    }

    print_section "Running BATS Tests (helper functions)"
    run_bats_file "$SCRIPT_DIR/test.bats" "BATS Tests (helper functions)"

    print_section "Running BATS Script Tests (production script)"
    run_bats_file "$SCRIPT_DIR/test_script.bats" "BATS Script Tests (production script)"
fi

# Print final summary
echo -e "\n${BLUE}================================${NC}"
echo -e "${BLUE}        Test Summary            ${NC}"
echo -e "${BLUE}================================${NC}"
echo -e "Total tests run: $TOTAL_TESTS"
echo -e "Tests passed: ${GREEN}$TOTAL_PASSED${NC}"
echo -e "Tests failed: ${RED}$TOTAL_FAILED${NC}"

if [[ $TOTAL_FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}🎉 All tests passed! The Custom Version Bumper Action is working correctly.${NC}"
    exit 0
else
    echo -e "\n${RED}😞 Some tests failed. Please review the failures above.${NC}"
    exit 1
fi
