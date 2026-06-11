#!/usr/bin/env bats

# Script-level BATS tests for Custom Version Bumper Action
#
# Unlike test.bats (which tests helper functions from test_helpers.sh), these tests
# invoke scripts/bump-version.sh directly as a subprocess in an isolated Git repository.
# This directly addresses the concern that tests "only test the logic, not the scripts"
# by exercising the actual production script and asserting on its real side effects:
# Git tags created and $GITHUB_OUTPUT contents written.
#
# Requires bats-core: brew install bats-core (macOS) or see https://github.com/bats-core/bats-core

setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    ORIGINAL_DIR="$(pwd)"
    GITHUB_OUTPUT_FILE="$(mktemp)"
    export TEST_TEMP_DIR ORIGINAL_DIR GITHUB_OUTPUT_FILE

    cd "$TEST_TEMP_DIR" || return 1

    git init --quiet
    git config user.name "Test User"
    git config user.email "test@example.com"

    echo "Initial content" > README.md
    git add README.md
    git commit --quiet -m "Initial commit"

    # Set up a local bare remote so git push commands in the script succeed
    ORIGIN_DIR="$(mktemp -d)"
    export ORIGIN_DIR
    git init --bare "$ORIGIN_DIR" --quiet
    git remote add origin "$ORIGIN_DIR"
    git push origin HEAD:main --quiet 2>/dev/null \
        || git push origin HEAD:master --quiet 2>/dev/null \
        || true
}

teardown() {
    cd "$ORIGINAL_DIR" || return 1
    rm -rf "$TEST_TEMP_DIR" "$ORIGIN_DIR"
    rm -f "$GITHUB_OUTPUT_FILE"
}

# ── Baseline ──────────────────────────────────────────────────────────────────

@test "script: no existing tags → first tag is v0.0.1 (patch)" {
    echo "First work" >> README.md
    git add README.md
    git commit --quiet -m "Bootstrap project"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "v0.0.1"
    grep -q "new_version=v0.0.1" "$GITHUB_OUTPUT_FILE"
    grep -q "bump_type=patch" "$GITHUB_OUTPUT_FILE"
}

# ── Hashtag markers ───────────────────────────────────────────────────────────

@test "script: default patch bump (no marker)" {
    git tag -a "v1.2.3" -m "Version 1.2.3"
    git push origin "v1.2.3" --quiet

    echo "Bug fix" >> README.md
    git add README.md
    git commit --quiet -m "Fix null-pointer in user lookup"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "v1.2.4"
    grep -q "new_version=v1.2.4" "$GITHUB_OUTPUT_FILE"
    grep -q "bump_type=patch" "$GITHUB_OUTPUT_FILE"
    grep -q "previous_version=v1.2.3" "$GITHUB_OUTPUT_FILE"
}

@test "script: minor bump via #minor marker" {
    git tag -a "v1.2.3" -m "Version 1.2.3"
    git push origin "v1.2.3" --quiet

    echo "New feature" >> README.md
    git add README.md
    git commit --quiet -m "Add new authentication flow #minor"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "v1.3.0"
    grep -q "new_version=v1.3.0" "$GITHUB_OUTPUT_FILE"
    grep -q "bump_type=minor" "$GITHUB_OUTPUT_FILE"
    grep -q "previous_version=v1.2.3" "$GITHUB_OUTPUT_FILE"
}

@test "script: major bump via #major marker" {
    git tag -a "v1.2.3" -m "Version 1.2.3"
    git push origin "v1.2.3" --quiet

    echo "Breaking change" >> README.md
    git add README.md
    git commit --quiet -m "Remove deprecated API endpoints #major"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "v2.0.0"
    grep -q "new_version=v2.0.0" "$GITHUB_OUTPUT_FILE"
    grep -q "bump_type=major" "$GITHUB_OUTPUT_FILE"
    grep -q "previous_version=v1.2.3" "$GITHUB_OUTPUT_FILE"
}

@test "script: #skip marker skips version bump" {
    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "CI change" >> README.md
    git add README.md
    git commit --quiet -m "Update CI config #skip"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    # No new tag should be created
    [ "$(git tag -l "v*.*.*" | grep -cv -- '-')" -eq 1 ]
    grep -q "skipped=true" "$GITHUB_OUTPUT_FILE"
}

# ── Conventional Commits mode ─────────────────────────────────────────────────

@test "script: conventional commits - feat: triggers minor bump" {
    git tag -a "v2.0.0" -m "Version 2.0.0"
    git push origin "v2.0.0" --quiet

    echo "New feature" >> README.md
    git add README.md
    git commit --quiet -m "feat: add new login page"

    local cc_map
    cc_map="$(printf 'feat=minor\nfix=patch\nchore=patch')"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        MARKER_STYLE="conventional-commits" \
        CC_TYPE_MAP="$cc_map" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "v2.1.0"
    grep -q "new_version=v2.1.0" "$GITHUB_OUTPUT_FILE"
    grep -q "bump_type=minor" "$GITHUB_OUTPUT_FILE"
}

@test "script: conventional commits - fix: triggers patch bump" {
    git tag -a "v2.1.0" -m "Version 2.1.0"
    git push origin "v2.1.0" --quiet

    echo "Bug fix" >> README.md
    git add README.md
    git commit --quiet -m "fix: correct timeout handling"

    local cc_map
    cc_map="$(printf 'feat=minor\nfix=patch\nchore=patch')"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        MARKER_STYLE="conventional-commits" \
        CC_TYPE_MAP="$cc_map" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "v2.1.1"
    grep -q "new_version=v2.1.1" "$GITHUB_OUTPUT_FILE"
    grep -q "bump_type=patch" "$GITHUB_OUTPUT_FILE"
}

@test "script: conventional commits - feat!: triggers major bump" {
    git tag -a "v2.1.1" -m "Version 2.1.1"
    git push origin "v2.1.1" --quiet

    echo "Breaking change" >> README.md
    git add README.md
    git commit --quiet -m "feat!: remove legacy auth provider"

    local cc_map
    cc_map="$(printf 'feat=minor\nfix=patch\nchore=patch')"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        MARKER_STYLE="conventional-commits" \
        CC_TYPE_MAP="$cc_map" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "v3.0.0"
    grep -q "new_version=v3.0.0" "$GITHUB_OUTPUT_FILE"
    grep -q "bump_type=major" "$GITHUB_OUTPUT_FILE"
}

# ── Pre-release ───────────────────────────────────────────────────────────────

@test "script: #prerelease:alpha hashtag creates named pre-release tag" {
    git tag -a "v1.5.0" -m "Version 1.5.0"
    git push origin "v1.5.0" --quiet

    echo "Experimental" >> README.md
    git add README.md
    git commit --quiet -m "Add experimental search #prerelease:alpha"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        ALLOWED_PRERELEASE_SUFFIXES="alpha beta rc" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "v1.5.1-alpha.1"
    grep -q "new_version=v1.5.1-alpha.1" "$GITHUB_OUTPUT_FILE"
}

@test "script: #stable escape hatch clears pre-release mode" {
    git tag -a "v5.0.0" -m "Version 5.0.0"
    git push origin "v5.0.0" --quiet

    echo "Release" >> README.md
    git add README.md
    git commit --quiet -m "Promote to stable #minor #stable"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        DEFAULT_BUMP="prerelease" \
        PRERELEASE_SUFFIX="alpha" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "v5.1.0"
    # No pre-release tag should be created despite prerelease mode being active
    [ "$(git tag -l | grep -c 'v5.1.0-')" -eq 0 ]
    grep -q "new_version=v5.1.0" "$GITHUB_OUTPUT_FILE"
}

# ── Branch name fallback ──────────────────────────────────────────────────────

@test "script: feat/ branch name triggers minor bump when no commit marker" {
    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "New login flow" >> README.md
    git add README.md
    git commit --quiet -m "Add new login flow"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        BRANCH_NAME="feat/add-login" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "v1.1.0"
    grep -q "new_version=v1.1.0" "$GITHUB_OUTPUT_FILE"
    grep -q "bump_type=minor" "$GITHUB_OUTPUT_FILE"
}

@test "script: commit marker wins over branch name" {
    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "Breaking change" >> README.md
    git add README.md
    git commit --quiet -m "Breaking API change #major"

    # fix/ branch prefix would imply patch, but explicit #major in commit wins
    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        BRANCH_NAME="fix/some-fix" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "v2.0.0"
    grep -q "new_version=v2.0.0" "$GITHUB_OUTPUT_FILE"
    grep -q "bump_type=major" "$GITHUB_OUTPUT_FILE"
}

# ── Major tag movement ────────────────────────────────────────────────────────

@test "script: move_major_tag=true creates floating major version tag" {
    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "New feature" >> README.md
    git add README.md
    git commit --quiet -m "Add search feature #minor"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        MOVE_MAJOR_TAG="true" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "v1.1.0"
    git tag -l | grep -qx "v1"
    grep -q "new_version=v1.1.0" "$GITHUB_OUTPUT_FILE"
}

@test "script: move_minor_tag=true creates floating minor version tag" {
    git tag -a "v2.0.0" -m "Version 2.0.0"
    git push origin "v2.0.0" --quiet

    echo "New feature" >> README.md
    git add README.md
    git commit --quiet -m "Add dashboard feature #minor"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        MOVE_MINOR_TAG="true" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "v2.1.0"
    git tag -l | grep -qx "v2.1"
    grep -q "new_version=v2.1.0" "$GITHUB_OUTPUT_FILE"
}

@test "script: custom BRANCH_PREFIX_MAP overrides default prefix mapping" {
    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "Deploy prep" >> README.md
    git add README.md
    # 'deploy' is not in the default prefix map; a custom map maps it to major
    git commit --quiet -m "Prepare deployment changes"

    local custom_map
    custom_map="$(printf 'deploy=major\nfeat=minor')"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        BRANCH_NAME="deploy/prod-release" \
        BRANCH_PREFIX_MAP="$custom_map" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "v2.0.0"
    grep -q "new_version=v2.0.0" "$GITHUB_OUTPUT_FILE"
    grep -q "bump_type=major" "$GITHUB_OUTPUT_FILE"
}

@test "script: DEFAULT_BUMP=none skips bump when commit has no explicit marker" {
    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "Routine work" >> README.md
    git add README.md
    git commit --quiet -m "Update internal docs"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        DEFAULT_BUMP="none" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    # No new tag should be created
    [ "$(git tag -l "v*.*.*" | grep -cv -- '-')" -eq 1 ]
    grep -q "skipped=true" "$GITHUB_OUTPUT_FILE"
}

@test "script: TAG_PREFIX creates tag with custom prefix" {
    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        TAG_PREFIX="ver-" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "ver-0.0.1"
    grep -q "new_version=ver-0.0.1" "$GITHUB_OUTPUT_FILE"
    grep -q "bump_type=patch" "$GITHUB_OUTPUT_FILE"
}

@test "script: TAG_PREFIX empty string creates unprefixed tag" {
    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        TAG_PREFIX="" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "0.0.1"
    grep -q "new_version=0.0.1" "$GITHUB_OUTPUT_FILE"
    grep -q "bump_type=patch" "$GITHUB_OUTPUT_FILE"
}

@test "script: BUILD_METADATA appends free-form metadata to tag" {
    git tag -a "v1.2.0" -m "Version 1.2.0"
    git push origin "v1.2.0" --quiet

    echo "Feature work" >> README.md
    git add README.md
    git commit --quiet -m "Add search feature #minor"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        BUILD_METADATA="build.42" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "v1.3.0+build.42"
    grep -q "new_version=v1.3.0+build.42" "$GITHUB_OUTPUT_FILE"
    grep -q "bump_type=minor" "$GITHUB_OUTPUT_FILE"
}

@test "script: BUILD_METADATA=sha resolves to sha.<7-char-sha>" {
    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "Fix bug" >> README.md
    git add README.md
    git commit --quiet -m "Fix null pointer bug"

    EXPECTED_SHA=$(git rev-parse --short=7 HEAD)

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        BUILD_METADATA="sha" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    git tag -l | grep -qx "v1.0.1+sha.${EXPECTED_SHA}"
    grep -q "new_version=v1.0.1+sha.${EXPECTED_SHA}" "$GITHUB_OUTPUT_FILE"
}

@test "script: BUILD_METADATA with invalid chars warns and creates clean tag" {
    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "Fix bug" >> README.md
    git add README.md
    git commit --quiet -m "Fix null pointer bug"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        BUILD_METADATA="bad value!" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    # Tag created without metadata due to invalid characters
    git tag -l | grep -qx "v1.0.1"
    grep -q "new_version=v1.0.1" "$GITHUB_OUTPUT_FILE"
    # Warning should appear in output
    [[ "$output" == *"Warning"* ]] || [[ "$output" == *"warning"* ]]
}

@test "script: BUILD_METADATA with trailing dot warns and creates clean tag" {
    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "Fix bug" >> README.md
    git add README.md
    git commit --quiet -m "Fix null pointer bug"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        BUILD_METADATA="build." \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    # Tag created without metadata — trailing dot is an empty identifier per SemVer §10
    git tag -l | grep -qx "v1.0.1"
    grep -q "new_version=v1.0.1" "$GITHUB_OUTPUT_FILE"
    [[ "$output" == *"Warning"* ]] || [[ "$output" == *"warning"* ]]
}

@test "script: BUILD_METADATA with consecutive dots warns and creates clean tag" {
    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "Fix bug" >> README.md
    git add README.md
    git commit --quiet -m "Fix null pointer bug"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        BUILD_METADATA="build..42" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    # Tag created without metadata — consecutive dots produce an empty identifier per SemVer §10
    git tag -l | grep -qx "v1.0.1"
    grep -q "new_version=v1.0.1" "$GITHUB_OUTPUT_FILE"
    [[ "$output" == *"Warning"* ]] || [[ "$output" == *"warning"* ]]
}

@test "script: BUILD_METADATA does not affect floating pointer tags" {
    git tag -a "v1.2.0" -m "Version 1.2.0"
    git push origin "v1.2.0" --quiet

    echo "Feature work" >> README.md
    git add README.md
    git commit --quiet -m "Add export feature #minor"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        BUILD_METADATA="build.99" \
        MOVE_MAJOR_TAG="true" \
        MOVE_MINOR_TAG="true" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    # Versioned tag has metadata
    git tag -l | grep -qx "v1.3.0+build.99"
    # Floating tags do NOT have metadata
    git tag -l | grep -qx "v1"
    git tag -l | grep -qx "v1.3"
    # Floating tags should not contain '+'
    run bash -c 'git tag -l | grep -q "v1+"'
    [ "$status" -ne 0 ]
    run bash -c 'git tag -l | grep -q "v1.3+"'
    [ "$status" -ne 0 ]
}

@test "script: MOVE_MAJOR_TAG and MOVE_MINOR_TAG are skipped for pre-release tags" {
    # Floating pointer tags must not move to pre-release commits — consumers who
    # pin to @v1 expect only stable releases.
    git tag -a "v1.2.0" -m "Version 1.2.0"
    git push origin "v1.2.0" --quiet
    # Establish a known stable state for v1 and v1.2
    git tag -a "v1" -m "Major pointer"
    git push origin "v1" --quiet
    git tag -a "v1.2" -m "Minor pointer"
    git push origin "v1.2" --quiet

    STABLE_SHA=$(git rev-parse HEAD)

    echo "Feature work" >> README.md
    git add README.md
    git commit --quiet -m "Add alpha feature"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        PRERELEASE_SUFFIX="alpha" \
        MOVE_MAJOR_TAG="true" \
        MOVE_MINOR_TAG="true" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    # Pre-release tag was created
    git tag -l | grep -qx "v1.2.1-alpha.1"

    # Floating tags still point to the stable commit — not the pre-release commit
    [ "$(git rev-parse "v1^{}")"   = "$STABLE_SHA" ]
    [ "$(git rev-parse "v1.2^{}")" = "$STABLE_SHA" ]

    # Skip messages should appear in output
    [[ "$output" == *"Skipping major tag"* ]]
    [[ "$output" == *"Skipping minor tag"* ]]
}

@test "script: RELEASE_MARKER sets should_release=true when marker found in commit" {
    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "Feature work" >> README.md
    git add README.md
    git commit --quiet -m "Add search feature #minor #release"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        RELEASE_MARKER="#release #publish #ship" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    grep -q "should_release=true" "$GITHUB_OUTPUT_FILE"
    grep -q "new_version=v1.1.0" "$GITHUB_OUTPUT_FILE"
}

@test "script: RELEASE_MARKER is case-insensitive for commit message marker casing" {
    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "Feature work" >> README.md
    git add README.md
    git commit --quiet -m "Add search feature #minor #RELEASE"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        RELEASE_MARKER="#release #publish #ship" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    grep -q "should_release=true" "$GITHUB_OUTPUT_FILE"
    grep -q "new_version=v1.1.0" "$GITHUB_OUTPUT_FILE"
}

@test "script: RELEASE_MARKER sets should_release=false when no marker in commit" {
    git tag -a "v1.0.0" -m "Version 1.0.0"
    git push origin "v1.0.0" --quiet

    echo "Feature work" >> README.md
    git add README.md
    git commit --quiet -m "Add search feature #minor"

    run env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
        RELEASE_MARKER="#release #publish #ship" \
        "$BATS_TEST_DIRNAME/run-bump-version.sh"
    echo "Script output: $output"
    [ "$status" -eq 0 ]

    grep -q "should_release=false" "$GITHUB_OUTPUT_FILE"
}
