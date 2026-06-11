#!/bin/bash

# Test helper functions for Custom Version Bumper Action
# These functions provide the same logic as the extracted script for unit testing

# Function to test version bumping logic - mirrors the production script
# Args: current_version commit_msg [default_bump [marker_style [cc_type_map]]]
# Returns the new version string, or "skip" if the bump would be skipped.
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

    local LOWER_MSG LOWER_TITLE LOWER_BODY TITLE_HAS_BUMP_MARKER TITLE_HAS_SKIP_MARKER
    LOWER_MSG=$(echo "$merge_commit_msg" | tr '[:upper:]' '[:lower:]')
    LOWER_TITLE=$(echo "$merge_commit_msg" | head -1 | tr '[:upper:]' '[:lower:]')
    LOWER_BODY=$(echo "$merge_commit_msg" | tail -n +2 | tr '[:upper:]' '[:lower:]')

    # Determine whether the title carries an explicit marker.
    TITLE_HAS_BUMP_MARKER=false
    TITLE_HAS_SKIP_MARKER=false
    if [[ $LOWER_TITLE == *"#major"* ]] || \
       [[ $LOWER_TITLE == *"#minor"* ]] || \
       [[ $LOWER_TITLE == *"#patch"* ]]; then
        TITLE_HAS_BUMP_MARKER=true
    fi
    if [[ $LOWER_TITLE == *"#skip-version"* ]] || \
       [[ $LOWER_TITLE == *"#no-bump"* ]] || \
       [[ $LOWER_TITLE == *"#skip"* ]]; then
        TITLE_HAS_SKIP_MARKER=true
    fi

    # Skip detection: title marker takes priority over body marker.
    if $TITLE_HAS_SKIP_MARKER; then
        echo "skip"
        return 0
    elif ! $TITLE_HAS_BUMP_MARKER; then
        # No title bump marker — check the body for skip markers
        if [[ $LOWER_BODY == *"#skip-version"* ]] || \
           [[ $LOWER_BODY == *"#no-bump"* ]] || \
           [[ $LOWER_BODY == *"#skip"* ]]; then
            echo "skip"
            return 0
        fi
    fi

    # Determine bump type based on marker_style
    local BUMP_TYPE=""

    if [[ "$marker_style" == "conventional-commits" ]]; then
        local CC_TYPE=""
        local line
        local cc_breaking_re='^([a-zA-Z]+)(\([^)]*\))?!:'
        local cc_footer_re='^BREAKING([[:space:]]|-)CHANGE:'
        local cc_type_re='^([a-zA-Z]+)(\([^)]*\))?:'
        while IFS= read -r line; do
            # Check for type with ! suffix — always major
            if [[ "$line" =~ $cc_breaking_re ]]; then
                CC_TYPE=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
                BUMP_TYPE="major"
                break
            fi
            # Check for BREAKING CHANGE footer — always major
            if [[ "$line" =~ $cc_footer_re ]]; then
                BUMP_TYPE="major"
                break
            fi
            # Capture first regular CC type prefix
            if [[ -z "$CC_TYPE" && "$line" =~ $cc_type_re ]]; then
                CC_TYPE=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
            fi
        done <<< "$merge_commit_msg"

        # Look up CC_TYPE in cc_type_map
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

        # Fallback to default_bump
        if [[ -z "$BUMP_TYPE" ]]; then
            BUMP_TYPE="$default_bump"
        fi
    else
        # Hashtag mode (default): title marker takes priority over body marker.
        if $TITLE_HAS_BUMP_MARKER; then
            if [[ $LOWER_TITLE == *"#major"* ]]; then
                BUMP_TYPE="major"
            elif [[ $LOWER_TITLE == *"#minor"* ]]; then
                BUMP_TYPE="minor"
            else
                BUMP_TYPE="patch"
            fi
        elif [[ $LOWER_MSG == *"#major"* ]]; then
            BUMP_TYPE="major"
        elif [[ $LOWER_MSG == *"#minor"* ]]; then
            BUMP_TYPE="minor"
        elif [[ $LOWER_MSG == *"#patch"* ]]; then
            BUMP_TYPE="patch"
        else
            BUMP_TYPE="$default_bump"
        fi
    fi

    # Handle 'none' and 'prerelease' default_bump with no explicit marker
    if [[ "$BUMP_TYPE" == "none" ]]; then
        echo "skip"
        return 0
    fi
    # 'prerelease' acts as 'patch' for base-version calculation; the pre-release suffix
    # is applied separately by the production script (or calculate_new_version_prerelease).
    if [[ "$BUMP_TYPE" == "prerelease" ]]; then
        BUMP_TYPE="patch"
    fi

    # Bump version
    case $BUMP_TYPE in
        "major") echo "$((MAJOR + 1)).0.0" ;;
        "minor") echo "$MAJOR.$((MINOR + 1)).0" ;;
        *)       echo "$MAJOR.$MINOR.$((PATCH + 1))" ;;
    esac
}

# Function to calculate a pre-release version string.
# Args: current_version commit_msg [default_bump [suffix [existing_counter]]]
# existing_counter=0 means no pre-release exists yet for the computed base version.
calculate_new_version_prerelease() {
    local current_version="$1"
    local merge_commit_msg="$2"
    local default_bump="${3:-patch}"
    local suffix="${4:-alpha}"
    local existing_counter="${5:-0}"

    local base_result
    base_result=$(calculate_new_version "$current_version" "$merge_commit_msg" "$default_bump")

    if [[ "$base_result" == "skip" ]]; then
        echo "skip"
        return 0
    fi

    local counter
    if [[ "$existing_counter" -gt 0 ]]; then
        counter="$((existing_counter + 1))"
    else
        counter=1
    fi

    echo "${base_result}-${suffix}.${counter}"
}

# Function to simulate major tag extraction
extract_major_version() {
    local version="$1"
    echo "$version" | cut -d'.' -f1
}

# Function to simulate getting the latest tag (mimics the action's logic)
get_latest_tag() {
    local tag_prefix="${1-v}"
    local match_pattern="${tag_prefix}[0-9]*.[0-9]*.[0-9]*"

    local latest_tag
    latest_tag=$(git describe --tags --abbrev=0 --match "$match_pattern" 2>/dev/null || true)

    if [[ -n "$latest_tag" ]]; then
        echo "$latest_tag"
    else
        echo "${tag_prefix}0.0.0"
    fi
}

# Function to simulate the complete version bumping process
simulate_version_bump() {
    local merge_commit_msg="$1"
    local move_major_tag="${2:-false}"
    local move_minor_tag="${3:-false}"
    local marker_style="${4:-hashtag}"
    local cc_type_map="${5:-}"
    local tag_prefix="${6-v}"

    # Get the latest tag
    local latest_tag
    latest_tag=$(get_latest_tag "$tag_prefix")
    local current_version=${latest_tag#"${tag_prefix}"}

    # Calculate new version
    local new_version
    new_version=$(calculate_new_version "$current_version" "$merge_commit_msg" "patch" "$marker_style" "$cc_type_map")
    local new_tag="${tag_prefix}${new_version}"

    echo "Current version: $latest_tag"
    echo "New version: $new_tag"
    
    # Create new tag (local testing only - no push)
    if git tag -a "$new_tag" -m "Bump version to $new_tag" 2>/dev/null; then
        echo "Created tag: $new_tag"
    else
        echo "Failed to create tag: $new_tag (may already exist)"
        return 1
    fi
    
    # Handle major tag movement if requested
    if [[ "$move_major_tag" == "true" ]]; then
        local major_version
        major_version=$(echo "$new_version" | cut -d'.' -f1)
        local major_tag="${tag_prefix}${major_version}"
        
        echo "Moving major tag: $major_tag"
        
        # Delete existing major tag locally (ignore errors)
        git tag -d "$major_tag" 2>/dev/null || true
        
        # Create new major tag pointing to same commit as new version tag
        if git tag -a "$major_tag" -m "Move major tag to $new_tag" 2>/dev/null; then
            echo "Major tag updated: $major_tag -> $new_tag"
        else
            echo "Failed to update major tag: $major_tag"
            return 1
        fi
    fi

    # Handle minor tag movement if requested
    if [[ "$move_minor_tag" == "true" ]]; then
        local major_part minor_part
        major_part=$(echo "$new_version" | cut -d'.' -f1)
        minor_part=$(echo "$new_version" | cut -d'.' -f2)
        local minor_tag="${tag_prefix}${major_part}.${minor_part}"

        echo "Moving minor tag: $minor_tag"

        git tag -d "$minor_tag" 2>/dev/null || true

        if git tag -a "$minor_tag" -m "Move minor tag to $new_tag" 2>/dev/null; then
            echo "Minor tag updated: $minor_tag -> $new_tag"
        else
            echo "Failed to update minor tag: $minor_tag"
            return 1
        fi
    fi

    return 0
}

# Function to create test scenario with existing tags
setup_test_tags() {
    local tags=("$@")
    for tag in "${tags[@]}"; do
        git tag -a "$tag" -m "Test tag $tag" 2>/dev/null || true
    done
}

# Function to verify tag exists
verify_tag_exists() {
    local tag="$1"
    git tag -l | grep -q "^${tag}$"
}

# Function to verify two tags point to same commit
verify_tags_same_commit() {
    local tag1="$1"
    local tag2="$2"
    
    local commit1
    local commit2
    commit1=$(git rev-list -n 1 "$tag1" 2>/dev/null)
    commit2=$(git rev-list -n 1 "$tag2" 2>/dev/null)
    
    [[ "$commit1" == "$commit2" ]]
}

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

    # default_bump=prerelease with no explicit marker → counter-only
    if [[ "$default_bump" == "prerelease" ]]; then
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
