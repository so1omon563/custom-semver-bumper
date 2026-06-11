#!/bin/bash
# shellcheck disable=SC2329  # Test functions are invoked indirectly via run_integration_test

# Integration tests for Custom Version Bumper Action
# These tests simulate real Git repository scenarios

set -e

# Source test helpers (provides calculate_new_version and simulate_version_bump)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test_helpers.sh
source "$SCRIPT_DIR/test_helpers.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_test_header() {
    echo -e "\n${YELLOW}=== $1 ===${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_failure() {
    echo -e "${RED}✗ $1${NC}"
    echo -e "${RED}  $2${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

run_integration_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_name="$1"
    local test_function="$2"
    
    print_info "Running: $test_name"
    
    # Create a temporary directory for each test
    local temp_dir
    temp_dir=$(mktemp -d)
    local original_dir
    original_dir=$(pwd)
    
    cd "$temp_dir" || return 1
    
    # Initialize a git repository
    git init --quiet
    git config user.name "Test User"
    git config user.email "test@example.com"
    
    # Create initial commit
    echo "Initial content" > README.md
    git add README.md
    git commit --quiet -m "Initial commit"
    
    if $test_function; then
        print_success "$test_name"
    else
        print_failure "$test_name" "Test function returned false"
    fi
    
    # Cleanup
    cd "$original_dir" || return 1
    rm -rf "$temp_dir"
}

# Test function for no existing tags scenario
test_no_existing_tags() {
    # Simulate getting latest tag when none exists
    local latest_tag
    latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    
    if [[ "$latest_tag" == "v0.0.0" ]]; then
        return 0
    else
        echo "Expected v0.0.0, got $latest_tag"
        return 1
    fi
}

# Test function for existing tags scenario
test_with_existing_tags() {
    # Create some tags - create them in chronological order
    git tag -a "v1.0.0" -m "Version 1.0.0"
    
    # Create a new commit for the next tag
    echo "Update 1" >> README.md
    git add README.md
    git commit --quiet -m "Update 1"
    git tag -a "v1.1.0" -m "Version 1.1.0"
    
    # Create another commit for the final tag
    echo "Update 2" >> README.md
    git add README.md
    git commit --quiet -m "Update 2"
    git tag -a "v1.1.5" -m "Version 1.1.5"
    
    # Get latest tag
    local latest_tag
    latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    
    if [[ "$latest_tag" == "v1.1.5" ]]; then
        return 0
    else
        echo "Expected v1.1.5, got $latest_tag"
        return 1
    fi
}

# Test function for tag creation
test_tag_creation() {
    # Create initial tag
    git tag -a "v1.0.0" -m "Version 1.0.0"
    
    # Simulate creating a new tag
    local new_tag="v1.0.1"
    git tag -a "$new_tag" -m "Bump version to $new_tag"
    
    # Verify tag was created
    if git tag -l | grep -q "$new_tag"; then
        return 0
    else
        echo "Tag $new_tag was not created"
        return 1
    fi
}

# Test function for major tag movement
test_major_tag_movement() {
    # Create initial tags
    git tag -a "v1.0.0" -m "Version 1.0.0"
    git tag -a "v1" -m "Major tag v1"
    
    # Create new commit for new version
    echo "New feature" >> README.md
    git add README.md
    git commit --quiet -m "Add new feature"
    
    # Simulate major tag movement
    local new_version="1.1.0"
    local new_tag="v$new_version"
    local major_tag="v1"
    
    # Create new version tag
    git tag -a "$new_tag" -m "Bump version to $new_tag"
    
    # Delete and recreate major tag
    git tag -d "$major_tag" 2>/dev/null || true
    git tag -a "$major_tag" -m "Move major tag to $new_tag"
    
    # Verify major tag points to the same commit as new tag
    local major_tag_commit new_tag_commit
    major_tag_commit=$(git rev-list -n 1 "$major_tag")
    new_tag_commit=$(git rev-list -n 1 "$new_tag")

    if [[ "$major_tag_commit" == "$new_tag_commit" ]]; then
        return 0
    else
        echo "Major tag doesn't point to same commit as new tag"
        return 1
    fi
}

# Test function for commit message parsing
test_commit_message_parsing() {
    # Create a commit with merge message containing version bump indicator
    echo "Feature update" >> README.md
    git add README.md
    git commit --quiet -m "Merge pull request #123: Add new feature #minor"
    
    # Get the merge commit message
    local merge_commit_msg
    merge_commit_msg=$(git log -1 --pretty=%B)

    # Test if we can detect the #minor tag
    if [[ $merge_commit_msg == *"#minor"* ]]; then
        return 0
    else
        echo "Failed to detect #minor in commit message: $merge_commit_msg"
        return 1
    fi
}

# Test function for version parsing edge cases
test_version_parsing_edge_cases() {
    # Test with different tag formats - add tags in chronological order
    git tag -a "v0.0.1" -m "Version 0.0.1"
    
    # Create a new commit for the next tag
    echo "Major update" >> README.md
    git add README.md
    git commit --quiet -m "Major update"
    git tag -a "v10.20.30" -m "Version 10.20.30"
    
    local latest_tag
    latest_tag=$(git describe --tags --abbrev=0 2>/dev/null)
    local current_version=${latest_tag#v}
    
    # Parse version parts using same method as helper function
    local major minor patch
    
    # Use IFS to split version string into components
    IFS='.' read -r major minor patch <<< "$current_version"
    major=${major:-0}
    minor=${minor:-0}
    patch=${patch:-0}
    
    if [[ "$major" == "10" && "$minor" == "20" && "$patch" == "30" ]]; then
        return 0
    else
        echo "Failed to parse version correctly: major=$major, minor=$minor, patch=$patch (from $current_version)"
        return 1
    fi
}

# Test function for Git configuration
test_git_configuration() {
    # Simulate the Git configuration that the action would set
    git config user.name "GitHub Actions"
    git config user.email "actions@github.com"
    
    local configured_name configured_email
    configured_name=$(git config user.name)
    configured_email=$(git config user.email)

    if [[ "$configured_name" == "GitHub Actions" && "$configured_email" == "actions@github.com" ]]; then
        return 0
    else
        echo "Git configuration failed: name=$configured_name, email=$configured_email"
        return 1
    fi
}

# Test function for tag conflict resolution
test_tag_conflict_resolution() {
    # Create some existing tags to simulate the conflict scenario
    git commit --allow-empty -m "Initial commit" 2>/dev/null
    git tag -a v1.1.0 -m "Bump version to v1.1.0" 2>/dev/null
    
    git commit --allow-empty -m "Second commit" 2>/dev/null
    git tag -a v1.0.1 -m "Bump version to v1.0.1" 2>/dev/null
    
    git commit --allow-empty -m "Third commit" 2>/dev/null
    
    # Now when we run the action, it should detect v1.0.1 as latest reachable
    # but should find v1.1.0 as the highest version and bump from there
    cat > test_action.sh << 'EOF'
#!/bin/bash
set -e

# Simulate the updated action logic
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")

# Get the highest version tag (chronologically) for comparison
HIGHEST_TAG=$(git tag -l "v*.*.*" | sort -V | tail -1)

# Use the highest version tag if it exists and is higher than latest reachable
BASE_TAG="$LATEST_TAG"
if [[ -n "$HIGHEST_TAG" && "$HIGHEST_TAG" != "$LATEST_TAG" ]]; then
    # Compare versions to see which is higher
    LATEST_VER=${LATEST_TAG#v}
    HIGHEST_VER=${HIGHEST_TAG#v}
    
    # Simple version comparison using sort -V
    HIGHER_VER=$(printf '%s\n%s\n' "$LATEST_VER" "$HIGHEST_VER" | sort -V | tail -1)
    if [[ "$HIGHER_VER" == "$HIGHEST_VER" ]]; then
        echo "Using highest version tag $HIGHEST_TAG instead of latest reachable $LATEST_TAG"
        BASE_TAG="$HIGHEST_TAG"
    fi
fi

CURRENT_VERSION=${BASE_TAG#v}
IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"

MAJOR=${VERSION_PARTS[0]:-0}
MINOR=${VERSION_PARTS[1]:-0}
PATCH=${VERSION_PARTS[2]:-0}

if ! [[ "$MAJOR" =~ ^[0-9]+$ ]]; then MAJOR=0; fi
if ! [[ "$MINOR" =~ ^[0-9]+$ ]]; then MINOR=0; fi
if ! [[ "$PATCH" =~ ^[0-9]+$ ]]; then PATCH=0; fi

MERGE_COMMIT_MSG="Test merge commit"
BUMP_TYPE="patch"  # Default to patch for this test

NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
NEW_TAG="v$NEW_VERSION"

git config user.name "GitHub Actions"
git config user.email "actions@github.com"
git tag -a $NEW_TAG -m "Bump version to $NEW_TAG"

echo "New version tag created: $NEW_TAG"
EOF

    chmod +x test_action.sh
    
    # Run the test action
    local output
    output=$(./test_action.sh 2>&1)
    
    # Verify the new tag was created as v1.1.1 (next after highest v1.1.0)
    if git rev-parse v1.1.1 >/dev/null 2>&1; then
        if [[ $output == *"Using highest version tag v1.1.0"* ]]; then
            return 0
        else
            echo "Expected 'Using highest version tag v1.1.0' in output"
            echo "Actual output: $output"
            return 1
        fi
    else
        echo "Expected tag v1.1.1 was not created"
        echo "Output: $output"
        git tag -l
        return 1
    fi
}

# Test function for skip marker
test_skip_marker() {
    # Create a tag so we have something to compare against
    git tag -a "v1.0.0" -m "Version 1.0.0"

    # Create a new commit with a skip marker
    echo "Skip this" >> README.md
    git add README.md
    git commit --quiet -m "Maintenance work #skip"

    # Simulate skip detection
    local msg
    msg=$(git log -1 --pretty=%B)
    local lower_msg
    lower_msg=$(echo "$msg" | tr '[:upper:]' '[:lower:]')

    if [[ $lower_msg == *"#skip"* ]]; then
        # Verify no new tag is created (only v1.0.0 should exist)
        local tag_count
        tag_count=$(git tag -l "v*.*.*" | wc -l | tr -d ' ')
        if [[ "$tag_count" -eq 1 ]]; then
            return 0
        else
            echo "Expected 1 tag, found $tag_count"
            git tag -l
            return 1
        fi
    else
        echo "Skip marker #skip not detected in: $msg"
        return 1
    fi
}

# Test function for no-bump marker
test_no_bump_marker() {
    git tag -a "v2.0.0" -m "Version 2.0.0"

    echo "No bump" >> README.md
    git add README.md
    git commit --quiet -m "Config update #no-bump"

    local msg
    msg=$(git log -1 --pretty=%B)
    local lower_msg
    lower_msg=$(echo "$msg" | tr '[:upper:]' '[:lower:]')

    if [[ $lower_msg == *"#no-bump"* ]]; then
        return 0
    else
        echo "#no-bump not detected in: $msg"
        return 1
    fi
}

# Test function for pre-release tag creation
test_prerelease_tag_creation() {
    git tag -a "v1.0.0" -m "Version 1.0.0"
    echo "Feature" >> README.md
    git add README.md
    git commit --quiet -m "Add feature #minor"

    # Simulate pre-release logic: minor bump from 1.0.0 = 1.1.0-alpha.1
    local new_base_version="1.1.0"
    local suffix="alpha"
    local prerelease_base="v${new_base_version}-${suffix}"

    # No existing pre-release tags for this base → counter starts at 1
    local highest_prerelease
    highest_prerelease=$(git tag -l "${prerelease_base}.*" | sort -V | tail -1)
    local new_counter=1
    if [[ -n "$highest_prerelease" ]]; then
        local current_counter="${highest_prerelease##*.}"
        [[ "$current_counter" =~ ^[0-9]+$ ]] && new_counter="$((current_counter + 1))"
    fi

    local new_tag="${prerelease_base}.${new_counter}"
    git tag -a "$new_tag" -m "Pre-release $new_tag"

    if [[ "$new_tag" == "v1.1.0-alpha.1" ]] && git tag -l | grep -q "v1.1.0-alpha.1"; then
        return 0
    else
        echo "Expected tag v1.1.0-alpha.1, got $new_tag"
        return 1
    fi
}

# Test function for pre-release counter increment
test_prerelease_counter_increment() {
    git tag -a "v1.0.0" -m "Version 1.0.0"
    git tag -a "v1.1.0-alpha.1" -m "Pre-release 1"
    git tag -a "v1.1.0-alpha.2" -m "Pre-release 2"
    git tag -a "v1.1.0-alpha.3" -m "Pre-release 3"

    echo "Another alpha" >> README.md
    git add README.md
    git commit --quiet -m "More alpha work"

    # Simulate finding the highest pre-release counter and incrementing
    local highest
    highest=$(git tag -l "v1.1.0-alpha.*" | sort -V | tail -1)
    local counter="${highest##*.}"
    local new_counter="$((counter + 1))"
    local new_tag="v1.1.0-alpha.${new_counter}"

    if [[ "$new_tag" == "v1.1.0-alpha.4" ]]; then
        git tag -a "$new_tag" -m "Pre-release $new_tag"
        if git tag -l | grep -q "v1.1.0-alpha.4"; then
            return 0
        else
            echo "Tag v1.1.0-alpha.4 was not created"
            return 1
        fi
    else
        echo "Expected v1.1.0-alpha.4, got $new_tag"
        return 1
    fi
}

# Test function for minor tag movement
test_minor_tag_movement() {
    git tag -a "v1.2.0" -m "Version 1.2.0"
    git tag -a "v1.2" -m "Minor tag v1.2"

    echo "Patch fix" >> README.md
    git add README.md
    git commit --quiet -m "Patch fix"

    local new_tag="v1.2.1"
    local minor_tag="v1.2"

    git tag -a "$new_tag" -m "Bump version to $new_tag"
    git tag -d "$minor_tag" 2>/dev/null || true
    git tag -a "$minor_tag" -m "Move minor tag to $new_tag"

    local minor_commit
    local new_commit
    minor_commit=$(git rev-list -n 1 "$minor_tag")
    new_commit=$(git rev-list -n 1 "$new_tag")

    if [[ "$minor_commit" == "$new_commit" ]]; then
        return 0
    else
        echo "Minor tag does not point to same commit as new tag"
        return 1
    fi
}

# Test conventional commits mode: feat: → minor bump
test_conventional_commits_feat() {
    local cc_map="feat=minor
fix=patch"

    git tag -a "v1.2.3" -m "Version 1.2.3"

    local result
    result=$(calculate_new_version "1.2.3" "feat: add new authentication flow" "patch" "conventional-commits" "$cc_map")

    if [[ "$result" == "1.3.0" ]]; then
        return 0
    else
        echo "Expected 1.3.0 (minor bump for feat:), got $result"
        return 1
    fi
}

# Test conventional commits mode: fix: → patch bump
test_conventional_commits_fix() {
    local cc_map="feat=minor
fix=patch"

    git tag -a "v1.2.3" -m "Version 1.2.3"

    local result
    result=$(calculate_new_version "1.2.3" "fix: correct null pointer in session handler" "patch" "conventional-commits" "$cc_map")

    if [[ "$result" == "1.2.4" ]]; then
        return 0
    else
        echo "Expected 1.2.4 (patch bump for fix:), got $result"
        return 1
    fi
}

# Test conventional commits mode: feat!: → major bump
test_conventional_commits_breaking() {
    local cc_map="feat=minor
fix=patch"

    git tag -a "v1.2.3" -m "Version 1.2.3"

    local result
    result=$(calculate_new_version "1.2.3" "feat!: remove deprecated v1 API" "patch" "conventional-commits" "$cc_map")

    if [[ "$result" == "2.0.0" ]]; then
        return 0
    else
        echo "Expected 2.0.0 (major bump for feat!:), got $result"
        return 1
    fi
}

# Test commit-message pre-release suffix end-to-end (via resolve_commit_prerelease_suffix + git tags)
test_commit_message_prerelease_suffix() {
    git tag -a "v1.2.0" -m "Version 1.2.0"

    echo "Feature work" >> README.md
    git add README.md
    git commit --quiet -m "Add feature #minor #prerelease:beta"

    # Resolve suffix from commit message (mirrors bump-version.sh detection)
    local commit_msg
    commit_msg=$(git log -1 --pretty=%B)
    local resolved_suffix
    resolved_suffix=$(resolve_commit_prerelease_suffix "$commit_msg" "" "alpha beta rc preview canary dev")

    if [[ "$resolved_suffix" != "beta" ]]; then
        echo "Expected resolved suffix 'beta', got '$resolved_suffix'"
        return 1
    fi

    # Simulate the full tag creation with the resolved suffix
    local new_base_version="1.3.0"
    local prerelease_base="v${new_base_version}-${resolved_suffix}"
    local highest_prerelease
    highest_prerelease=$(git tag -l "${prerelease_base}.*" | sort -V | tail -1)
    local new_counter=1
    if [[ -n "$highest_prerelease" ]]; then
        local current_counter="${highest_prerelease##*.}"
        [[ "$current_counter" =~ ^[0-9]+$ ]] && new_counter="$((current_counter + 1))"
    fi

    local new_tag="${prerelease_base}.${new_counter}"
    git tag -a "$new_tag" -m "Pre-release $new_tag"

    if [[ "$new_tag" == "v1.3.0-beta.1" ]] && git tag -l | grep -q "v1.3.0-beta.1"; then
        return 0
    else
        echo "Expected tag v1.3.0-beta.1, got $new_tag"
        return 1
    fi
}

# Test commit-message prerelease suffix from CC footer (end-to-end: resolves suffix AND creates tag)
test_commit_message_prerelease_footer() {
    git tag -a "v2.0.0" -m "Version 2.0.0"

    echo "RC work" >> README.md
    git add README.md
    local commit_msg
    commit_msg="$(printf 'feat: final pre-release\n\nPre-release: rc')"
    git commit --quiet -m "$commit_msg"

    local actual_msg
    actual_msg=$(git log -1 --pretty=%B)

    # Resolve suffix from commit footer (mirrors bump-version.sh detection)
    local resolved_suffix
    resolved_suffix=$(resolve_commit_prerelease_suffix "$actual_msg" "" "alpha beta rc preview canary dev" "conventional-commits")

    if [[ "$resolved_suffix" != "rc" ]]; then
        echo "Expected resolved suffix 'rc' from Pre-release: footer, got '$resolved_suffix'"
        return 1
    fi

    # Simulate the full tag creation with the resolved suffix (mirrors hashtag sibling test)
    local new_base_version="2.1.0"
    local prerelease_base="v${new_base_version}-${resolved_suffix}"
    local highest_prerelease
    highest_prerelease=$(git tag -l "${prerelease_base}.*" | sort -V | tail -1)
    local new_counter=1
    if [[ -n "$highest_prerelease" ]]; then
        local current_counter="${highest_prerelease##*.}"
        [[ "$current_counter" =~ ^[0-9]+$ ]] && new_counter="$((current_counter + 1))"
    fi

    local new_tag="${prerelease_base}.${new_counter}"
    git tag -a "$new_tag" -m "Pre-release $new_tag"

    if [[ "$new_tag" == "v2.1.0-rc.1" ]] && git tag -l | grep -q "v2.1.0-rc.1"; then
        return 0
    else
        echo "Expected tag v2.1.0-rc.1, got $new_tag"
        return 1
    fi
}

# Run all integration tests
print_test_header "Integration Tests for Custom Version Bumper"

run_integration_test "No existing tags scenario" test_no_existing_tags
run_integration_test "With existing tags scenario" test_with_existing_tags
run_integration_test "Tag creation" test_tag_creation
run_integration_test "Major tag movement" test_major_tag_movement
run_integration_test "Commit message parsing" test_commit_message_parsing
run_integration_test "Version parsing edge cases" test_version_parsing_edge_cases
run_integration_test "Git configuration" test_git_configuration
run_integration_test "Tag conflict resolution" test_tag_conflict_resolution
run_integration_test "Skip marker (#skip)" test_skip_marker
run_integration_test "Skip marker (#no-bump)" test_no_bump_marker
run_integration_test "Pre-release tag creation" test_prerelease_tag_creation
run_integration_test "Pre-release counter increment" test_prerelease_counter_increment
run_integration_test "Minor tag movement" test_minor_tag_movement
run_integration_test "Conventional commits mode (feat: → minor)" test_conventional_commits_feat
run_integration_test "Conventional commits mode (fix: → patch)" test_conventional_commits_fix
run_integration_test "Conventional commits mode (feat!: → major)" test_conventional_commits_breaking
run_integration_test "Commit-message prerelease suffix (#prerelease: hashtag)" test_commit_message_prerelease_suffix
run_integration_test "Commit-message prerelease suffix (Pre-release: footer)" test_commit_message_prerelease_footer

# ── bump-version.sh smoke tests ───────────────────────────────────────────────
# These tests run the ACTUAL production script to catch drift between the mirrored
# helper functions in test_helpers.sh and the real bump-version.sh logic.

# Helper: set up a bare local "origin" so git push commands in the script succeed.
_setup_local_remote() {
    local origin_dir
    origin_dir=$(mktemp -d)
    git init --bare "$origin_dir" --quiet
    git remote add origin "$origin_dir"
    # Push initial branch to the bare remote so subsequent tag pushes work
    git push origin HEAD:main --quiet 2>/dev/null \
        || git push origin HEAD:master --quiet 2>/dev/null \
        || true
    echo "$origin_dir"
}

# Smoke test: default patch bump
test_bump_version_script_patch() {
    local origin_dir
    origin_dir=$(_setup_local_remote)

    git tag -a "v1.2.3" -m "Version 1.2.3"
    git push origin "v1.2.3" --quiet

    echo "Bug fix" >> README.md
    git add README.md
    git commit --quiet -m "Fix a critical null-pointer bug"

    local github_output
    github_output=$(mktemp)

    GITHUB_OUTPUT="$github_output" bash "$SCRIPT_DIR/../scripts/bump-version.sh" > /dev/null 2>&1

    if ! git tag -l | grep -q "v1.2.4"; then
        echo "Expected tag v1.2.4 not found. Tags: $(git tag -l)"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi
    if ! grep -q "new_version=v1.2.4" "$github_output"; then
        echo "GITHUB_OUTPUT missing new_version=v1.2.4. Got: $(cat "$github_output")"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi
    if ! grep -q "bump_type=patch" "$github_output"; then
        echo "GITHUB_OUTPUT missing bump_type=patch. Got: $(cat "$github_output")"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi

    rm -f "$github_output"; rm -rf "$origin_dir"
    return 0
}

# Smoke test: minor bump via #minor marker
test_bump_version_script_minor() {
    local origin_dir
    origin_dir=$(_setup_local_remote)

    git tag -a "v1.2.3" -m "Version 1.2.3"
    git push origin "v1.2.3" --quiet

    echo "New feature" >> README.md
    git add README.md
    git commit --quiet -m "Add new authentication flow #minor"

    local github_output
    github_output=$(mktemp)

    GITHUB_OUTPUT="$github_output" bash "$SCRIPT_DIR/../scripts/bump-version.sh" > /dev/null 2>&1

    if ! git tag -l | grep -q "v1.3.0"; then
        echo "Expected tag v1.3.0 not found. Tags: $(git tag -l)"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi
    if ! grep -q "bump_type=minor" "$github_output"; then
        echo "GITHUB_OUTPUT missing bump_type=minor. Got: $(cat "$github_output")"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi

    rm -f "$github_output"; rm -rf "$origin_dir"
    return 0
}

# Smoke test: major bump via #major marker
test_bump_version_script_major() {
    local origin_dir
    origin_dir=$(_setup_local_remote)

    git tag -a "v1.2.3" -m "Version 1.2.3"
    git push origin "v1.2.3" --quiet

    echo "Breaking change" >> README.md
    git add README.md
    git commit --quiet -m "Remove deprecated API endpoints #major"

    local github_output
    github_output=$(mktemp)

    GITHUB_OUTPUT="$github_output" bash "$SCRIPT_DIR/../scripts/bump-version.sh" > /dev/null 2>&1

    if ! git tag -l | grep -q "v2.0.0"; then
        echo "Expected tag v2.0.0 not found. Tags: $(git tag -l)"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi
    if ! grep -q "bump_type=major" "$github_output"; then
        echo "GITHUB_OUTPUT missing bump_type=major. Got: $(cat "$github_output")"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi

    rm -f "$github_output"; rm -rf "$origin_dir"
    return 0
}

# Smoke test: #skip marker skips version bump
test_bump_version_script_skip() {
    local origin_dir
    origin_dir=$(_setup_local_remote)

    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "Docs" >> README.md
    git add README.md
    git commit --quiet -m "Update CI config #skip"

    local github_output
    github_output=$(mktemp)

    GITHUB_OUTPUT="$github_output" bash "$SCRIPT_DIR/../scripts/bump-version.sh" > /dev/null 2>&1

    # Only v1.0.0 should exist — no new tag created
    local tag_count
    tag_count=$(git tag -l "v*.*.*" | grep -cv -- '-')
    if [[ "$tag_count" -ne 1 ]]; then
        echo "Expected 1 stable tag after skip, found $tag_count. Tags: $(git tag -l)"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi
    if ! grep -q "skipped=true" "$github_output"; then
        echo "GITHUB_OUTPUT missing skipped=true. Got: $(cat "$github_output")"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi

    rm -f "$github_output"; rm -rf "$origin_dir"
    return 0
}

run_integration_test "bump-version.sh smoke: patch bump" test_bump_version_script_patch
run_integration_test "bump-version.sh smoke: minor bump (#minor)" test_bump_version_script_minor
run_integration_test "bump-version.sh smoke: major bump (#major)" test_bump_version_script_major
run_integration_test "bump-version.sh smoke: skip marker (#skip)" test_bump_version_script_skip

# Smoke test: commit-message pre-release suffix via #prerelease: hashtag
test_bump_version_script_prerelease_hashtag() {
    local origin_dir
    origin_dir=$(_setup_local_remote)

    git tag -a "v1.5.0" -m "Version 1.5.0"
    git push origin "v1.5.0" --quiet

    echo "Experimental feature" >> README.md
    git add README.md
    git commit --quiet -m "Add experimental search #prerelease:alpha"

    local github_output
    github_output=$(mktemp)

    GITHUB_OUTPUT="$github_output" \
    ALLOWED_PRERELEASE_SUFFIXES="alpha beta rc" \
    bash "$SCRIPT_DIR/../scripts/bump-version.sh" > /dev/null 2>&1

    if ! git tag -l | grep -q "v1.5.1-alpha.1"; then
        echo "Expected tag v1.5.1-alpha.1 not found. Tags: $(git tag -l)"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi
    if ! grep -q "new_version=v1.5.1-alpha.1" "$github_output"; then
        echo "GITHUB_OUTPUT missing new_version=v1.5.1-alpha.1. Got: $(cat "$github_output")"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi

    rm -f "$github_output"; rm -rf "$origin_dir"
    return 0
}

# Smoke test: commit-message pre-release suffix overrides workflow input
test_bump_version_script_prerelease_override() {
    local origin_dir
    origin_dir=$(_setup_local_remote)

    git tag -a "v2.0.0" -m "Version 2.0.0"
    git push origin "v2.0.0" --quiet

    echo "Beta work" >> README.md
    git add README.md
    git commit --quiet -m "Promote to beta #minor #prerelease:beta"

    local github_output
    github_output=$(mktemp)

    # Workflow input says alpha; commit message says beta — commit message wins
    GITHUB_OUTPUT="$github_output" \
    PRERELEASE_SUFFIX="alpha" \
    ALLOWED_PRERELEASE_SUFFIXES="alpha beta rc" \
    bash "$SCRIPT_DIR/../scripts/bump-version.sh" > /dev/null 2>&1

    if ! git tag -l | grep -q "v2.1.0-beta.1"; then
        echo "Expected tag v2.1.0-beta.1 (commit msg wins over workflow 'alpha'). Tags: $(git tag -l)"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi

    rm -f "$github_output"; rm -rf "$origin_dir"
    return 0
}

run_integration_test "bump-version.sh smoke: prerelease suffix via #prerelease: hashtag" test_bump_version_script_prerelease_hashtag
run_integration_test "bump-version.sh smoke: commit-msg prerelease overrides workflow input" test_bump_version_script_prerelease_override

# Smoke test: CC mode feat: → minor bump via bump-version.sh
test_bump_version_script_cc_minor() {
    local origin_dir
    origin_dir=$(_setup_local_remote)

    git tag -a "v3.0.0" -m "Version 3.0.0"
    git push origin "v3.0.0" --quiet

    echo "New login flow" >> README.md
    git add README.md
    git commit --quiet -m "feat: add new login flow"

    local github_output
    github_output=$(mktemp)

    GITHUB_OUTPUT="$github_output" \
    MARKER_STYLE="conventional-commits" \
    CC_TYPE_MAP="$(printf 'feat=minor\nfix=patch\nchore=patch')" \
    bash "$SCRIPT_DIR/../scripts/bump-version.sh" > /dev/null 2>&1

    if ! git tag -l | grep -q "v3.1.0"; then
        echo "Expected tag v3.1.0 not found. Tags: $(git tag -l)"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi
    if ! grep -q "bump_type=minor" "$github_output"; then
        echo "GITHUB_OUTPUT missing bump_type=minor. Got: $(cat "$github_output")"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi

    rm -f "$github_output"; rm -rf "$origin_dir"
    return 0
}

run_integration_test "bump-version.sh smoke: CC mode feat: → minor bump" test_bump_version_script_cc_minor

# Smoke test: branch name fallback when commit has no explicit marker
test_bump_version_script_branch_fallback() {
    local origin_dir
    origin_dir=$(_setup_local_remote)

    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "New login flow" >> README.md
    git add README.md
    # No explicit version marker in commit message
    git commit --quiet -m "Add new login flow"

    local github_output
    github_output=$(mktemp)

    # Branch name provides the signal; commit message has none
    GITHUB_OUTPUT="$github_output" \
    BRANCH_NAME="feat/add-login" \
    bash "$SCRIPT_DIR/../scripts/bump-version.sh" > /dev/null 2>&1

    if ! git tag -l | grep -q "v1.1.0"; then
        echo "Expected tag v1.1.0 (feat/ branch → minor). Tags: $(git tag -l)"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi
    if ! grep -q "bump_type=minor" "$github_output"; then
        echo "GITHUB_OUTPUT missing bump_type=minor. Got: $(cat "$github_output")"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi

    rm -f "$github_output"; rm -rf "$origin_dir"
    return 0
}

# Smoke test: commit message marker takes precedence over branch name
test_bump_version_script_branch_commit_wins() {
    local origin_dir
    origin_dir=$(_setup_local_remote)

    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "Breaking change" >> README.md
    git add README.md
    # Explicit #major in commit should win over fix/ branch (which would be patch)
    git commit --quiet -m "Breaking API change #major"

    local github_output
    github_output=$(mktemp)

    GITHUB_OUTPUT="$github_output" \
    BRANCH_NAME="fix/some-fix" \
    bash "$SCRIPT_DIR/../scripts/bump-version.sh" > /dev/null 2>&1

    if ! git tag -l | grep -q "v2.0.0"; then
        echo "Expected tag v2.0.0 (commit #major wins over fix/ branch). Tags: $(git tag -l)"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi
    if ! grep -q "bump_type=major" "$github_output"; then
        echo "GITHUB_OUTPUT missing bump_type=major. Got: $(cat "$github_output")"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi

    rm -f "$github_output"; rm -rf "$origin_dir"
    return 0
}

run_integration_test "bump-version.sh smoke: branch name fallback (feat/ → minor)" test_bump_version_script_branch_fallback
run_integration_test "bump-version.sh smoke: commit message wins over branch name" test_bump_version_script_branch_commit_wins

# Smoke test: default_bump=prerelease produces counter-only pre-release tag
test_bump_version_script_default_prerelease() {
    local origin_dir
    origin_dir=$(_setup_local_remote)

    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "Routine work" >> README.md
    git add README.md
    git commit --quiet -m "Add minor improvements"

    local github_output
    github_output=$(mktemp)

    GITHUB_OUTPUT="$github_output" \
    DEFAULT_BUMP="prerelease" \
    bash "$SCRIPT_DIR/../scripts/bump-version.sh" > /dev/null 2>&1

    if ! git tag -l | grep -q "v1.0.1-1"; then
        echo "Expected counter-only tag v1.0.1-1. Tags: $(git tag -l)"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi
    if ! grep -q "new_version=v1.0.1-1" "$github_output"; then
        echo "GITHUB_OUTPUT missing new_version=v1.0.1-1. Got: $(cat "$github_output")"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi

    rm -f "$github_output"; rm -rf "$origin_dir"
    return 0
}

# Smoke test: default_bump=prerelease + named suffix → named pre-release
test_bump_version_script_default_prerelease_named() {
    local origin_dir
    origin_dir=$(_setup_local_remote)

    git tag -a "v2.0.0" -m "Version 2.0.0"
    git push origin "v2.0.0" --quiet

    echo "Routine work" >> README.md
    git add README.md
    git commit --quiet -m "Add minor improvements"

    local github_output
    github_output=$(mktemp)

    GITHUB_OUTPUT="$github_output" \
    DEFAULT_BUMP="prerelease" \
    PRERELEASE_SUFFIX="alpha" \
    bash "$SCRIPT_DIR/../scripts/bump-version.sh" > /dev/null 2>&1

    if ! git tag -l | grep -q "v2.0.1-alpha.1"; then
        echo "Expected named pre-release tag v2.0.1-alpha.1. Tags: $(git tag -l)"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi

    rm -f "$github_output"; rm -rf "$origin_dir"
    return 0
}

# Smoke test: default_bump=prerelease + explicit #minor + no suffix → stable minor
test_bump_version_script_prerelease_explicit_stable() {
    local origin_dir
    origin_dir=$(_setup_local_remote)

    git tag -a "v3.0.0" -m "Version 3.0.0"
    git push origin "v3.0.0" --quiet

    echo "New feature" >> README.md
    git add README.md
    git commit --quiet -m "Add new API endpoint #minor"

    local github_output
    github_output=$(mktemp)

    GITHUB_OUTPUT="$github_output" \
    DEFAULT_BUMP="prerelease" \
    bash "$SCRIPT_DIR/../scripts/bump-version.sh" > /dev/null 2>&1

    if ! git tag -l | grep -q "v3.1.0"; then
        echo "Expected stable tag v3.1.0 (#minor + prerelease default + no suffix). Tags: $(git tag -l)"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi

    rm -f "$github_output"; rm -rf "$origin_dir"
    return 0
}

# Smoke test: bare #prerelease marker → counter-only
test_bump_version_script_bare_prerelease_marker() {
    local origin_dir
    origin_dir=$(_setup_local_remote)

    git tag -a "v4.0.0" -m "Version 4.0.0"
    git push origin "v4.0.0" --quiet

    echo "WIP" >> README.md
    git add README.md
    git commit --quiet -m "Work in progress #prerelease"

    local github_output
    github_output=$(mktemp)

    GITHUB_OUTPUT="$github_output" \
    bash "$SCRIPT_DIR/../scripts/bump-version.sh" > /dev/null 2>&1

    if ! git tag -l | grep -q "v4.0.1-1"; then
        echo "Expected counter-only tag v4.0.1-1 from bare #prerelease. Tags: $(git tag -l)"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi

    rm -f "$github_output"; rm -rf "$origin_dir"
    return 0
}

# Smoke test: #stable escape hatch clears pre-release
test_bump_version_script_stable_escape() {
    local origin_dir
    origin_dir=$(_setup_local_remote)

    git tag -a "v5.0.0" -m "Version 5.0.0"
    git push origin "v5.0.0" --quiet

    echo "Release" >> README.md
    git add README.md
    git commit --quiet -m "Promote to stable #minor #stable"

    local github_output
    github_output=$(mktemp)

    GITHUB_OUTPUT="$github_output" \
    DEFAULT_BUMP="prerelease" \
    PRERELEASE_SUFFIX="alpha" \
    bash "$SCRIPT_DIR/../scripts/bump-version.sh" > /dev/null 2>&1

    if ! git tag -l | grep -q "v5.1.0"; then
        echo "Expected stable tag v5.1.0 (#stable escape hatch). Tags: $(git tag -l)"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi
    # Should NOT have created any pre-release tag
    if git tag -l | grep -q "v5.1.0-"; then
        echo "Unexpected pre-release tag created despite #stable marker. Tags: $(git tag -l)"
        rm -f "$github_output"; rm -rf "$origin_dir"
        return 1
    fi

    rm -f "$github_output"; rm -rf "$origin_dir"
    return 0
}

run_integration_test "bump-version.sh smoke: default_bump=prerelease → counter-only (v1.0.1-1)" test_bump_version_script_default_prerelease
run_integration_test "bump-version.sh smoke: default_bump=prerelease + suffix → named (v2.0.1-alpha.1)" test_bump_version_script_default_prerelease_named
run_integration_test "bump-version.sh smoke: default_bump=prerelease + #minor + no suffix → stable (v3.1.0)" test_bump_version_script_prerelease_explicit_stable
run_integration_test "bump-version.sh smoke: bare #prerelease marker → counter-only (v4.0.1-1)" test_bump_version_script_bare_prerelease_marker
run_integration_test "bump-version.sh smoke: #stable escape hatch → stable (v5.1.0)" test_bump_version_script_stable_escape

# Print test summary
print_test_header "Integration Test Summary"
echo "Tests run: $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}All integration tests passed! 🎉${NC}"
    exit 0
else
    echo -e "\n${RED}Some integration tests failed. 😞${NC}"
    exit 1
fi
