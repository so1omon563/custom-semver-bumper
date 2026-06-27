# Test Documentation for Custom Version Bumper Action

This directory contains comprehensive unit and integration tests for the Custom Version Bumper GitHub Action.

## Test Structure

### Files Overview

| File | Tests | Invokes `scripts/bump-version.sh`? | Uses real Git? |
|---|---|---|---|
| `test.sh` | Unit tests — core logic in isolation | ❌ No | ❌ No |
| `integration_test.sh` | Integration + smoke tests in real Git repos | ✅ Yes (smoke tests) | ✅ Yes |
| `test.bats` | BATS tests for helper functions | ❌ No (tests `test_helpers.sh`) | ✅ Yes |
| `test_script.bats` | BATS tests that invoke the production script | ✅ Yes | ✅ Yes |
| `check_contract.sh` | Contract check: all action.yml inputs covered | — | — |
| `test_helpers.sh` | Shared helper functions used by tests | — | — |
| `run_tests.sh` | Main test runner that executes all test suites | — | — |

> **Note**: `test.bats` tests the helper functions from `test_helpers.sh`, not the
> production script. `test_script.bats` is the BATS suite that directly invokes
> `scripts/bump-version.sh` as a subprocess and asserts on its real side effects.

## Coverage Enforcement

Three mechanisms protect against new functionality being added without tests:

### 1. Input Contract Check (`check_contract.sh`)

Asserts that every `action.yml` input env var (`MOVE_MAJOR_TAG`, `MARKER_STYLE`, etc.)
is referenced in `test_script.bats`. Runs automatically as part of `run_tests.sh` and
as a standalone `make check-contract` target.

If a new input is added to `action.yml` without a corresponding test, CI fails with a
clear message listing the untested inputs.

### 2. Line Coverage Gate (kcov — Linux/CI only)

`kcov` instruments `scripts/bump-version.sh` as it is called by `test_script.bats`,
measuring which lines are actually executed. CI enforces a minimum threshold (currently
**70%**) — if new code branches are added without tests, coverage drops and the
`coverage` CI job fails.

```bash
# Run locally (Linux only — install with: sudo apt-get install kcov)
make coverage

# Override threshold
COVERAGE_THRESHOLD=80 make coverage
```

HTML coverage reports are uploaded as a CI artifact after each run.

### 3. ShellCheck Static Analysis

`make shellcheck` runs ShellCheck across all shell scripts including `check_contract.sh`,
catching syntax errors, undefined variables, and common scripting pitfalls before they
reach tests.

## Running Tests

### Quick Start

To run all tests at once:

```bash
cd tests/
./run_tests.sh
```

### Individual Test Suites

Run specific test suites:

```bash
# Unit tests only
./test.sh

# Integration tests only
./integration_test.sh

# BATS helper-function tests (requires bats-core)
bats test.bats

# BATS script-level tests — invokes bump-version.sh directly (requires bats-core)
bats test_script.bats

# Contract check only (no dependencies required)
./check_contract.sh

# Coverage report — Linux only, requires kcov
make coverage
```

## Test Categories

### Unit Tests (`test.sh`)

Tests the core version bumping logic in isolation:

- **Version Parsing**: Correctly parsing semantic version strings
- **Patch Bumping**: Default behavior when no tags are present
- **Minor Bumping**: When `#minor` is found in commit messages
- **Major Bumping**: When `#major` is found in commit messages
- **Case Sensitivity**: Handling uppercase/lowercase tags
- **Edge Cases**: Zero versions, large numbers, multiple keywords
- **Major Tag Extraction**: Getting major version number from version strings

**Example test cases:**

- `1.2.3` + `"Fix bug"` → `1.2.4` (patch)
- `1.2.3` + `"Add feature #minor"` → `1.3.0` (minor)
- `1.2.3` + `"Breaking change #major"` → `2.0.0` (major)

### Integration Tests (`integration_test.sh`)

Tests the action in realistic Git repository scenarios:

- **No Existing Tags**: Starting from scratch (`v0.0.0`)
- **With Existing Tags**: Getting latest tag from repository
- **Tag Creation**: Actually creating Git tags
- **Major Tag Movement**: Moving major tags to point to latest versions
- **Commit Message Parsing**: Reading merge commit messages
- **Git Configuration**: Setting up Git user name and email
- **Version Parsing Edge Cases**: Handling various version formats
- **Smoke Tests**: Call `scripts/bump-version.sh` directly as a subprocess

### BATS Helper Tests (`test.bats`)

Modern testing framework tests for the helper functions in `test_helpers.sh`:

- **Structured Test Cases**: Clear test organization with setup/teardown
- **Isolated Test Environment**: Each test runs in a clean temporary Git repository
- **Detailed Assertions**: More granular test validation
- **Better Error Reporting**: Clear failure messages

### BATS Script Tests (`test_script.bats`)

Directly invokes `scripts/bump-version.sh` as a subprocess in real isolated Git
repositories. These tests verify the **actual production script** behaves correctly
end-to-end, not just the helper functions.

Scenarios covered:

- **Baseline**: No existing tags → starts at `v0.0.1`
- **Hashtag markers**: Patch (default), `#minor`, `#major`, `#skip`
- **Conventional Commits**: `feat:` → minor, `fix:` → patch, `feat!:` → major
- **Pre-release**: `#prerelease:alpha` creates named tag; `#stable` clears pre-release mode
- **Branch fallback**: `feat/` branch name triggers minor when no commit marker
- **Precedence**: Commit marker wins over branch name signal
- **Major tag movement**: `MOVE_MAJOR_TAG=true` creates floating major pointer

## Dependencies

### Required

- **Git**: For repository operations
- **Bash**: Version 4.0+ recommended

### Optional

- **BATS**: For running `.bats` test files
  - Install on macOS: `brew install bats-core`
  - Install on Ubuntu/Debian: `sudo apt-get install bats`
  - See: https://github.com/bats-core/bats-core

## Test Coverage

The tests cover the following scenarios from the GitHub Action:

### Core Logic Coverage

- ✅ Version parsing from Git tags
- ✅ Commit message analysis for version bump indicators
- ✅ Semantic version bumping (major, minor, patch)
- ✅ Tag creation and Git operations
- ✅ Major tag movement functionality
- ✅ Git configuration setup
- ✅ Edge cases and error conditions
- ✅ Conventional Commits type parsing and `cc_type_map` lookup
- ✅ Pre-release suffix — workflow input and commit-message detection
- ✅ `allowed_prerelease_suffixes` validation and fallback

### Commit Message Patterns Tested

- ✅ `#major`, `#minor`, `#patch` (case insensitive)
- ✅ Keywords at different positions in messages
- ✅ Multiple keywords (highest-precedence marker wins)
- ✅ Words without `#` prefix (should not trigger)
- ✅ Empty or malformed commit messages
- ✅ `#skip`, `#no-bump`, `#skip-version` skip markers
- ✅ `#prerelease:<suffix>` and `#pre:<suffix>` hashtag markers
- ✅ `Pre-release:` / `Prerelease:` footer (case-insensitive)
- ✅ `pre:<suffix>` CC scope hint (e.g. `feat(pre:alpha):`)
- ✅ Detection priority: footer > scope hint > hashtag marker
- ✅ Validation against `allowed_prerelease_suffixes` list
- ✅ Fallback to workflow input when suffix is invalid

### Version Scenarios Tested

- ✅ Starting from `v0.0.0` (no existing tags)
- ✅ Normal increments: `v1.2.3` → `v1.2.4`
- ✅ Minor bumps reset patch: `v1.2.3` → `v1.3.0`
- ✅ Major bumps reset minor and patch: `v1.2.3` → `v2.0.0`
- ✅ Large version numbers: `v99.99.99`
- ✅ Zero versions: `v0.0.1`, `v0.1.0`

## Adding New Tests

### Adding Unit Tests

Add new test cases to `test.sh`:

```bash
# Test new scenario
result=$(calculate_new_version "2.0.0" "Your test message #minor")
run_test "Your test description" "2.1.0" "$result"
```

To test pre-release suffix detection, use the `resolve_commit_prerelease_suffix` helper:

```bash
# Args: commit_msg [workflow_suffix [allowed_suffixes [marker_style]]]
result=$(resolve_commit_prerelease_suffix "Feature #prerelease:beta" "alpha")
run_test "Commit message overrides workflow suffix" "beta" "$result"
```

### Adding Integration Tests

Add new integration tests to `integration_test.sh`:

```bash
test_your_new_scenario() {
    # Your test logic here
    # Return 0 for success, 1 for failure
}

run_integration_test "Your test name" test_your_new_scenario
```

### Adding BATS Script Tests

Add new tests to `test_script.bats` to test the production script directly:

```bash
@test "script: your scenario description" {
    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "change" >> README.md
    git add README.md
    git commit --quiet -m "Your commit message #minor"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        bash "$BATS_TEST_DIRNAME/../scripts/bump-version.sh"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "v1.1.0"
    grep -q "new_version=v1.1.0" "$GITHUB_OUTPUT_FILE"
}
```

### Adding BATS Helper Tests

Add new BATS tests to `test.bats` for helper function coverage:

```bash
@test "your test description" {
    # Test setup
    result=$(your_helper_function)

    # Assertion
    [ "$result" = "expected_value" ]
}
```

## Continuous Integration

These tests are designed to be run in CI/CD environments. The `run_tests.sh` script:

- Exits with code 0 on success (all tests pass)
- Exits with code 1 on failure (any test fails)
- Provides detailed output for debugging failures
- Works in headless environments (no user interaction required)

### Example CI Usage

```yaml
# In your .github/workflows/test.yml
- name: Run Action Tests
  run: |
    cd tests/
    ./run_tests.sh
```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Make test files executable

   ```bash
   chmod +x tests/*.sh
   ```

2. **Git Not Configured**: Tests automatically configure Git, but ensure Git is installed

3. **BATS Not Found**: BATS tests are optional. Install BATS or ignore these tests

4. **Temporary Directory Issues**: Tests create temporary directories - ensure sufficient disk space and permissions

### Debugging Test Failures

1. Run individual test suites to isolate issues
2. Check the detailed output when tests fail
3. Manually run the failing commands in a test Git repository
4. Verify Git operations work correctly in your environment

## Contributing

When modifying the GitHub Action:

1. **Update Tests**: Ensure tests reflect your changes
2. **Run Tests**: Verify all tests pass before submitting
3. **Add New Tests**: Cover any new functionality or edge cases
4. **Document Changes**: Update this README if you add new test files or categories
