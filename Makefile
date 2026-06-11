# Makefile for Custom Version Bumper Action

.PHONY: test-all test-unit test-integration test-bats test-script check-contract coverage shellcheck clean install-deps help setup

# Default target
help:
	@echo "Available targets:"
	@echo "  test-all         - Run all tests (includes contract check)"
	@echo "  test-unit        - Run unit tests only"
	@echo "  test-integration - Run integration tests only"
	@echo "  test-bats        - Run BATS helper-function tests only (requires bats-core)"
	@echo "  test-script      - Run BATS script-level tests only (requires bats-core)"
	@echo "  check-contract   - Check all action.yml inputs are tested in test_script.bats"
	@echo "  coverage         - Measure bump-version.sh coverage with kcov (requires kcov, Linux)"
	@echo "  shellcheck       - Run shellcheck on all shell scripts"
	@echo "  install-deps     - Install test dependencies (macOS)"
	@echo "  setup            - Make test files executable"
	@echo "  clean            - Clean up temporary files"
	@echo "  help             - Show this help message"

# Run all tests
test-all:
	@echo "Running all tests..."
	cd tests && ./run_tests.sh

# Run unit tests only
test-unit:
	@echo "Running unit tests..."
	cd tests && ./test.sh

# Run integration tests only
test-integration:
	@echo "Running integration tests..."
	cd tests && ./integration_test.sh

# Run BATS tests only
test-bats:
	@echo "Running BATS tests (helper functions)..."
	cd tests && bats test.bats

# Run BATS script-level tests only
test-script:
	@echo "Running BATS script-level tests (production script)..."
	cd tests && bats test_script.bats

# Check that all action.yml inputs are exercised in test_script.bats
check-contract:
	@chmod +x tests/check_contract.sh
	@tests/check_contract.sh

# Measure line coverage of scripts/bump-version.sh using kcov (Linux only)
# Install: sudo apt-get install kcov
# Usage:   make coverage              (generates coverage/index.html)
#          COVERAGE_THRESHOLD=80 make coverage  (override default 70% threshold)
COVERAGE_THRESHOLD ?= 70
coverage:
	@command -v kcov >/dev/null 2>&1 \
		|| { echo "kcov not found (Linux only). Install: sudo apt-get install kcov"; exit 1; }
	@echo "Running kcov coverage (threshold: $(COVERAGE_THRESHOLD)%)..."
	@rm -rf coverage/
	@# Each test invocation is wrapped by kcov individually via tests/run-bump-version.sh.
	@# This bypasses the limitation where kcov loses bash instrumentation when
	@# bats clears BASH_ENV before spawning child processes.
	@COVERAGE_DIR=$(CURDIR)/coverage bats tests/test_script.bats
	@echo "Coverage report: coverage/ (open coverage/*/index.html in a browser)"
	@COVERAGE=$$(find coverage -name 'cobertura.xml' 2>/dev/null \
		| xargs -r grep -l 'bump-version' 2>/dev/null \
		| head -1 \
		| xargs -r grep -oP 'line-rate="\K[0-9.]+' 2>/dev/null \
		| head -1 \
		| awk '{printf "%d", $$1 * 100}'); \
	if [ -z "$$COVERAGE" ]; then \
		echo "Warning: could not determine coverage percentage from cobertura.xml"; \
	elif [ "$$COVERAGE" -lt "$(COVERAGE_THRESHOLD)" ]; then \
		echo "Coverage $$COVERAGE% is below threshold $(COVERAGE_THRESHOLD)% — failing"; \
		exit 1; \
	else \
		echo "Coverage $$COVERAGE% meets threshold $(COVERAGE_THRESHOLD)%"; \
	fi

# Run shellcheck on all shell scripts
shellcheck:
	@echo "Running shellcheck..."
	@shellcheck scripts/bump-version.sh tests/test.sh tests/test_helpers.sh tests/run_tests.sh tests/check_contract.sh
	@shellcheck --external-sources --exclude=SC2317 tests/integration_test.sh
	@echo "shellcheck passed."

# Install test dependencies on macOS
install-deps:
	@echo "Installing test dependencies..."
	@if command -v brew >/dev/null 2>&1; then \
		echo "Installing bats-core via Homebrew..."; \
		brew install bats-core; \
	else \
		echo "Homebrew not found. Please install manually:"; \
		echo "https://github.com/bats-core/bats-core#installation"; \
	fi

# Clean up temporary files
clean:
	@echo "Cleaning up..."
	@find tests -name "*.tmp" -delete 2>/dev/null || true
	@find . -name ".DS_Store" -delete 2>/dev/null || true
	@rm -rf coverage/

# Make test files executable
setup:
	@echo "Setting up test files..."
	chmod +x tests/*.sh
	@echo "Test files are ready to run."
