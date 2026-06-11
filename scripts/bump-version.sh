#!/bin/bash
set -e

# Custom Version Bumper Script
# Automatically bumps version based on the PR merge commit message

# Tag prefix (e.g. 'v' → v1.2.3, '' → 1.2.3, 'release-' → release-1.2.3)
TAG_PREFIX="${TAG_PREFIX-v}"

# Parse compound default_bump values (e.g. minor-prerelease → base=minor, prerelease=true)
_DEFAULT_BUMP_RAW="${DEFAULT_BUMP:-patch}"
_DEFAULT_PRERELEASE=false
_DEFAULT_BASE_BUMP="$_DEFAULT_BUMP_RAW"
case "$_DEFAULT_BUMP_RAW" in
  prerelease|patch-prerelease)
    _DEFAULT_PRERELEASE=true
    _DEFAULT_BASE_BUMP="patch"
    ;;
  minor-prerelease)
    _DEFAULT_PRERELEASE=true
    _DEFAULT_BASE_BUMP="minor"
    ;;
  major-prerelease)
    _DEFAULT_PRERELEASE=true
    _DEFAULT_BASE_BUMP="major"
    ;;
esac

# Get the merge commit message early (needed for skip detection)
MERGE_COMMIT_MSG=$(git log -1 --pretty=%B)
LOWER_MSG=$(echo "$MERGE_COMMIT_MSG" | tr '[:upper:]' '[:lower:]')

# Split message into title (first line) and body (remaining lines).
# A marker in the title takes priority over a conflicting marker in the body,
# so that documentation examples in the body don't cause false positives.
COMMIT_TITLE=$(echo "$MERGE_COMMIT_MSG" | head -1)
COMMIT_BODY=$(echo "$MERGE_COMMIT_MSG" | tail -n +2)
LOWER_TITLE=$(echo "$COMMIT_TITLE" | tr '[:upper:]' '[:lower:]')
LOWER_BODY=$(echo "$COMMIT_BODY" | tr '[:upper:]' '[:lower:]')

# --- Skip detection ---
# Check the commit title first. If the title contains an explicit bump marker
# (#major, #minor, #patch), skip detection is bypassed entirely — a body that
# happens to mention "#skip" in documentation text must not suppress the bump.
# If the title itself has a skip marker, honour it immediately.
# Only when the title has no marker at all do we fall through to the body.
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

if $TITLE_HAS_SKIP_MARKER; then
  echo "Skip marker detected in commit title. No version bump will be performed."
  if [[ -n "$GITHUB_OUTPUT" ]]; then
    {
      echo "skipped=true"
      echo "bump_type=skip"
      echo "new_version="
      echo "previous_version="
      echo "should_release=false"
    } >> "$GITHUB_OUTPUT"
  fi
  exit 0
elif ! $TITLE_HAS_BUMP_MARKER; then
  # Title has no explicit marker — check the body for skip markers
  if [[ $LOWER_BODY == *"#skip-version"* ]] || \
     [[ $LOWER_BODY == *"#no-bump"* ]] || \
     [[ $LOWER_BODY == *"#skip"* ]]; then
    echo "Skip marker detected in commit message body. No version bump will be performed."
    if [[ -n "$GITHUB_OUTPUT" ]]; then
      {
        echo "skipped=true"
        echo "bump_type=skip"
        echo "new_version="
        echo "previous_version="
        echo "should_release=false"
      } >> "$GITHUB_OUTPUT"
    fi
    exit 0
  fi
fi

# --- Stable-release escape hatch (for default_bump=prerelease workflows) ---
# #stable or #release in the commit message forces a plain stable tag even when
# default_bump is set to 'prerelease'. Detected here so it can clear PRERELEASE_SUFFIX.
FORCE_STABLE=false
if [[ $LOWER_MSG == *"#stable"* || $LOWER_MSG == *"#release"* ]]; then
  FORCE_STABLE=true
fi

# Get the highest stable version tag, excluding pre-release tags.
# When TAG_PREFIX contains '-' the grep-v trick would incorrectly drop every
# tag; instead, strip the prefix first and check only the version-number part.
_stable_tags() {
  git tag -l "${TAG_PREFIX}*.*.*" | while IFS= read -r _t; do
    _ver="${_t#"${TAG_PREFIX}"}"
    _ver_base="${_ver%%+*}"  # strip build metadata before the stability check
    # Require a pure numeric semver version part (no pre-release suffix)
    [[ "$_ver_base" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo "$_t"
  done
}
HIGHEST_TAG=$(_stable_tags | sort -V | tail -1 || true)
HIGHEST_TAG="${HIGHEST_TAG:-${TAG_PREFIX}0.0.0}"

# Get the latest reachable stable tag, excluding pre-release tags.
# --exclude requires git >= 2.13; fall back gracefully if unsupported.
# Build metadata tags (e.g. v1.2.3+sha.abc) are treated as stable — metadata
# is stripped when parsing the version, so they are valid baseline candidates.
LATEST_TAG=$(git describe --tags --abbrev=0 --match "${TAG_PREFIX}*.*.*" \
  --exclude "*-*" 2>/dev/null || echo "")
if [[ -z "$LATEST_TAG" || "$LATEST_TAG" == *"-"* ]]; then
  LATEST_TAG=$(_stable_tags | sort -V | tail -1 || true)
  LATEST_TAG="${LATEST_TAG:-${TAG_PREFIX}0.0.0}"
fi

# Use the highest version tag if it exists and is higher than latest reachable
BASE_TAG="$LATEST_TAG"
if [[ -n "$HIGHEST_TAG" && "$HIGHEST_TAG" != "$LATEST_TAG" ]]; then
  LATEST_VER=${LATEST_TAG#"${TAG_PREFIX}"}
  LATEST_VER="${LATEST_VER%%+*}"   # strip build metadata before version comparison
  HIGHEST_VER=${HIGHEST_TAG#"${TAG_PREFIX}"}
  HIGHEST_VER="${HIGHEST_VER%%+*}" # strip build metadata before version comparison
  HIGHER_VER=$(printf '%s\n%s\n' "$LATEST_VER" "$HIGHEST_VER" | sort -V | tail -1)
  if [[ "$HIGHER_VER" == "$HIGHEST_VER" ]]; then
    echo "Using highest version tag $HIGHEST_TAG instead of latest reachable $LATEST_TAG"
    BASE_TAG="$HIGHEST_TAG"
  fi
fi

PREVIOUS_TAG="$BASE_TAG"
CURRENT_VERSION=${BASE_TAG#"${TAG_PREFIX}"}
CURRENT_VERSION="${CURRENT_VERSION%%+*}"  # strip build metadata before version parsing
IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"

# Robust version parsing with defaults for missing parts
MAJOR=${VERSION_PARTS[0]:-0}
MINOR=${VERSION_PARTS[1]:-0}
PATCH=${VERSION_PARTS[2]:-0}

# Validate that version parts are numeric, otherwise default to 0
if ! [[ "$MAJOR" =~ ^[0-9]+$ ]]; then MAJOR=0; fi
if ! [[ "$MINOR" =~ ^[0-9]+$ ]]; then MINOR=0; fi
if ! [[ "$PATCH" =~ ^[0-9]+$ ]]; then PATCH=0; fi

# --- Determine bump type from commit message ---
COMMIT_HAS_EXPLICIT_MARKER=false

if [[ "${MARKER_STYLE:-hashtag}" == "conventional-commits" ]]; then
  # Conventional Commits mode
  # Precedence: BREAKING CHANGE / type! > cc_type_map lookup > DEFAULT_BUMP
  BUMP_TYPE=""
  CC_TYPE=""
  CC_SCOPE_PRERELEASE=""

  # Regex patterns stored in variables for bash 3.2 compatibility
  CC_BREAKING_RE='^([a-zA-Z]+)(\([^)]*\))?!:'
  CC_FOOTER_RE='^BREAKING([[:space:]]|-)CHANGE:'
  CC_TYPE_RE='^([a-zA-Z]+)(\([^)]*\))?:'

  # Scan every line of the commit message
  while IFS= read -r line; do
    scope_raw=""
    scope_inner=""
    # Check for type with ! suffix (breaking change shorthand) — always major
    if [[ "$line" =~ $CC_BREAKING_RE ]]; then
      CC_TYPE=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
      BUMP_TYPE="major"
      echo "Conventional commits: '${CC_TYPE}!' breaking change detected → major bump"
      COMMIT_HAS_EXPLICIT_MARKER=true
      # Also capture pre-release scope hint from breaking-change lines (e.g. feat(pre:alpha)!:)
      if [[ -z "$CC_SCOPE_PRERELEASE" ]]; then
        scope_raw="${BASH_REMATCH[2]}"
        scope_inner=$(echo "${scope_raw#(}" | tr '[:upper:]' '[:lower:]')
        scope_inner="${scope_inner%)}"
        if [[ "$scope_inner" =~ ^pre:([a-zA-Z][a-zA-Z0-9]*)$ ]]; then
          CC_SCOPE_PRERELEASE="${BASH_REMATCH[1]}"
        fi
      fi
      break
    fi
    # Check for BREAKING CHANGE footer — always major
    if [[ "$line" =~ $CC_FOOTER_RE ]]; then
      BUMP_TYPE="major"
      echo "Conventional commits: 'BREAKING CHANGE:' footer detected → major bump"
      COMMIT_HAS_EXPLICIT_MARKER=true
      break
    fi
    # Capture first regular CC type prefix found (e.g. feat:, fix:, chore:)
    if [[ -z "$CC_TYPE" && "$line" =~ $CC_TYPE_RE ]]; then
      CC_TYPE=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
      # Check for pre-release scope hint: feat(pre:alpha): or fix(pre:rc):
      # scope_raw/scope_inner are script-level temp vars (can't use 'local' outside a function).
      if [[ -z "$CC_SCOPE_PRERELEASE" ]]; then
        scope_raw="${BASH_REMATCH[2]}"
        # Lowercase scope_inner so feat(Pre:ALPHA): normalises to pre:alpha (consistent with hashtag/footer)
        scope_inner=$(echo "${scope_raw#(}" | tr '[:upper:]' '[:lower:]')
        scope_inner="${scope_inner%)}"
        if [[ "$scope_inner" =~ ^pre:([a-zA-Z][a-zA-Z0-9]*)$ ]]; then
          CC_SCOPE_PRERELEASE="${BASH_REMATCH[1]}"
        fi
      fi
    fi
  done <<< "$MERGE_COMMIT_MSG"

  # Look up CC_TYPE in CC_TYPE_MAP when no breaking change was found
  if [[ -z "$BUMP_TYPE" && -n "$CC_TYPE" && -n "$CC_TYPE_MAP" ]]; then
    while IFS='=' read -r map_key map_val; do
      map_key=$(echo "$map_key" | tr -d ' \t\r')
      map_val=$(echo "$map_val" | tr -d ' \t\r')
      if [[ -n "$map_key" && "$map_key" == "$CC_TYPE" ]]; then
        BUMP_TYPE="$map_val"
        echo "Conventional commits: '$CC_TYPE' → $BUMP_TYPE bump (from cc_type_map)"
        COMMIT_HAS_EXPLICIT_MARKER=true
        break
      fi
    done <<< "$CC_TYPE_MAP"
  fi

  # Fall through to DEFAULT_BUMP when nothing matched
  if [[ -z "$BUMP_TYPE" ]]; then
    if $_DEFAULT_PRERELEASE; then
      BUMP_TYPE="$_DEFAULT_BASE_BUMP"
    else
      BUMP_TYPE="${DEFAULT_BUMP:-patch}"
    fi
    if [[ -n "$CC_TYPE" ]]; then
      echo "Conventional commits: '$CC_TYPE' not in cc_type_map → fallback to default_bump ($BUMP_TYPE)"
    else
      echo "Conventional commits: no CC type prefix found → fallback to default_bump ($BUMP_TYPE)"
    fi
  fi
else
  # Hashtag mode (default)
  # Check the commit title first — a title marker overrides any body marker.
  # Fall through to the full-message scan only when the title has no bump marker.
  CC_SCOPE_PRERELEASE=""
  if $TITLE_HAS_BUMP_MARKER; then
    if [[ $LOWER_TITLE == *"#major"* ]]; then
      BUMP_TYPE="major"
    elif [[ $LOWER_TITLE == *"#minor"* ]]; then
      BUMP_TYPE="minor"
    else
      BUMP_TYPE="patch"
    fi
    COMMIT_HAS_EXPLICIT_MARKER=true
    echo "Hashtag marker found in commit title: $BUMP_TYPE bump"
  elif [[ $LOWER_MSG == *"#major"* ]]; then
    BUMP_TYPE="major"
    COMMIT_HAS_EXPLICIT_MARKER=true
  elif [[ $LOWER_MSG == *"#minor"* ]]; then
    BUMP_TYPE="minor"
    COMMIT_HAS_EXPLICIT_MARKER=true
  elif [[ $LOWER_MSG == *"#patch"* ]]; then
    BUMP_TYPE="patch"
    COMMIT_HAS_EXPLICIT_MARKER=true
  else
    # default_bump=prerelease (or compound variant) means "use the configured base bump
    # level when no explicit marker is present, but always produce a pre-release tag" — the
    # pre-release suffix application happens after this block.
    if $_DEFAULT_PRERELEASE; then
      BUMP_TYPE="$_DEFAULT_BASE_BUMP"
    else
      BUMP_TYPE="${DEFAULT_BUMP:-patch}"
    fi
  fi
fi

# --- Commit-message pre-release suffix detection ---
# Detection runs in execution order (A → B → C); each step overwrites the previous,
# so C wins (highest priority) and A is the lowest-priority baseline:
#   A. #prerelease:<suffix> / #pre:<suffix> hashtag marker  — works in both modes
#      bare #prerelease / #pre (no suffix) → counter-only mode
#   B. pre:<suffix> CC scope hint                           — conventional-commits mode only
#   C. Pre-release: footer                                  — works in both modes (highest priority)
COMMIT_MSG_PRERELEASE=""
COUNTER_ONLY_FROM_MSG=false

# Step A (lowest priority baseline): hashtag marker — matched on lowercase message
PRERELEASE_HASHTAG_RE='#(prerelease|pre):([a-zA-Z][a-zA-Z0-9]*)'
PRERELEASE_BARE_RE='#(prerelease|pre)([^:a-zA-Z0-9]|$)'
if [[ "$LOWER_MSG" =~ $PRERELEASE_HASHTAG_RE ]]; then
  COMMIT_MSG_PRERELEASE="${BASH_REMATCH[2]}"
elif [[ "$LOWER_MSG" =~ $PRERELEASE_BARE_RE ]]; then
  # Bare #prerelease or #pre (no suffix) → counter-only mode
  COUNTER_ONLY_FROM_MSG=true
fi

# Step B (overrides A): CC scope hint set during conventional-commits parsing above
if [[ -n "$CC_SCOPE_PRERELEASE" ]]; then
  COMMIT_MSG_PRERELEASE="$CC_SCOPE_PRERELEASE"
fi

# Step C (highest priority; overrides A and B): Pre-release: footer, case-insensitive
# Intentional: only the first alphanumeric word after the colon is captured;
# any trailing content (e.g. "Pre-release: rc.2") is silently ignored and "rc" is used.
PRERELEASE_FOOTER_RE='^pre-?release:[[:space:]]*([a-zA-Z][a-zA-Z0-9]*)'
while IFS= read -r footer_line; do
  footer_line_lower=$(echo "$footer_line" | tr '[:upper:]' '[:lower:]')
  if [[ "$footer_line_lower" =~ $PRERELEASE_FOOTER_RE ]]; then
    COMMIT_MSG_PRERELEASE="${BASH_REMATCH[1]}"
    break
  fi
done <<< "$MERGE_COMMIT_MSG"

# Validate and apply the commit-message suffix (overrides workflow-level input when valid)
if [[ -n "$COMMIT_MSG_PRERELEASE" ]]; then
  # Normalize the commit-message suffix to lowercase for case-insensitive comparison
  COMMIT_MSG_PRERELEASE_LOWER=$(echo "$COMMIT_MSG_PRERELEASE" | tr '[:upper:]' '[:lower:]')
  ALLOWED_LIST="${ALLOWED_PRERELEASE_SUFFIXES:-alpha beta rc preview canary dev}"
  SUFFIX_VALID=false
  for allowed_val in $ALLOWED_LIST; do
    # Normalize each allowed value: strip whitespace and lowercase
    allowed_normalized=$(echo "$allowed_val" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    # Skip empty entries that may result from extra spaces
    if [[ -z "$allowed_normalized" ]]; then
      continue
    fi
    if [[ "$allowed_normalized" == "$COMMIT_MSG_PRERELEASE_LOWER" ]]; then
      SUFFIX_VALID=true
      # Use the normalized form for the applied suffix
      COMMIT_MSG_PRERELEASE="$allowed_normalized"
      break
    fi
  done

  if $SUFFIX_VALID; then
    PRERELEASE_SUFFIX="$COMMIT_MSG_PRERELEASE"
    echo "Commit message sets pre-release suffix: $PRERELEASE_SUFFIX"
  else
    echo "Warning: '$COMMIT_MSG_PRERELEASE' is not in the allowed pre-release suffix list" \
      "(${ALLOWED_LIST}). Falling back to workflow input: '${PRERELEASE_SUFFIX:-<none>}'."
  fi
fi

# Determine whether to operate in pre-release mode and whether it is counter-only.
# PRERELEASE_MODE=true  → produce a pre-release tag (named or counter-only)
# COUNTER_ONLY=true     → use format v1.2.3-N (no suffix name) instead of v1.2.3-SUFFIX.N
#
# Priority:
#   1. #stable / #release in commit message → always stable (FORCE_STABLE)
#   2. Bare #prerelease / #pre in commit message → counter-only pre-release
#   3. PRERELEASE_SUFFIX set (named) → always named pre-release
#   4. default_bump=prerelease AND no explicit commit marker AND no suffix
#        → counter-only pre-release (explicit markers still produce stable)
#   5. Otherwise → stable tag
PRERELEASE_MODE=false
COUNTER_ONLY=false

if $FORCE_STABLE; then
  # #stable or #release escape hatch — always produce a stable tag regardless of config.
  # Only log when pre-release was actually active; silent no-op on standard workflows.
  if [[ -n "$PRERELEASE_SUFFIX" || $_DEFAULT_PRERELEASE == true ]]; then
    echo "Stable-release marker detected. Pre-release suffix will be cleared for this run."
  fi
  PRERELEASE_SUFFIX=""
  PRERELEASE_MODE=false
elif $COUNTER_ONLY_FROM_MSG; then
  # Bare #prerelease / #pre in commit message → counter-only pre-release
  PRERELEASE_SUFFIX=""
  PRERELEASE_MODE=true
  COUNTER_ONLY=true
  echo "Bare #prerelease marker → counter-only pre-release (v<base>-N)"
elif [[ -n "$PRERELEASE_SUFFIX" ]]; then
  # Named pre-release (suffix set by workflow input or commit-message detection above)
  PRERELEASE_MODE=true
elif [[ "$_DEFAULT_PRERELEASE" == true && "$COMMIT_HAS_EXPLICIT_MARKER" == "false" ]]; then
  # default_bump=prerelease (or compound variant) with no suffix → counter-only pre-release
  # by default. Only applies when the commit message had no explicit bump marker; explicit
  # markers (#major, #minor, #patch) still produce stable releases.
  PRERELEASE_MODE=true
  COUNTER_ONLY=true
  echo "default_bump=$_DEFAULT_BUMP_RAW with no suffix → counter-only pre-release (v<base>-N)"
fi

# --- Branch-name fallback bump detection ---
# Used only when the commit message had no explicit marker.
# The prefix before the first '/' is looked up in BRANCH_PREFIX_MAP.
if [[ "$COMMIT_HAS_EXPLICIT_MARKER" == "false" && -n "$BRANCH_NAME" ]]; then
  branch_prefix="${BRANCH_NAME%%/*}"
  branch_prefix_lower=$(echo "$branch_prefix" | tr '[:upper:]' '[:lower:]')
  BRANCH_PREFIX_MAP="${BRANCH_PREFIX_MAP:-feat=minor
feature=minor
fix=patch
hotfix=patch
bugfix=patch
breaking=major
major=major
minor=minor
patch=patch}"
  while IFS='=' read -r bp_key bp_val; do
    bp_key=$(echo "$bp_key" | tr -d ' \t\r' | tr '[:upper:]' '[:lower:]')
    bp_val=$(echo "$bp_val" | tr -d ' \t\r' | tr '[:upper:]' '[:lower:]')
    if [[ -n "$bp_key" && "$bp_key" == "$branch_prefix_lower" ]]; then
      BUMP_TYPE="$bp_val"
      echo "Branch name '${BRANCH_NAME}' prefix '${branch_prefix}' → $BUMP_TYPE bump (from branch_prefix_map)"
      break
    fi
  done <<< "$BRANCH_PREFIX_MAP"
fi

# If DEFAULT_BUMP is "none" and no explicit marker was found, skip
if [[ "$BUMP_TYPE" == "none" ]]; then
  echo "No version bump marker found and default_bump is 'none'. Skipping version bump."
  if [[ -n "$GITHUB_OUTPUT" ]]; then
    {
      echo "skipped=true"
      echo "bump_type=skip"
      echo "new_version="
      echo "previous_version=$PREVIOUS_TAG"
      echo "should_release=false"
    } >> "$GITHUB_OUTPUT"
  fi
  exit 0
fi

# When operating in pre-release mode, the bump_type output is 'prerelease'.
# The underlying base bump level (major/minor/patch) is preserved in
# BASE_BUMP_TYPE for use in the version-number calculation below.
BASE_BUMP_TYPE="$BUMP_TYPE"
if $PRERELEASE_MODE; then
  BUMP_TYPE="prerelease"
  echo "Pre-release mode active (base bump: $BASE_BUMP_TYPE) → bump_type=prerelease"
fi

# --- Bump base version ---
case $BASE_BUMP_TYPE in
  "major")
    NEW_MAJOR="$((MAJOR + 1))"
    NEW_MINOR="0"
    NEW_PATCH="0"
    ;;
  "minor")
    NEW_MAJOR="$MAJOR"
    NEW_MINOR="$((MINOR + 1))"
    NEW_PATCH="0"
    ;;
  *)
    NEW_MAJOR="$MAJOR"
    NEW_MINOR="$MINOR"
    NEW_PATCH="$((PATCH + 1))"
    ;;
esac

NEW_BASE_VERSION="${NEW_MAJOR}.${NEW_MINOR}.${NEW_PATCH}"

# --- Pre-release suffix logic ---
if $PRERELEASE_MODE; then
  if $COUNTER_ONLY; then
    # Counter-only format: {prefix}1.2.3-N (no suffix name)
    # Find highest existing counter tag for this base version: {prefix}1.2.3-<digits>
    HIGHEST_PRERELEASE=$(git tag -l "${TAG_PREFIX}${NEW_BASE_VERSION}-*" \
      | grep -E "${NEW_BASE_VERSION//./\\.}-[0-9]+$" \
      | sort -V | tail -1)
    if [[ -n "$HIGHEST_PRERELEASE" ]]; then
      CURRENT_COUNTER="${HIGHEST_PRERELEASE##*-}"
      if [[ "$CURRENT_COUNTER" =~ ^[0-9]+$ ]]; then
        NEW_COUNTER="$((CURRENT_COUNTER + 1))"
      else
        NEW_COUNTER=1
      fi
    else
      NEW_COUNTER=1
    fi
    NEW_VERSION="${NEW_BASE_VERSION}-${NEW_COUNTER}"
  else
    # Named pre-release format: {prefix}1.2.3-suffix.N
    PRERELEASE_BASE="${TAG_PREFIX}${NEW_BASE_VERSION}-${PRERELEASE_SUFFIX}"
    HIGHEST_PRERELEASE=$(git tag -l "${PRERELEASE_BASE}.*" | sort -V | tail -1)
    if [[ -n "$HIGHEST_PRERELEASE" ]]; then
      # Extract the counter (last dot-separated segment) and increment
      CURRENT_COUNTER="${HIGHEST_PRERELEASE##*.}"
      if [[ "$CURRENT_COUNTER" =~ ^[0-9]+$ ]]; then
        NEW_COUNTER="$((CURRENT_COUNTER + 1))"
      else
        NEW_COUNTER=1
      fi
    else
      NEW_COUNTER=1
    fi
    NEW_VERSION="${NEW_BASE_VERSION}-${PRERELEASE_SUFFIX}.${NEW_COUNTER}"
  fi
else
  NEW_VERSION="$NEW_BASE_VERSION"

  # Check if stable tag already exists and handle conflicts
  if git rev-parse "${TAG_PREFIX}${NEW_VERSION}" >/dev/null 2>&1; then
    echo "Warning: Tag ${TAG_PREFIX}${NEW_VERSION} already exists." \
      "Finding next available version..."

    if [[ -n "$HIGHEST_TAG" ]]; then
      HIGHEST_VERSION=${HIGHEST_TAG#"${TAG_PREFIX}"}
      HIGHEST_VERSION="${HIGHEST_VERSION%%+*}"  # strip build metadata before version parsing
      IFS='.' read -ra HIGHEST_PARTS <<< "$HIGHEST_VERSION"
      HIGHEST_MAJOR=${HIGHEST_PARTS[0]:-0}
      HIGHEST_MINOR=${HIGHEST_PARTS[1]:-0}
      HIGHEST_PATCH=${HIGHEST_PARTS[2]:-0}

      case $BASE_BUMP_TYPE in
        "major") NEW_VERSION="$((HIGHEST_MAJOR + 1)).0.0" ;;
        "minor") NEW_VERSION="$HIGHEST_MAJOR.$((HIGHEST_MINOR + 1)).0" ;;
        *)       NEW_VERSION="$HIGHEST_MAJOR.$HIGHEST_MINOR.$((HIGHEST_PATCH + 1))" ;;
      esac
      echo "Using next available version: ${TAG_PREFIX}$NEW_VERSION" \
        "(based on highest existing: $HIGHEST_TAG)"
    else
      echo "Error: Could not determine next version. No existing tags found."
      exit 1
    fi
  fi
fi

# Create and push new tag
NEW_TAG="${TAG_PREFIX}${NEW_VERSION}"

# Append build metadata (+BUILD) if requested.
# The shorthand value 'sha' resolves to sha.<7-char-commit-sha>.
# Only characters valid in SemVer §10 identifiers ([0-9A-Za-z\-.]) are accepted;
# invalid input produces a warning and the tag is created without metadata.
# Build metadata is never appended to floating pointer tags (v1, v1.3).
_RESOLVED_METADATA=""
if [[ -n "${BUILD_METADATA:-}" ]]; then
  if [[ "$BUILD_METADATA" == "sha" ]]; then
    _RESOLVED_METADATA="sha.$(git rev-parse --short=7 HEAD)"
  else
    _RESOLVED_METADATA="$BUILD_METADATA"
  fi
  # Validate: SemVer §10 allows [0-9A-Za-z-] identifiers separated by '.'.
  # A hyphen is valid as a leading character (e.g. -build.42 is a valid identifier).
  # Identifiers MUST NOT be empty, so trailing dots and consecutive dots are invalid.
  # Checked with two guards to avoid complex regex that causes catastrophic backtracking.
  if [[ "$_RESOLVED_METADATA" =~ ^[0-9A-Za-z-][0-9A-Za-z.\-]*$ ]] && \
     [[ "$_RESOLVED_METADATA" != *..* ]] && \
     [[ "$_RESOLVED_METADATA" != *. ]]; then
    NEW_TAG="${NEW_TAG}+${_RESOLVED_METADATA}"
    echo "Build metadata appended: +${_RESOLVED_METADATA}"
  else
    echo "Warning: build_metadata value '${_RESOLVED_METADATA}' is not a valid" \
      "SemVer §10 identifier ([0-9A-Za-z-.], no empty identifiers). Metadata will be omitted."
    _RESOLVED_METADATA=""
  fi
fi

git config user.name "GitHub Actions"
git config user.email "actions@github.com"
git tag -a "$NEW_TAG" -m "Bump version to $NEW_TAG"
git push origin "$NEW_TAG"

# Move major tag if requested — skipped for pre-release tags to protect consumers
# who pin to e.g. @v1 and expect only stable releases.
if [[ "$MOVE_MAJOR_TAG" == "true" ]]; then
  if $PRERELEASE_MODE; then
    echo "Skipping major tag update: floating pointer tags are not moved for pre-release versions."
  else
    IFS='.' read -ra NEW_VERSION_PARTS <<< "$NEW_VERSION"
    MAJOR_TAG="${TAG_PREFIX}${NEW_VERSION_PARTS[0]}"

    git tag -d "$MAJOR_TAG" 2>/dev/null || true
    git push origin --delete "$MAJOR_TAG" 2>/dev/null || true
    git tag -a "$MAJOR_TAG" -m "Move major tag to $NEW_TAG"
    git push origin "$MAJOR_TAG"

    echo "Major tag updated: $MAJOR_TAG -> $NEW_TAG"
  fi
fi

# Move minor tag if requested — skipped for pre-release tags for the same reason.
if [[ "$MOVE_MINOR_TAG" == "true" ]]; then
  if $PRERELEASE_MODE; then
    echo "Skipping minor tag update: floating pointer tags are not moved for pre-release versions."
  else
    IFS='.' read -ra NEW_VERSION_PARTS <<< "$NEW_VERSION"
    MINOR_TAG="${TAG_PREFIX}${NEW_VERSION_PARTS[0]}.${NEW_VERSION_PARTS[1]}"

    git tag -d "$MINOR_TAG" 2>/dev/null || true
    git push origin --delete "$MINOR_TAG" 2>/dev/null || true
    git tag -a "$MINOR_TAG" -m "Move minor tag to $NEW_TAG"
    git push origin "$MINOR_TAG"

    echo "Minor tag updated: $MINOR_TAG -> $NEW_TAG"
  fi
fi

echo "New version tag created: $NEW_TAG"

# Detect release marker — check merge commit message for any configured token.
# RELEASE_MARKER is a space-separated list of tokens (default: "#release #publish #ship").
# Detection is case-insensitive. should_release is always false when skipped.
SHOULD_RELEASE="false"
if [[ -n "${RELEASE_MARKER:-}" ]]; then
  _commit_msg="$MERGE_COMMIT_MSG"
  for _token in ${RELEASE_MARKER}; do
    if echo "${_commit_msg}" | grep -qiF "${_token}"; then
      SHOULD_RELEASE="true"
      break
    fi
  done
fi

# Write outputs to GITHUB_OUTPUT (only set in a real GitHub Actions environment)
if [[ -n "$GITHUB_OUTPUT" ]]; then
  {
    echo "skipped=false"
    echo "bump_type=$BUMP_TYPE"
    echo "new_version=$NEW_TAG"
    echo "previous_version=$PREVIOUS_TAG"
    echo "should_release=$SHOULD_RELEASE"
  } >> "$GITHUB_OUTPUT"
fi
