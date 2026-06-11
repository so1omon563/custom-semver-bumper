#!/usr/bin/env bats

# BATS (Bash Automated Testing System) tests for Custom Version Bumper Action
# Install bats: brew install bats-core (on macOS) or see https://github.com/bats-core/bats-core

setup() {
    # Create a temporary directory for each test
    TEST_TEMP_DIR="$(mktemp -d)"
    ORIGINAL_DIR="$(pwd)"
    export TEST_TEMP_DIR ORIGINAL_DIR
    cd "$TEST_TEMP_DIR" || return 1
    
    # Initialize git repository
    git init --quiet
    git config user.name "Test User"
    git config user.email "test@example.com"
    
    # Create initial commit
    echo "Initial content" > README.md
    git add README.md
    git commit --quiet -m "Initial commit"
    
    # Load the version bumping functions
    # shellcheck disable=SC1091  # path resolved dynamically via $BATS_TEST_DIRNAME
    source "$BATS_TEST_DIRNAME/test_helpers.sh"
}

teardown() {
    # Cleanup
    cd "$ORIGINAL_DIR" || return 1
    rm -rf "$TEST_TEMP_DIR"
}

@test "calculate_new_version: patch bump by default" {
    result=$(calculate_new_version "1.2.3" "Fix bug in function")
    [ "$result" = "1.2.4" ]
}

@test "calculate_new_version: patch bump from 0.0.1" {
    result=$(calculate_new_version "0.0.1" "Small fix")
    [ "$result" = "0.0.2" ]
}

@test "calculate_new_version: minor bump with #minor tag" {
    result=$(calculate_new_version "1.2.3" "Add new feature #minor")
    [ "$result" = "1.3.0" ]
}

@test "calculate_new_version: major bump with #major tag" {
    result=$(calculate_new_version "1.2.3" "Breaking change #major")
    [ "$result" = "2.0.0" ]
}

@test "calculate_new_version: case insensitive #MINOR" {
    result=$(calculate_new_version "1.0.0" "Feature #MINOR")
    [ "$result" = "1.1.0" ]
}

@test "calculate_new_version: case insensitive #MAJOR" {
    result=$(calculate_new_version "1.0.0" "Breaking #MAJOR")
    [ "$result" = "2.0.0" ]
}

@test "calculate_new_version: multiple tags uses higher precedence" {
    result=$(calculate_new_version "1.0.0" "Change #minor #major")
    [ "$result" = "2.0.0" ]
}

@test "calculate_new_version: word 'major' without # should be patch" {
    result=$(calculate_new_version "1.0.0" "This is a major improvement")
    [ "$result" = "1.0.1" ]
}

@test "calculate_new_version: #minor at different positions" {
    result1=$(calculate_new_version "1.0.0" "#minor at beginning")
    result2=$(calculate_new_version "1.0.0" "In middle #minor here")
    result3=$(calculate_new_version "1.0.0" "At end #minor")
    
    [ "$result1" = "1.1.0" ]
    [ "$result2" = "1.1.0" ]
    [ "$result3" = "1.1.0" ]
}

@test "extract_major_version: extract major from version string" {
    result1=$(extract_major_version "1.2.3")
    result2=$(extract_major_version "10.0.0")
    result3=$(extract_major_version "0.5.1")
    
    [ "$result1" = "1" ]
    [ "$result2" = "10" ]
    [ "$result3" = "0" ]
}

@test "git operations: no existing tags returns v0.0.0" {
    latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    [ "$latest_tag" = "v0.0.0" ]
}

@test "git operations: get latest tag with multiple tags" {
    git tag -a "v1.0.0" -m "Version 1.0.0"
    
    # Create new commit for next tag
    echo "Update 1" >> README.md
    git add README.md
    git commit --quiet -m "Update 1"
    git tag -a "v1.1.0" -m "Version 1.1.0" 
    
    # Create another commit for final tag
    echo "Update 2" >> README.md
    git add README.md
    git commit --quiet -m "Update 2"
    git tag -a "v1.1.5" -m "Version 1.1.5"
    
    latest_tag=$(git describe --tags --abbrev=0)
    [ "$latest_tag" = "v1.1.5" ]
}

@test "git operations: create new tag" {
    git tag -a "v1.0.1" -m "Version 1.0.1"
    git tag -l | grep -q "v1.0.1"
}

@test "git operations: parse commit message for version bump indicators" {
    echo "Feature" >> README.md
    git add README.md
    git commit --quiet -m "Merge PR: Add feature #minor"
    
    merge_commit_msg=$(git log -1 --pretty=%B)
    [[ $merge_commit_msg == *"#minor"* ]]
}

@test "git operations: configure user name and email" {
    git config user.name "GitHub Actions"
    git config user.email "actions@github.com"
    
    configured_name=$(git config user.name)
    configured_email=$(git config user.email)
    
    [ "$configured_name" = "GitHub Actions" ]
    [ "$configured_email" = "actions@github.com" ]
}

@test "version parsing: handle edge case versions" {
    # Test parsing different version formats
    versions=("0.0.0" "0.1.0" "1.0.0" "10.20.30" "999.999.999")
    
    for version in "${versions[@]}"; do
        IFS='.' read -ra VERSION_PARTS <<< "$version"
        major=${VERSION_PARTS[0]}
        minor=${VERSION_PARTS[1]}
        patch=${VERSION_PARTS[2]}
        
        # Reconstruct version to verify parsing
        reconstructed="$major.$minor.$patch"
        [ "$reconstructed" = "$version" ]
    done
}

@test "major tag movement: simulate tag deletion and recreation" {
    # Setup initial state
    git tag -a "v1.0.0" -m "Version 1.0.0"
    git tag -a "v1" -m "Major tag v1"
    
    # Create new commit for new version
    echo "New feature" >> README.md
    git add README.md
    git commit --quiet -m "Add new feature"
    
    # Create new version tag
    new_tag="v1.1.0"
    git tag -a "$new_tag" -m "Version 1.1.0"
    
    # Simulate major tag movement
    major_tag="v1"
    git tag -d "$major_tag"
    git tag -a "$major_tag" -m "Move major tag to $new_tag"
    
    # Verify both tags exist and point to same commit
    git tag -l | grep -q "$new_tag"
    git tag -l | grep -q "$major_tag"
    
    major_commit=$(git rev-list -n 1 "$major_tag")
    new_commit=$(git rev-list -n 1 "$new_tag")
    [ "$major_commit" = "$new_commit" ]
}

@test "calculate_new_version: handles major-only version like v1" {
    result=$(calculate_new_version "1" "Fix bug")
    [ "$result" = "1.0.1" ]
}

@test "calculate_new_version: handles major.minor version like v1.2" {
    result=$(calculate_new_version "1.2" "Fix bug")
    [ "$result" = "1.2.1" ]
}

@test "calculate_new_version: handles major-only with minor bump" {
    result=$(calculate_new_version "1" "Add feature #minor")
    [ "$result" = "1.1.0" ]
}

@test "calculate_new_version: handles major-only with major bump" {
    result=$(calculate_new_version "1" "Breaking change #major")
    [ "$result" = "2.0.0" ]
}

@test "calculate_new_version: handles invalid version gracefully" {
    result=$(calculate_new_version "invalid" "Fix bug")
    [ "$result" = "0.0.1" ]
}

@test "calculate_new_version: handles empty version gracefully" {
    result=$(calculate_new_version "" "Fix bug")
    [ "$result" = "0.0.1" ]
}

# ── Skip Marker Tests ──────────────────────────────────────────────────────────

@test "skip markers: #skip triggers skip" {
    result=$(calculate_new_version "1.0.0" "Deploy hotfix #skip" "patch")
    [ "$result" = "skip" ]
}

@test "skip markers: #no-bump triggers skip" {
    result=$(calculate_new_version "1.0.0" "No bump #no-bump" "patch")
    [ "$result" = "skip" ]
}

@test "skip markers: #skip-version triggers skip" {
    result=$(calculate_new_version "1.0.0" "Skip this #skip-version" "patch")
    [ "$result" = "skip" ]
}

@test "skip markers: #SKIP uppercase triggers skip" {
    result=$(calculate_new_version "1.0.0" "Deploy #SKIP" "patch")
    [ "$result" = "skip" ]
}

@test "skip markers: skip overrides #minor" {
    result=$(calculate_new_version "1.0.0" "New feature #minor #skip" "patch")
    [ "$result" = "skip" ]
}

# ── Explicit #patch Marker Tests ───────────────────────────────────────────────

@test "calculate_new_version: explicit #patch marker produces patch bump" {
    result=$(calculate_new_version "1.2.3" "Explicit patch #patch" "patch")
    [ "$result" = "1.2.4" ]
}

@test "calculate_new_version: #patch marker overrides default_bump=none" {
    result=$(calculate_new_version "1.2.3" "Fix thing #patch" "none")
    [ "$result" = "1.2.4" ]
}

# ── Configurable default_bump Tests ───────────────────────────────────────────

@test "default_bump=minor: no marker produces minor bump" {
    result=$(calculate_new_version "1.2.3" "No marker here" "minor")
    [ "$result" = "1.3.0" ]
}

@test "default_bump=major: no marker produces major bump" {
    result=$(calculate_new_version "1.2.3" "No marker here" "major")
    [ "$result" = "2.0.0" ]
}

@test "default_bump=none: no marker skips the bump" {
    result=$(calculate_new_version "1.2.3" "No marker here" "none")
    [ "$result" = "skip" ]
}

@test "default_bump=none: explicit #minor marker still bumps" {
    result=$(calculate_new_version "1.2.3" "Feature #minor" "none")
    [ "$result" = "1.3.0" ]
}

@test "default_bump=none: explicit #major marker still bumps" {
    result=$(calculate_new_version "1.2.3" "Breaking #major" "none")
    [ "$result" = "2.0.0" ]
}

@test "default_bump=none: explicit #patch marker still bumps" {
    result=$(calculate_new_version "1.2.3" "Fix it #patch" "none")
    [ "$result" = "1.2.4" ]
}

# ── Pre-release Helper Tests ───────────────────────────────────────────────────

@test "calculate_new_version_prerelease: first alpha tag starts at .1" {
    result=$(calculate_new_version_prerelease "1.0.0" "Feature #minor" "patch" "alpha" 0)
    [ "$result" = "1.1.0-alpha.1" ]
}

@test "calculate_new_version_prerelease: counter increments from existing" {
    result=$(calculate_new_version_prerelease "1.0.0" "Feature #minor" "patch" "alpha" 3)
    [ "$result" = "1.1.0-alpha.4" ]
}

@test "calculate_new_version_prerelease: different suffixes work" {
    result_beta=$(calculate_new_version_prerelease "1.0.0" "Fix #patch" "patch" "beta" 0)
    result_rc=$(calculate_new_version_prerelease "1.0.0" "Fix #patch" "patch" "rc" 1)
    [ "$result_beta" = "1.0.1-beta.1" ]
    [ "$result_rc" = "1.0.1-rc.2" ]
}

@test "calculate_new_version_prerelease: skip marker still skips" {
    result=$(calculate_new_version_prerelease "1.0.0" "No bump #skip" "patch" "alpha" 0)
    [ "$result" = "skip" ]
}

# ── Minor Tag Movement Tests ───────────────────────────────────────────────────

@test "minor tag movement: simulate tag deletion and recreation" {
    git tag -a "v1.2.0" -m "Version 1.2.0"
    git tag -a "v1.2" -m "Minor tag v1.2"

    echo "Patch fix" >> README.md
    git add README.md
    git commit --quiet -m "Patch fix"

    new_tag="v1.2.1"
    minor_tag="v1.2"

    git tag -a "$new_tag" -m "Bump version to $new_tag"
    git tag -d "$minor_tag"
    git tag -a "$minor_tag" -m "Move minor tag to $new_tag"

    git tag -l | grep -q "$new_tag"
    git tag -l | grep -q "$minor_tag"

    minor_commit=$(git rev-list -n 1 "$minor_tag")
    new_commit=$(git rev-list -n 1 "$new_tag")
    [ "$minor_commit" = "$new_commit" ]
}
# ── Conventional Commits Mode Tests ───────────────────────────────────────────

DEFAULT_CC_MAP="feat=minor
fix=patch"

@test "conventional commits: feat: produces minor bump" {
    result=$(calculate_new_version "1.2.3" "feat: add new feature" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
    [ "$result" = "1.3.0" ]
}

@test "conventional commits: fix: produces patch bump" {
    result=$(calculate_new_version "1.2.3" "fix: correct null pointer" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
    [ "$result" = "1.2.4" ]
}

@test "conventional commits: feat!: produces major bump" {
    result=$(calculate_new_version "1.2.3" "feat!: remove deprecated API" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
    [ "$result" = "2.0.0" ]
}

@test "conventional commits: fix!: produces major bump" {
    result=$(calculate_new_version "1.2.3" "fix!: rename config keys" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
    [ "$result" = "2.0.0" ]
}

@test "conventional commits: BREAKING CHANGE footer produces major bump" {
    msg="$(printf 'feat: add thing\n\nBREAKING CHANGE: removed old API')"
    result=$(calculate_new_version "1.2.3" "$msg" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
    [ "$result" = "2.0.0" ]
}

@test "conventional commits: feat(scope): produces minor bump" {
    result=$(calculate_new_version "1.2.3" "feat(auth): add OAuth support" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
    [ "$result" = "1.3.0" ]
}

@test "conventional commits: feat(scope)!: produces major bump" {
    result=$(calculate_new_version "1.2.3" "feat(api)!: remove endpoint" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
    [ "$result" = "2.0.0" ]
}

@test "conventional commits: unknown type falls through to default_bump" {
    result=$(calculate_new_version "1.2.3" "chore: update dependencies" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
    [ "$result" = "1.2.4" ]
}

@test "conventional commits: #skip escape hatch honored in cc mode" {
    result=$(calculate_new_version "1.2.3" "feat: new thing #skip" "patch" "conventional-commits" "$DEFAULT_CC_MAP")
    [ "$result" = "skip" ]
}

@test "conventional commits: custom map extends built-in types" {
    extended_map="feat=minor
fix=patch
perf=patch"
    result=$(calculate_new_version "1.2.3" "perf: optimise query execution" "patch" "conventional-commits" "$extended_map")
    [ "$result" = "1.2.4" ]
}

@test "conventional commits: hashtag mode unaffected (regression)" {
    result=$(calculate_new_version "1.2.3" "fix: bug fix" "patch" "hashtag" "$DEFAULT_CC_MAP")
    [ "$result" = "1.2.4" ]
}

# ── Commit-Message Pre-Release Suffix Detection Tests ─────────────────────────

@test "prerelease suffix: #prerelease:alpha sets suffix" {
    result=$(resolve_commit_prerelease_suffix "Add feature #minor #prerelease:alpha")
    [ "$result" = "alpha" ]
}

@test "prerelease suffix: #pre:beta alias sets suffix" {
    result=$(resolve_commit_prerelease_suffix "Add feature #pre:beta")
    [ "$result" = "beta" ]
}

@test "prerelease suffix: #prerelease:rc sets suffix" {
    result=$(resolve_commit_prerelease_suffix "Release candidate #prerelease:rc")
    [ "$result" = "rc" ]
}

@test "prerelease suffix: case-insensitive #PRERELEASE:ALPHA" {
    result=$(resolve_commit_prerelease_suffix "Feature #PRERELEASE:ALPHA")
    [ "$result" = "alpha" ]
}

@test "prerelease suffix: commit message overrides workflow input" {
    result=$(resolve_commit_prerelease_suffix "Fix #prerelease:beta" "alpha")
    [ "$result" = "beta" ]
}

@test "prerelease suffix: invalid suffix falls back to workflow input" {
    result=$(resolve_commit_prerelease_suffix "Deploy #prerelease:snapshot" "alpha")
    [ "$result" = "alpha" ]
}

@test "prerelease suffix: invalid suffix with empty workflow input returns empty" {
    result=$(resolve_commit_prerelease_suffix "Deploy #prerelease:snapshot" "")
    [ "$result" = "" ]
}

@test "prerelease suffix: custom allowed list accepts snapshot" {
    result=$(resolve_commit_prerelease_suffix "Deploy #prerelease:snapshot" "" "alpha beta snapshot")
    [ "$result" = "snapshot" ]
}

@test "prerelease suffix: alpha excluded from custom allowed list falls back" {
    result=$(resolve_commit_prerelease_suffix "Deploy #prerelease:alpha" "" "beta rc")
    [ "$result" = "" ]
}

@test "prerelease suffix: CC scope hint feat(pre:alpha): sets suffix" {
    result=$(resolve_commit_prerelease_suffix "feat(pre:alpha): add login" "" "alpha beta rc preview canary dev" "conventional-commits")
    [ "$result" = "alpha" ]
}

@test "prerelease suffix: CC scope hint fix(pre:rc): sets suffix" {
    result=$(resolve_commit_prerelease_suffix "fix(pre:rc): null check" "" "alpha beta rc preview canary dev" "conventional-commits")
    [ "$result" = "rc" ]
}

@test "prerelease suffix: CC normal scope does not set suffix" {
    result=$(resolve_commit_prerelease_suffix "feat(auth): normal scope" "" "alpha beta rc preview canary dev" "conventional-commits")
    [ "$result" = "" ]
}

@test "prerelease suffix: CC scope hint overrides workflow input" {
    result=$(resolve_commit_prerelease_suffix "feat(pre:alpha): add login" "beta" "alpha beta rc preview canary dev" "conventional-commits")
    [ "$result" = "alpha" ]
}

@test "prerelease suffix: Pre-release: footer sets suffix" {
    msg="$(printf 'feat: add feature\n\nPre-release: beta')"
    result=$(resolve_commit_prerelease_suffix "$msg" "" "alpha beta rc preview canary dev" "conventional-commits")
    [ "$result" = "beta" ]
}

@test "prerelease suffix: Prerelease: footer (no hyphen) sets suffix" {
    msg="$(printf 'feat: add feature\n\nPrerelease: rc')"
    result=$(resolve_commit_prerelease_suffix "$msg" "" "alpha beta rc preview canary dev" "conventional-commits")
    [ "$result" = "rc" ]
}

@test "prerelease suffix: PRE-RELEASE: footer case-insensitive sets suffix" {
    msg="$(printf 'feat: add feature\n\nPRE-RELEASE: alpha')"
    result=$(resolve_commit_prerelease_suffix "$msg" "" "alpha beta rc preview canary dev" "conventional-commits")
    [ "$result" = "alpha" ]
}

@test "prerelease suffix: footer wins over scope and hashtag" {
    msg="$(printf 'feat(pre:alpha): add thing #prerelease:beta\n\nPre-release: rc')"
    result=$(resolve_commit_prerelease_suffix "$msg" "" "alpha beta rc" "conventional-commits")
    [ "$result" = "rc" ]
}

@test "prerelease suffix: scope wins over hashtag when no footer" {
    msg="$(printf 'feat(pre:alpha): add thing #prerelease:beta')"
    result=$(resolve_commit_prerelease_suffix "$msg" "" "alpha beta rc" "conventional-commits")
    [ "$result" = "alpha" ]
}

@test "prerelease suffix: hashtag marker works in CC mode" {
    result=$(resolve_commit_prerelease_suffix "feat: add feature #prerelease:beta" "" "alpha beta rc preview canary dev" "conventional-commits")
    [ "$result" = "beta" ]
}

@test "prerelease suffix: no marker returns workflow suffix unchanged" {
    result=$(resolve_commit_prerelease_suffix "feat: add feature" "alpha" "alpha beta rc" "conventional-commits")
    [ "$result" = "alpha" ]
}

@test "prerelease suffix: no marker and no workflow suffix returns empty" {
    result=$(resolve_commit_prerelease_suffix "Fix bug without marker" "" "alpha beta rc")
    [ "$result" = "" ]
}

@test "prerelease suffix: CC breaking-change feat(pre:alpha)!: scope hint sets suffix" {
    result=$(resolve_commit_prerelease_suffix "feat(pre:alpha)!: drop v1 API" "" "alpha beta rc preview canary dev" "conventional-commits")
    [ "$result" = "alpha" ]
}

@test "prerelease suffix: CC breaking-change fix(pre:rc)!: scope hint sets suffix" {
    result=$(resolve_commit_prerelease_suffix "fix(pre:rc)!: rename config keys" "" "alpha beta rc preview canary dev" "conventional-commits")
    [ "$result" = "rc" ]
}

@test "prerelease suffix: CC scope hint feat(Pre:ALPHA): case-normalised to alpha" {
    result=$(resolve_commit_prerelease_suffix "feat(Pre:ALPHA): add feature" "" "alpha beta rc preview canary dev" "conventional-commits")
    [ "$result" = "alpha" ]
}

@test "prerelease suffix: CC breaking-change scope hint PRE:beta case-normalised to beta" {
    result=$(resolve_commit_prerelease_suffix "feat(PRE:beta)!: breaking" "" "alpha beta rc preview canary dev" "conventional-commits")
    [ "$result" = "beta" ]
}

@test "prerelease suffix: Pre-release: footer works in hashtag mode" {
    msg="$(printf 'bump\n\nPre-release: beta')"
    result=$(resolve_commit_prerelease_suffix "$msg" "" "alpha beta rc preview canary dev" "hashtag")
    [ "$result" = "beta" ]
}

@test "prerelease suffix: PRE-RELEASE: footer case-insensitive in hashtag mode" {
    msg="$(printf 'bump\n\nPRE-RELEASE: rc')"
    result=$(resolve_commit_prerelease_suffix "$msg" "" "alpha beta rc" "hashtag")
    [ "$result" = "rc" ]
}

# ── Branch-Name Fallback Bump Detection Tests ─────────────────────────────────

DEFAULT_PREFIX_MAP="feat=minor
feature=minor
fix=patch
hotfix=patch
bugfix=patch
breaking=major
major=major
minor=minor
patch=patch"

@test "branch name: feat/ prefix → minor" {
    result=$(resolve_branch_name_bump "feat/add-login" "$DEFAULT_PREFIX_MAP")
    [ "$result" = "minor" ]
}

@test "branch name: feature/ prefix → minor" {
    result=$(resolve_branch_name_bump "feature/redesign" "$DEFAULT_PREFIX_MAP")
    [ "$result" = "minor" ]
}

@test "branch name: fix/ prefix → patch" {
    result=$(resolve_branch_name_bump "fix/null-pointer" "$DEFAULT_PREFIX_MAP")
    [ "$result" = "patch" ]
}

@test "branch name: hotfix/ prefix → patch" {
    result=$(resolve_branch_name_bump "hotfix/urgent-crash" "$DEFAULT_PREFIX_MAP")
    [ "$result" = "patch" ]
}

@test "branch name: breaking/ prefix → major" {
    result=$(resolve_branch_name_bump "breaking/v2-api" "$DEFAULT_PREFIX_MAP")
    [ "$result" = "major" ]
}

@test "branch name: FEAT/ uppercase case-normalised → minor" {
    result=$(resolve_branch_name_bump "FEAT/add-login" "$DEFAULT_PREFIX_MAP")
    [ "$result" = "minor" ]
}

@test "branch name: unknown prefix chore returns empty" {
    result=$(resolve_branch_name_bump "chore/update-deps" "$DEFAULT_PREFIX_MAP")
    [ "$result" = "" ]
}

@test "branch name: empty branch name returns empty" {
    result=$(resolve_branch_name_bump "" "$DEFAULT_PREFIX_MAP")
    [ "$result" = "" ]
}

@test "branch name: custom map chore=patch" {
    result=$(resolve_branch_name_bump "chore/update-deps" "chore=patch
feat=minor")
    [ "$result" = "patch" ]
}

@test "branch name: feat/TICKET-ID-description extracts feat prefix" {
    result=$(resolve_branch_name_bump "feat/add-login" "$DEFAULT_PREFIX_MAP")
    [ "$result" = "minor" ]
}

@test "branch name: fix/TICKET-ID-description extracts fix prefix" {
    result=$(resolve_branch_name_bump "fix/null-check" "$DEFAULT_PREFIX_MAP")
    [ "$result" = "patch" ]
}

@test "branch name: branch without slash uses whole name as prefix" {
    result=$(resolve_branch_name_bump "feat" "$DEFAULT_PREFIX_MAP")
    [ "$result" = "minor" ]
}

# ── Pre-Release Mode Determination Tests ──────────────────────────────────────

@test "prerelease mode: #stable overrides suffix → stable" {
    result=$(determine_prerelease_mode "Release v2 #stable" "patch" "alpha")
    [ "$result" = "stable" ]
}

@test "prerelease mode: #release overrides default_bump=prerelease → stable" {
    result=$(determine_prerelease_mode "Release #release" "prerelease" "")
    [ "$result" = "stable" ]
}

@test "prerelease mode: bare #prerelease → counter-only" {
    result=$(determine_prerelease_mode "Hotfix #prerelease" "patch" "")
    [ "$result" = "counter-only" ]
}

@test "prerelease mode: bare #pre → counter-only" {
    result=$(determine_prerelease_mode "Hotfix #pre" "patch" "")
    [ "$result" = "counter-only" ]
}

@test "prerelease mode: bare #prerelease overrides workflow suffix → counter-only" {
    result=$(determine_prerelease_mode "Hotfix #prerelease" "patch" "alpha")
    [ "$result" = "counter-only" ]
}

@test "prerelease mode: workflow suffix alpha → named" {
    result=$(determine_prerelease_mode "Fix bug" "patch" "alpha")
    [ "$result" = "named" ]
}

@test "prerelease mode: #prerelease:beta → named" {
    result=$(determine_prerelease_mode "Fix bug #prerelease:beta" "patch" "")
    [ "$result" = "named" ]
}

@test "prerelease mode: default_bump=prerelease + no marker + no suffix → counter-only" {
    result=$(determine_prerelease_mode "Routine commit" "prerelease" "")
    [ "$result" = "counter-only" ]
}

@test "prerelease mode: default_bump=prerelease + no marker + suffix → named" {
    result=$(determine_prerelease_mode "Routine commit" "prerelease" "alpha")
    [ "$result" = "named" ]
}

@test "prerelease mode: default_bump=prerelease + #minor + no suffix → stable" {
    result=$(determine_prerelease_mode "Add feature #minor" "prerelease" "")
    [ "$result" = "stable" ]
}

@test "prerelease mode: default_bump=prerelease + #minor + suffix → named" {
    result=$(determine_prerelease_mode "Add feature #minor" "prerelease" "alpha")
    [ "$result" = "named" ]
}

@test "prerelease mode: no config → stable" {
    result=$(determine_prerelease_mode "Fix bug" "patch" "")
    [ "$result" = "stable" ]
}

@test "calculate_new_version: default_bump=prerelease maps to patch bump" {
    result=$(calculate_new_version "1.2.3" "Routine commit" "prerelease")
    [ "$result" = "1.2.4" ]
}

@test "calculate_new_version: default_bump=prerelease + #minor → minor bump" {
    result=$(calculate_new_version "1.2.3" "Add feature #minor" "prerelease")
    [ "$result" = "1.3.0" ]
}

# --- Title-over-body marker priority tests ---

@test "title #minor overrides #skip in body (regression: PR #6 false positive)" {
    commit_msg="$(printf 'Add feature #minor\n\nThis commit documents skip (#skip) as an example.\nAlso mentions #no-bump and #skip-version in prose.')"
    result=$(calculate_new_version "1.0.2" "$commit_msg")
    [ "$result" = "1.1.0" ]
}

@test "title #major overrides #skip in body" {
    commit_msg="$(printf 'Breaking API change #major\n\nSkip example: use #skip to prevent a bump.')"
    result=$(calculate_new_version "1.0.2" "$commit_msg")
    [ "$result" = "2.0.0" ]
}

@test "title #patch overrides #skip in body" {
    commit_msg="$(printf 'Hotfix #patch\n\nTo skip a bump use #skip in your message.')"
    result=$(calculate_new_version "1.0.2" "$commit_msg")
    [ "$result" = "1.0.3" ]
}

@test "title #skip is honoured even when body contains #minor" {
    commit_msg="$(printf 'Deploy config #skip\n\nThis would normally be a #minor change.')"
    result=$(calculate_new_version "1.0.2" "$commit_msg")
    [ "$result" = "skip" ]
}

@test "no title marker + body #skip → skip (existing behavior preserved)" {
    commit_msg="$(printf 'Update docs\n\n#skip')"
    result=$(calculate_new_version "1.0.2" "$commit_msg")
    [ "$result" = "skip" ]
}

@test "no title marker + body #minor → minor bump (existing behavior preserved)" {
    commit_msg="$(printf 'Update docs\n\n#minor')"
    result=$(calculate_new_version "1.0.2" "$commit_msg")
    [ "$result" = "1.1.0" ]
}

@test "title #minor overrides #no-bump in body" {
    commit_msg="$(printf 'Add feature #minor\n\nUse #no-bump to skip.')"
    result=$(calculate_new_version "1.0.2" "$commit_msg")
    [ "$result" = "1.1.0" ]
}

@test "title #minor overrides #skip-version in body" {
    commit_msg="$(printf 'Add feature #minor\n\nUse #skip-version to skip.')"
    result=$(calculate_new_version "1.0.2" "$commit_msg")
    [ "$result" = "1.1.0" ]
}

# --- Configurable tag prefix tests ---

@test "tag prefix 'v' creates v-prefixed tag via simulate_version_bump" {
    # Exercises the prefix-aware path: simulate_version_bump with explicit 'v' prefix
    local tmpdir
    tmpdir=$(mktemp -d)
    (
        cd "$tmpdir"
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        git commit --allow-empty -m "init"
        git tag -a "v1.0.0" -m "initial"
        simulate_version_bump "Add feature #minor" "false" "false" "hashtag" "" "v"
        verify_tag_exists "v1.1.0"
    )
    local exit_code=$?
    rm -rf "$tmpdir"
    [ "$exit_code" -eq 0 ]
}

@test "simulate_version_bump with empty prefix creates bare tag" {
    # Integration test: simulate bump using '' as tag prefix
    local tmpdir
    tmpdir=$(mktemp -d)
    (
        cd "$tmpdir"
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        git commit --allow-empty -m "init"
        git tag -a "1.0.0" -m "initial"
        simulate_version_bump "Add feature #minor" "false" "false" "hashtag" "" ""
        verify_tag_exists "1.1.0"
    )
    local exit_code=$?
    rm -rf "$tmpdir"
    [ "$exit_code" -eq 0 ]
}

@test "simulate_version_bump with release- prefix creates release-X.Y.Z tag" {
    local tmpdir
    tmpdir=$(mktemp -d)
    (
        cd "$tmpdir"
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        git commit --allow-empty -m "init"
        git tag -a "release-1.2.3" -m "initial"
        simulate_version_bump "Fix issue #patch" "false" "false" "hashtag" "" "release-"
        verify_tag_exists "release-1.2.4"
    )
    local exit_code=$?
    rm -rf "$tmpdir"
    [ "$exit_code" -eq 0 ]
}

@test "simulate_version_bump with custom prefix major tag movement uses prefix" {
    local tmpdir
    tmpdir=$(mktemp -d)
    (
        cd "$tmpdir"
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        git commit --allow-empty -m "init"
        git tag -a "ver-1.2.3" -m "initial"
        simulate_version_bump "Add feature #minor" "true" "false" "hashtag" "" "ver-"
        verify_tag_exists "ver-1.3.0"
        verify_tag_exists "ver-1"
    )
    local exit_code=$?
    rm -rf "$tmpdir"
    [ "$exit_code" -eq 0 ]
}
