#!/bin/bash

# Unit tests for Custom Version Bumper Action

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
print_test_header() {
    echo -e "\n${YELLOW}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_failure() {
    echo -e "${RED}✗ $1${NC}"
    echo -e "${RED}  Expected: $2${NC}"
    echo -e "${RED}  Got: $3${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    
    if [[ "$expected" == "$actual" ]]; then
        print_success "$test_name"
    else
        print_failure "$test_name" "$expected" "$actual"
    fi
}

# Function to simulate version bumping logic
# Args: current_version commit_msg [default_bump [marker_style [cc_type_map]]]
# Returns new version string, or "skip" if the bump would be skipped.
calculate_new_version() {
    local current_version="$1"
    local merge_commit_msg="$2"
    local default_bump="${3:-patch}"
    local marker_style="${4:-hashtag}"
    local cc_type_map="${5:-}"

    # Parse current version with robust handling for missing parts
    local MAJOR MINOR PATCH
    IFS='.' read -r MAJOR MINOR PATCH <<< "$current_version"
    MAJOR=${MAJOR:-0}
    MINOR=${MINOR:-0}
    PATCH=${PATCH:-0}

    # Validate that parts are numeric, otherwise default to 0
    if ! [[ "$MAJOR" =~ ^[0-9]+$ ]]; then MAJOR=0; fi
    if ! [[ "$MINOR" =~ ^[0-9]+$ ]]; then MINOR=0; fi
    if ! [[ "$PATCH" =~ ^[0-9]+$ ]]; then PATCH=0; fi

    local lower_msg
    lower_msg=$(echo "$merge_commit_msg" | tr '[:upper:]' '[:lower:]')

    # Check for skip markers first (honored in both modes)
    if [[ $lower_msg == *"#skip-version"* ]] || \
       [[ $lower_msg == *"#no-bump"* ]] || \
       [[ $lower_msg == *"#skip"* ]]; then
        echo "skip"
        return 0
    fi

    local BUMP_TYPE=""

    if [[ "$marker_style" == "conventional-commits" ]]; then
        local CC_TYPE=""
        local line
        local cc_breaking_re='^([a-zA-Z]+)(\([^)]*\))?!:'
        local cc_footer_re='^BREAKING([[:space:]]|-)CHANGE:'
        local cc_type_re='^([a-zA-Z]+)(\([^)]*\))?:'
        while IFS= read -r line; do
            if [[ "$line" =~ $cc_breaking_re ]]; then
                CC_TYPE=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
                BUMP_TYPE="major"
                break
            fi
            if [[ "$line" =~ $cc_footer_re ]]; then
                BUMP_TYPE="major"
                break
            fi
            if [[ -z "$CC_TYPE" && "$line" =~ $cc_type_re ]]; then
                CC_TYPE=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
            fi
        done <<< "$merge_commit_msg"

        if [[ -z "$BUMP_TYPE" && -n "$CC_TYPE" && -n "$cc_type_map" ]]; then
            local map_key map_val
            while IFS='=' read -r map_key map_val; do
                map_key=$(echo "$map_key" | tr -d ' \t\r')
                map_val=$(echo "$map_val" | tr -d ' \t\r')
                if [[ -n "$map_key" && "$map_key" == "$CC_TYPE" ]]; then
                    BUMP_TYPE="$map_val"
                    break
                fi
            done <<< "$cc_type_map"
        fi

        if [[ -z "$BUMP_TYPE" ]]; then
            BUMP_TYPE="$default_bump"
        fi
    else
        # Hashtag mode (default)
        # Precedence: #major > #minor > #patch > default_bump
        if [[ $lower_msg == *"#major"* ]]; then
            BUMP_TYPE="major"
        elif [[ $lower_msg == *"#minor"* ]]; then
            BUMP_TYPE="minor"
        elif [[ $lower_msg == *"#patch"* ]]; then
            BUMP_TYPE="patch"
        else
            BUMP_TYPE="$default_bump"
        fi
    fi

    # Handle 'none' and prerelease default_bump variants with no explicit marker
    if [[ "$BUMP_TYPE" == "none" ]]; then
        echo "skip"
        return 0
    fi
    # Parse compound prerelease default_bump values for base-version calculation.
    case "$BUMP_TYPE" in
        prerelease|patch-prerelease) BUMP_TYPE="patch" ;;
        minor-prerelease) BUMP_TYPE="minor" ;;
        major-prerelease) BUMP_TYPE="major" ;;
    esac

    # Bump version
    case $BUMP_TYPE in
        "major") echo "$((MAJOR + 1)).0.0" ;;
        "minor") echo "$MAJOR.$((MINOR + 1)).0" ;;
        *)       echo "$MAJOR.$MINOR.$((PATCH + 1))" ;;
    esac
}

# Test version parsing and bumping
print_test_header "Version Parsing and Bumping Tests"

# Test patch bumping (default)
result=$(calculate_new_version "1.2.3" "Fix bug in function")
run_test "Patch bump from 1.2.3" "1.2.4" "$result"

result=$(calculate_new_version "0.0.1" "Small fix")
run_test "Patch bump from 0.0.1" "0.0.2" "$result"

result=$(calculate_new_version "10.5.99" "Another patch fix")
run_test "Patch bump from 10.5.99" "10.5.100" "$result"

# Test minor bumping
result=$(calculate_new_version "1.2.3" "Add new feature #minor")
run_test "Minor bump from 1.2.3" "1.3.0" "$result"

result=$(calculate_new_version "0.0.1" "New feature added #minor")
run_test "Minor bump from 0.0.1" "0.1.0" "$result"

result=$(calculate_new_version "5.99.50" "Feature enhancement #minor")
run_test "Minor bump from 5.99.50" "5.100.0" "$result"

# Test major bumping
result=$(calculate_new_version "1.2.3" "Breaking change introduced #major")
run_test "Major bump from 1.2.3" "2.0.0" "$result"

result=$(calculate_new_version "0.5.10" "Major refactor #major")
run_test "Major bump from 0.5.10" "1.0.0" "$result"

result=$(calculate_new_version "99.1.1" "API breaking change #major")
run_test "Major bump from 99.1.1" "100.0.0" "$result"

# Test case sensitivity and multiple keywords
result=$(calculate_new_version "1.0.0" "Fix issue and add feature #minor")
run_test "Minor bump with #minor" "1.1.0" "$result"

result=$(calculate_new_version "1.0.0" "Breaking change #major")
run_test "Major bump with #major" "2.0.0" "$result"

result=$(calculate_new_version "1.0.0" "Multiple keywords #minor then #major should use major (first in precedence)")
run_test "Multiple keywords - should use major (higher precedence)" "2.0.0" "$result"

result=$(calculate_new_version "1.0.0" "Keywords in wrong order #major #minor should use major (first found)")
run_test "Multiple keywords - should use major (first found)" "2.0.0" "$result"

result=$(calculate_new_version "1.0.0" "Test #MAJOR uppercase")
run_test "Case insensitive #MAJOR" "2.0.0" "$result"

result=$(calculate_new_version "1.0.0" "Test #MINOR uppercase")
run_test "Case insensitive #MINOR" "1.1.0" "$result"

# Test edge cases
result=$(calculate_new_version "0.0.0" "Initial patch")
run_test "Patch bump from 0.0.0" "0.0.1" "$result"

result=$(calculate_new_version "0.0.0" "Initial minor #minor")
run_test "Minor bump from 0.0.0" "0.1.0" "$result"

result=$(calculate_new_version "0.0.0" "Initial major #major")
run_test "Major bump from 0.0.0" "1.0.0" "$result"

# Test commit messages that might contain keywords but not as tags
result=$(calculate_new_version "1.0.0" "This is a major improvement but no hashtag")
run_test "Contains 'major' but not #major" "1.0.1" "$result"

result=$(calculate_new_version "1.0.0" "Minor fix without hashtag")
run_test "Contains 'minor' but not #minor" "1.0.1" "$result"

result=$(calculate_new_version "1.0.0" "Patch this issue")
run_test "Contains 'patch' but not #patch" "1.0.1" "$result"

# Test hashtags in different positions
result=$(calculate_new_version "1.0.0" "#minor at the beginning")
run_test "#minor at beginning of message" "1.1.0" "$result"

result=$(calculate_new_version "1.0.0" "In the middle #major of the message")
run_test "#major in middle of message" "2.0.0" "$result"

result=$(calculate_new_version "1.0.0" "At the end of message #minor")
run_test "#minor at end of message" "1.1.0" "$result"

# Function to simulate major tag extraction
extract_major_version() {
    local version="$1"
    echo "$version" | cut -d'.' -f1
}

print_test_header "Major Tag Movement Tests"

# Test major tag extraction
result=$(extract_major_version "1.2.3")
run_test "Extract major from 1.2.3" "1" "$result"

result=$(extract_major_version "10.0.0")
run_test "Extract major from 10.0.0" "10" "$result"

result=$(extract_major_version "0.5.1")
run_test "Extract major from 0.5.1" "0" "$result"

print_test_header "Skip Marker Tests"

result=$(calculate_new_version "1.0.0" "Deploy hotfix #skip" "patch")
run_test "#skip marker triggers skip" "skip" "$result"

result=$(calculate_new_version "1.0.0" "No bump needed #no-bump" "patch")
run_test "#no-bump marker triggers skip" "skip" "$result"

result=$(calculate_new_version "1.0.0" "Skip this release #skip-version" "patch")
run_test "#skip-version marker triggers skip" "skip" "$result"

result=$(calculate_new_version "1.0.0" "Deploy hotfix #SKIP" "patch")
run_test "#SKIP uppercase triggers skip" "skip" "$result"

result=$(calculate_new_version "1.0.0" "No bump #NO-BUMP uppercase" "patch")
run_test "#NO-BUMP uppercase triggers skip" "skip" "$result"

print_test_header "Explicit #patch Marker Tests"

result=$(calculate_new_version "1.2.3" "Explicit patch bump #patch" "patch")
run_test "#patch explicit marker" "1.2.4" "$result"

result=$(calculate_new_version "1.2.3" "Patch even with none default #patch" "none")
run_test "#patch marker overrides default_bump=none" "1.2.4" "$result"

result=$(calculate_new_version "1.0.0" "Patch this issue" "patch")
run_test "Word 'patch' without # is still default bump" "1.0.1" "$result"

print_test_header "Configurable default_bump Tests"

result=$(calculate_new_version "1.2.3" "No marker present" "minor")
run_test "default_bump=minor with no marker" "1.3.0" "$result"

result=$(calculate_new_version "1.2.3" "No marker present" "major")
run_test "default_bump=major with no marker" "2.0.0" "$result"

result=$(calculate_new_version "1.2.3" "No marker present" "none")
run_test "default_bump=none with no marker skips" "skip" "$result"

result=$(calculate_new_version "1.2.3" "Feature #minor" "none")
run_test "default_bump=none with #minor marker bumps" "1.3.0" "$result"

result=$(calculate_new_version "1.2.3" "Breaking #major" "none")
run_test "default_bump=none with #major marker bumps" "2.0.0" "$result"

result=$(calculate_new_version "1.2.3" "Patch fix #patch" "none")
run_test "default_bump=none with #patch marker bumps" "1.2.4" "$result"

DEFAULT_CC_MAP="feat=minor
fix=patch"

print_test_header "Conventional Commits Mode Tests"

result=$(calculate_new_version "1.2.3" "feat: add new feature" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
run_test "CC: feat: → minor bump" "1.3.0" "$result"

result=$(calculate_new_version "1.2.3" "fix: fix the bug" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
run_test "CC: fix: → patch bump" "1.2.4" "$result"

result=$(calculate_new_version "1.2.3" "feat!: drop support for v1 API" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
run_test "CC: feat!: → major bump (! suffix)" "2.0.0" "$result"

result=$(calculate_new_version "1.2.3" "fix!: rename config keys" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
run_test "CC: fix!: → major bump (! suffix)" "2.0.0" "$result"

result=$(calculate_new_version "1.2.3" "$(printf 'feat: add thing\n\nBREAKING CHANGE: removed old API')" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
run_test "CC: BREAKING CHANGE footer → major bump" "2.0.0" "$result"

result=$(calculate_new_version "1.2.3" "$(printf 'feat: add thing\n\nBREAKING-CHANGE: removed old API')" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
run_test "CC: BREAKING-CHANGE footer (hyphen form) → major bump" "2.0.0" "$result"

result=$(calculate_new_version "1.2.3" "feat(auth): add OAuth support" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
run_test "CC: feat(scope): → minor bump" "1.3.0" "$result"

result=$(calculate_new_version "1.2.3" "feat(api)!: remove deprecated endpoint" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
run_test "CC: feat(scope)!: → major bump" "2.0.0" "$result"

result=$(calculate_new_version "1.2.3" "chore: update dependencies" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
run_test "CC: chore: (not in map) → fallback to default_bump (patch)" "1.2.4" "$result"

result=$(calculate_new_version "1.2.3" "docs: update readme" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
run_test "CC: docs: (not in map) → fallback to default_bump (patch)" "1.2.4" "$result"

result=$(calculate_new_version "1.2.3" "refactor: clean up auth module" "minor" "conventional-commits" "$DEFAULT_CC_MAP")
run_test "CC: refactor: (not in map) → fallback to default_bump (minor)" "1.3.0" "$result"

EXTENDED_CC_MAP="feat=minor
fix=patch
perf=patch
refactor=patch"

result=$(calculate_new_version "1.2.3" "perf: optimise query" "patch" "conventional-commits" "$EXTENDED_CC_MAP")
run_test "CC: perf: with custom map → patch bump" "1.2.4" "$result"

result=$(calculate_new_version "1.2.3" "refactor: simplify parser" "patch" "conventional-commits" "$EXTENDED_CC_MAP")
run_test "CC: refactor: with custom map → patch bump" "1.2.4" "$result"

result=$(calculate_new_version "1.2.3" "feat: new thing #skip" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
run_test "CC: #skip escape hatch still skips in cc mode" "skip" "$result"

result=$(calculate_new_version "1.2.3" "fix: bug fix" "patch" "hashtag" "$DEFAULT_CC_MAP")
run_test "CC: hashtag mode unaffected (regression check)" "1.2.4" "$result"

# Resolve commit-message pre-release suffix (mirrors detection logic in bump-version.sh).
# NOTE: Keep in sync with scripts/bump-version.sh detection block.
# Args: commit_msg [workflow_suffix [allowed_suffixes [marker_style]]]
# Returns the effective suffix (from commit message if valid, else workflow input).
resolve_commit_prerelease_suffix() {
    local merge_commit_msg="$1"
    local workflow_suffix="${2:-}"
    local allowed_suffixes="${3:-alpha beta rc preview canary dev}"
    local marker_style="${4:-hashtag}"

    local lower_msg
    lower_msg=$(echo "$merge_commit_msg" | tr '[:upper:]' '[:lower:]')

    local COMMIT_MSG_PRERELEASE=""
    local CC_SCOPE_PRERELEASE=""

    # Step A (lowest priority baseline): hashtag marker
    local PRERELEASE_HASHTAG_RE='#(prerelease|pre):([a-zA-Z][a-zA-Z0-9]*)'
    if [[ "$lower_msg" =~ $PRERELEASE_HASHTAG_RE ]]; then
        COMMIT_MSG_PRERELEASE="${BASH_REMATCH[2]}"
    fi

    # Step B (overrides A): CC scope hint (only in conventional-commits mode)
    if [[ "$marker_style" == "conventional-commits" ]]; then
        local cc_breaking_re='^([a-zA-Z]+)(\([^)]*\))?!:'
        local cc_type_re='^([a-zA-Z]+)(\([^)]*\))?:'
        local line
        while IFS= read -r line; do
            # Breaking-change line: extract scope hint before breaking out
            if [[ -z "$CC_SCOPE_PRERELEASE" && "$line" =~ $cc_breaking_re ]]; then
                local scope_raw="${BASH_REMATCH[2]}"
                local scope_inner
                # Lowercase so feat(Pre:ALPHA)!: normalises to pre:alpha
                scope_inner=$(echo "${scope_raw#(}" | tr '[:upper:]' '[:lower:]')
                scope_inner="${scope_inner%)}"
                if [[ "$scope_inner" =~ ^pre:([a-zA-Z][a-zA-Z0-9]*)$ ]]; then
                    CC_SCOPE_PRERELEASE="${BASH_REMATCH[1]}"
                fi
            fi
            # Regular CC type line
            if [[ -z "$CC_SCOPE_PRERELEASE" && "$line" =~ $cc_type_re ]]; then
                local scope_raw="${BASH_REMATCH[2]}"
                local scope_inner
                # Lowercase so feat(Pre:ALPHA): normalises to pre:alpha (consistent with hashtag/footer)
                scope_inner=$(echo "${scope_raw#(}" | tr '[:upper:]' '[:lower:]')
                scope_inner="${scope_inner%)}"
                if [[ "$scope_inner" =~ ^pre:([a-zA-Z][a-zA-Z0-9]*)$ ]]; then
                    CC_SCOPE_PRERELEASE="${BASH_REMATCH[1]}"
                fi
            fi
        done <<< "$merge_commit_msg"
        if [[ -n "$CC_SCOPE_PRERELEASE" ]]; then
            COMMIT_MSG_PRERELEASE="$CC_SCOPE_PRERELEASE"
        fi
    fi

    # Step C (highest priority; overrides A and B): Pre-release: footer, case-insensitive
    # Intentional: only the first alphanumeric word after the colon is captured.
    local PRERELEASE_FOOTER_RE='^pre-?release:[[:space:]]*([a-zA-Z][a-zA-Z0-9]*)'
    local footer_line
    while IFS= read -r footer_line; do
        local footer_lower
        footer_lower=$(echo "$footer_line" | tr '[:upper:]' '[:lower:]')
        if [[ "$footer_lower" =~ $PRERELEASE_FOOTER_RE ]]; then
            COMMIT_MSG_PRERELEASE="${BASH_REMATCH[1]}"
            break
        fi
    done <<< "$merge_commit_msg"

    # Validate against allowed list; fall back to workflow input when invalid
    if [[ -n "$COMMIT_MSG_PRERELEASE" ]]; then
        local SUFFIX_VALID=false
        local allowed_val
        for allowed_val in $allowed_suffixes; do
            if [[ "$allowed_val" == "$COMMIT_MSG_PRERELEASE" ]]; then
                SUFFIX_VALID=true
                break
            fi
        done
        if $SUFFIX_VALID; then
            echo "$COMMIT_MSG_PRERELEASE"
            return 0
        fi
    fi

    echo "$workflow_suffix"
}

print_test_header "Commit-Message Pre-Release Suffix Detection Tests"

# --- Hashtag marker detection ---
result=$(resolve_commit_prerelease_suffix "Add feature #minor #prerelease:alpha")
run_test "Hashtag #prerelease:alpha sets suffix" "alpha" "$result"

result=$(resolve_commit_prerelease_suffix "Add feature #pre:beta")
run_test "Hashtag #pre:beta (alias) sets suffix" "beta" "$result"

result=$(resolve_commit_prerelease_suffix "Release candidate #prerelease:rc")
run_test "Hashtag #prerelease:rc sets suffix" "rc" "$result"

result=$(resolve_commit_prerelease_suffix "Feature #PRERELEASE:ALPHA")
run_test "Hashtag #PRERELEASE:ALPHA case-insensitive → alpha" "alpha" "$result"

# --- Commit message overrides workflow input ---
result=$(resolve_commit_prerelease_suffix "Fix #prerelease:beta" "alpha")
run_test "Commit message #prerelease:beta overrides workflow suffix alpha" "beta" "$result"

# --- Invalid suffix falls back to workflow input ---
result=$(resolve_commit_prerelease_suffix "Deploy #prerelease:snapshot" "alpha")
run_test "Invalid suffix 'snapshot' falls back to workflow input 'alpha'" "alpha" "$result"

result=$(resolve_commit_prerelease_suffix "Deploy #prerelease:snapshot" "")
run_test "Invalid suffix 'snapshot' falls back to empty workflow input" "" "$result"

# --- Custom allowed list ---
result=$(resolve_commit_prerelease_suffix "Deploy #prerelease:snapshot" "" "alpha beta snapshot")
run_test "Custom allowed list includes snapshot" "snapshot" "$result"

result=$(resolve_commit_prerelease_suffix "Deploy #prerelease:alpha" "" "beta rc")
run_test "alpha not in custom allowed list falls back to empty" "" "$result"

# --- CC mode: scope hint ---
result=$(resolve_commit_prerelease_suffix "feat(pre:alpha): add login" "" "alpha beta rc preview canary dev" "conventional-commits")
run_test "CC scope hint feat(pre:alpha): sets suffix" "alpha" "$result"

result=$(resolve_commit_prerelease_suffix "fix(pre:rc): null check" "" "alpha beta rc preview canary dev" "conventional-commits")
run_test "CC scope hint fix(pre:rc): sets suffix" "rc" "$result"

result=$(resolve_commit_prerelease_suffix "feat(auth): normal scope" "" "alpha beta rc preview canary dev" "conventional-commits")
run_test "CC normal scope (no pre:) does not set suffix" "" "$result"

result=$(resolve_commit_prerelease_suffix "feat(pre:alpha): add login" "beta" "alpha beta rc preview canary dev" "conventional-commits")
run_test "CC scope hint overrides workflow input beta" "alpha" "$result"

# --- CC mode: Pre-release: footer ---
result=$(resolve_commit_prerelease_suffix "$(printf 'feat: add feature\n\nPre-release: beta')" "" "alpha beta rc preview canary dev" "conventional-commits")
run_test "CC Pre-release: footer sets suffix" "beta" "$result"

result=$(resolve_commit_prerelease_suffix "$(printf 'feat: add feature\n\nPrerelease: rc')" "" "alpha beta rc preview canary dev" "conventional-commits")
run_test "CC Prerelease: footer (no hyphen) sets suffix" "rc" "$result"

result=$(resolve_commit_prerelease_suffix "$(printf 'feat: add feature\n\nPRE-RELEASE: alpha')" "" "alpha beta rc preview canary dev" "conventional-commits")
run_test "CC PRE-RELEASE: footer case-insensitive sets suffix" "alpha" "$result"

# --- Priority: footer > scope > hashtag ---
result=$(resolve_commit_prerelease_suffix "$(printf 'feat(pre:alpha): add thing #prerelease:beta\n\nPre-release: rc')" "" "alpha beta rc" "conventional-commits")
run_test "Footer wins over scope and hashtag (rc > alpha > beta)" "rc" "$result"

result=$(resolve_commit_prerelease_suffix "$(printf 'feat(pre:alpha): add thing #prerelease:beta')" "" "alpha beta rc" "conventional-commits")
run_test "Scope wins over hashtag when footer absent (alpha > beta)" "alpha" "$result"

# --- Hashtag marker works in CC mode too ---
result=$(resolve_commit_prerelease_suffix "feat: add feature #prerelease:beta" "" "alpha beta rc preview canary dev" "conventional-commits")
run_test "Hashtag #prerelease: marker works in CC mode" "beta" "$result"

# --- No marker: return workflow input unchanged ---
result=$(resolve_commit_prerelease_suffix "feat: add feature" "alpha" "alpha beta rc" "conventional-commits")
run_test "No commit-message marker returns workflow suffix unchanged" "alpha" "$result"

result=$(resolve_commit_prerelease_suffix "Fix bug without marker" "" "alpha beta rc")
run_test "No commit-message marker and no workflow suffix returns empty" "" "$result"

# --- Skip markers don't interfere with suffix detection (skip is handled upstream) ---
result=$(resolve_commit_prerelease_suffix "Hotfix #skip #prerelease:alpha")
run_test "Suffix detected even alongside #skip marker (skip handled upstream)" "alpha" "$result"

# --- Breaking-change lines with scope hint ---
result=$(resolve_commit_prerelease_suffix "feat(pre:alpha)!: drop v1 API" "" "alpha beta rc preview canary dev" "conventional-commits")
run_test "CC breaking-change feat(pre:alpha)!: scope hint sets suffix" "alpha" "$result"

result=$(resolve_commit_prerelease_suffix "fix(pre:rc)!: rename config keys" "" "alpha beta rc preview canary dev" "conventional-commits")
run_test "CC breaking-change fix(pre:rc)!: scope hint sets suffix" "rc" "$result"

# --- Uppercase scope hint normalises correctly ---
result=$(resolve_commit_prerelease_suffix "feat(Pre:ALPHA): add feature" "" "alpha beta rc preview canary dev" "conventional-commits")
run_test "CC scope hint feat(Pre:ALPHA): case-normalised to alpha" "alpha" "$result"

result=$(resolve_commit_prerelease_suffix "feat(PRE:beta)!: breaking" "" "alpha beta rc preview canary dev" "conventional-commits")
run_test "CC breaking-change scope hint PRE:beta case-normalised to beta" "beta" "$result"

# --- Footer works in hashtag (default) mode too ---
result=$(resolve_commit_prerelease_suffix "$(printf 'bump\n\nPre-release: beta')" "" "alpha beta rc preview canary dev" "hashtag")
run_test "Pre-release: footer works in hashtag mode" "beta" "$result"

result=$(resolve_commit_prerelease_suffix "$(printf 'bump\n\nPRE-RELEASE: rc')" "" "alpha beta rc" "hashtag")
run_test "PRE-RELEASE: footer case-insensitive in hashtag mode" "rc" "$result"

# Resolve branch-name fallback bump level (mirrors detection logic in bump-version.sh).
# NOTE: Keep in sync with scripts/bump-version.sh branch-name fallback block.
# Args: branch_name [branch_prefix_map]
# Returns the bump level (major/minor/patch) or empty string when prefix not in map.
resolve_branch_name_bump() {
    local branch_name="$1"
    local branch_prefix_map="${2:-feat=minor
feature=minor
fix=patch
hotfix=patch
bugfix=patch
breaking=major
major=major
minor=minor
patch=patch}"

    [[ -z "$branch_name" ]] && return 0

    local branch_prefix="${branch_name%%/*}"
    local branch_prefix_lower
    branch_prefix_lower=$(echo "$branch_prefix" | tr '[:upper:]' '[:lower:]')

    local bp_key bp_val
    while IFS='=' read -r bp_key bp_val; do
        bp_key=$(echo "$bp_key" | tr -d ' \t\r' | tr '[:upper:]' '[:lower:]')
        bp_val=$(echo "$bp_val" | tr -d ' \t\r' | tr '[:upper:]' '[:lower:]')
        if [[ -n "$bp_key" && "$bp_key" == "$branch_prefix_lower" ]]; then
            echo "$bp_val"
            return 0
        fi
    done <<< "$branch_prefix_map"
}

print_test_header "Branch-Name Fallback Bump Detection Tests"

DEFAULT_PREFIX_MAP="feat=minor
feature=minor
fix=patch
hotfix=patch
bugfix=patch
breaking=major
major=major
minor=minor
patch=patch"

# --- Default map: standard prefixes ---
result=$(resolve_branch_name_bump "feat/add-login" "$DEFAULT_PREFIX_MAP")
run_test "feat/ prefix → minor" "minor" "$result"

result=$(resolve_branch_name_bump "feature/redesign-dashboard" "$DEFAULT_PREFIX_MAP")
run_test "feature/ prefix → minor" "minor" "$result"

result=$(resolve_branch_name_bump "fix/null-pointer" "$DEFAULT_PREFIX_MAP")
run_test "fix/ prefix → patch" "patch" "$result"

result=$(resolve_branch_name_bump "hotfix/urgent-crash" "$DEFAULT_PREFIX_MAP")
run_test "hotfix/ prefix → patch" "patch" "$result"

result=$(resolve_branch_name_bump "bugfix/off-by-one" "$DEFAULT_PREFIX_MAP")
run_test "bugfix/ prefix → patch" "patch" "$result"

result=$(resolve_branch_name_bump "breaking/v2-api" "$DEFAULT_PREFIX_MAP")
run_test "breaking/ prefix → major" "major" "$result"

result=$(resolve_branch_name_bump "major/new-platform" "$DEFAULT_PREFIX_MAP")
run_test "major/ prefix → major" "major" "$result"

result=$(resolve_branch_name_bump "minor/small-api-change" "$DEFAULT_PREFIX_MAP")
run_test "minor/ prefix → minor" "minor" "$result"

result=$(resolve_branch_name_bump "patch/typo-fix" "$DEFAULT_PREFIX_MAP")
run_test "patch/ prefix → patch" "patch" "$result"

# --- Case insensitivity ---
result=$(resolve_branch_name_bump "FEAT/add-login" "$DEFAULT_PREFIX_MAP")
run_test "FEAT/ uppercase prefix case-normalised → minor" "minor" "$result"

result=$(resolve_branch_name_bump "Fix/null-check" "$DEFAULT_PREFIX_MAP")
run_test "Fix/ mixed-case prefix case-normalised → patch" "patch" "$result"

# --- Unknown prefix returns empty ---
result=$(resolve_branch_name_bump "chore/update-deps" "$DEFAULT_PREFIX_MAP")
run_test "Unknown prefix 'chore' returns empty" "" "$result"

result=$(resolve_branch_name_bump "dependabot/npm_and_yarn/lodash" "$DEFAULT_PREFIX_MAP")
run_test "dependabot/ prefix not in default map returns empty" "" "$result"

# --- No branch name returns empty ---
result=$(resolve_branch_name_bump "" "$DEFAULT_PREFIX_MAP")
run_test "Empty branch name returns empty" "" "$result"

# --- Custom map ---
result=$(resolve_branch_name_bump "chore/update-deps" "chore=patch
feat=minor")
run_test "Custom map: chore/ → patch" "patch" "$result"

result=$(resolve_branch_name_bump "release/v2" "release=major
feat=minor")
run_test "Custom map: release/ → major" "major" "$result"

# --- Branch without slash uses whole name as prefix ---
result=$(resolve_branch_name_bump "feat" "$DEFAULT_PREFIX_MAP")
run_test "Branch name without slash: 'feat' matches prefix" "minor" "$result"

# --- Ticket ID in branch name (common pattern) ---
result=$(resolve_branch_name_bump "feat/add-login" "$DEFAULT_PREFIX_MAP")
run_test "feat/TICKET-ID-description extracts 'feat' prefix" "minor" "$result"

result=$(resolve_branch_name_bump "fix/null-check" "$DEFAULT_PREFIX_MAP")
run_test "fix/TICKET-ID-description extracts 'fix' prefix" "patch" "$result"

# Determine effective pre-release mode (mirrors PRERELEASE_MODE logic in bump-version.sh).
# NOTE: Keep in sync with scripts/bump-version.sh PRERELEASE_MODE determination block.
# Args: commit_msg default_bump [prerelease_suffix]
# Returns: "stable", "named", or "counter-only"
determine_prerelease_mode() {
    local commit_msg="$1"
    local default_bump="${2:-patch}"
    local prerelease_suffix="${3:-}"

    local lower_msg
    lower_msg=$(echo "$commit_msg" | tr '[:upper:]' '[:lower:]')

    # Check #stable / #release escape hatch
    if [[ "$lower_msg" == *"#stable"* || "$lower_msg" == *"#release"* ]]; then
        echo "stable"
        return 0
    fi

    # Check bare #prerelease / #pre (counter-only from commit)
    local bare_re='#(prerelease|pre)([^:a-zA-Z0-9]|$)'
    local named_re='#(prerelease|pre):([a-zA-Z][a-zA-Z0-9]*)'
    if [[ "$lower_msg" =~ $named_re ]]; then
        # Named suffix from commit message
        echo "named"
        return 0
    elif [[ "$lower_msg" =~ $bare_re ]]; then
        echo "counter-only"
        return 0
    fi

    # Named pre-release suffix set (workflow input or commit-message detection)
    if [[ -n "$prerelease_suffix" ]]; then
        echo "named"
        return 0
    fi

    # default_bump=prerelease (or compound variant) with no explicit marker → counter-only
    local _is_prerelease_default=false
    case "$default_bump" in
        prerelease|patch-prerelease|minor-prerelease|major-prerelease)
            _is_prerelease_default=true ;;
    esac
    if $_is_prerelease_default; then
        # Determine if commit has explicit marker
        local explicit=false
        local named_re2='#(prerelease|pre):([a-zA-Z][a-zA-Z0-9]*)'
        if [[ "$lower_msg" =~ $named_re2 ]]; then
            explicit=true
        elif [[ "$lower_msg" == *"#major"* || "$lower_msg" == *"#minor"* || "$lower_msg" == *"#patch"* ]]; then
            explicit=true
        fi
        if ! $explicit; then
            echo "counter-only"
            return 0
        fi
    fi

    echo "stable"
}

print_test_header "Pre-Release Mode Determination Tests"

# --- #stable / #release escape hatch ---
result=$(determine_prerelease_mode "Release v2 #stable" "patch" "alpha")
run_test "#stable marker → stable (overrides suffix)" "stable" "$result"

result=$(determine_prerelease_mode "Release #release" "prerelease" "")
run_test "#release marker → stable (overrides default_bump=prerelease)" "stable" "$result"

# --- Bare #prerelease / #pre → counter-only ---
result=$(determine_prerelease_mode "Hotfix #prerelease" "patch" "")
run_test "Bare #prerelease → counter-only" "counter-only" "$result"

result=$(determine_prerelease_mode "Hotfix #pre" "patch" "")
run_test "Bare #pre → counter-only" "counter-only" "$result"

result=$(determine_prerelease_mode "Hotfix #prerelease" "patch" "alpha")
run_test "Bare #prerelease overrides workflow suffix → counter-only" "counter-only" "$result"

# --- Named suffix (workflow or commit-message) ---
result=$(determine_prerelease_mode "Fix bug" "patch" "alpha")
run_test "Workflow suffix alpha → named" "named" "$result"

result=$(determine_prerelease_mode "Fix bug #prerelease:beta" "patch" "")
run_test "#prerelease:beta → named" "named" "$result"

# --- default_bump=prerelease: no explicit marker → counter-only ---
result=$(determine_prerelease_mode "Routine commit" "prerelease" "")
run_test "default_bump=prerelease + no marker + no suffix → counter-only" "counter-only" "$result"

result=$(determine_prerelease_mode "Routine commit" "prerelease" "alpha")
run_test "default_bump=prerelease + no marker + suffix → named" "named" "$result"

# --- default_bump=prerelease: explicit marker → stable (when no suffix) ---
result=$(determine_prerelease_mode "Add feature #minor" "prerelease" "")
run_test "default_bump=prerelease + #minor + no suffix → stable" "stable" "$result"

result=$(determine_prerelease_mode "Add feature #major" "prerelease" "")
run_test "default_bump=prerelease + #major + no suffix → stable" "stable" "$result"

# --- default_bump=prerelease: explicit marker + named suffix → named ---
result=$(determine_prerelease_mode "Add feature #minor" "prerelease" "alpha")
run_test "default_bump=prerelease + #minor + suffix alpha → named" "named" "$result"

# --- Plain stable (no special config) ---
result=$(determine_prerelease_mode "Fix bug" "patch" "")
run_test "No pre-release config → stable" "stable" "$result"

# --- calculate_new_version handles prerelease as patch ---
result=$(calculate_new_version "1.2.3" "Routine commit" "prerelease")
run_test "default_bump=prerelease maps to patch version bump (1.2.4)" "1.2.4" "$result"

result=$(calculate_new_version "1.2.3" "Add feature #minor" "prerelease")
run_test "default_bump=prerelease + #minor → minor bump (1.3.0)" "1.3.0" "$result"

# --- Compound prerelease default_bump Tests ---
print_test_header "Compound Pre-Release Default Bump Tests"

# calculate_new_version: base-version calculation
result=$(calculate_new_version "1.2.3" "Routine commit" "minor-prerelease")
run_test "default_bump=minor-prerelease → minor base version (1.3.0)" "1.3.0" "$result"

result=$(calculate_new_version "1.2.3" "Routine commit" "major-prerelease")
run_test "default_bump=major-prerelease → major base version (2.0.0)" "2.0.0" "$result"

result=$(calculate_new_version "1.2.3" "Routine commit" "patch-prerelease")
run_test "default_bump=patch-prerelease → patch base version (1.2.4)" "1.2.4" "$result"

# CC-mode: type not in cc_type_map falls back to compound default_bump
result=$(calculate_new_version "1.2.3" "chore: routine maintenance" "minor-prerelease")
run_test "CC chore + default_bump=minor-prerelease → minor base version (1.3.0)" "1.3.0" "$result"

result=$(calculate_new_version "1.2.3" "chore: routine maintenance" "major-prerelease")
run_test "CC chore + default_bump=major-prerelease → major base version (2.0.0)" "2.0.0" "$result"

# Explicit markers override compound defaults
result=$(calculate_new_version "1.2.3" "Bug fix #patch" "minor-prerelease")
run_test "default_bump=minor-prerelease + #patch → patch (1.2.4)" "1.2.4" "$result"

result=$(calculate_new_version "1.2.3" "Add feature #minor" "major-prerelease")
run_test "default_bump=major-prerelease + #minor → minor (1.3.0)" "1.3.0" "$result"

result=$(calculate_new_version "1.2.3" "Breaking #major" "minor-prerelease")
run_test "default_bump=minor-prerelease + #major → major (2.0.0)" "2.0.0" "$result"

# determine_prerelease_mode: compound defaults
result=$(determine_prerelease_mode "Routine commit" "minor-prerelease" "")
run_test "default_bump=minor-prerelease + no marker + no suffix → counter-only" "counter-only" "$result"

result=$(determine_prerelease_mode "Routine commit" "major-prerelease" "")
run_test "default_bump=major-prerelease + no marker + no suffix → counter-only" "counter-only" "$result"

result=$(determine_prerelease_mode "Routine commit" "patch-prerelease" "")
run_test "default_bump=patch-prerelease + no marker + no suffix → counter-only" "counter-only" "$result"

result=$(determine_prerelease_mode "Routine commit" "minor-prerelease" "alpha")
run_test "default_bump=minor-prerelease + no marker + suffix → named" "named" "$result"

result=$(determine_prerelease_mode "Add feature #minor" "minor-prerelease" "")
run_test "default_bump=minor-prerelease + #minor + no suffix → stable" "stable" "$result"

result=$(determine_prerelease_mode "Release v2 #stable" "minor-prerelease" "alpha")
run_test "#stable overrides default_bump=minor-prerelease + suffix → stable" "stable" "$result"

result=$(determine_prerelease_mode "Release #release" "major-prerelease" "")
run_test "#release overrides default_bump=major-prerelease → stable" "stable" "$result"

# Print test summary
print_test_header "Test Summary"
echo "Tests run: $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}All tests passed! 🎉${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed. 😞${NC}"
    exit 1
fi
