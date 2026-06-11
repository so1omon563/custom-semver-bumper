# Custom Version Bumper

[![Test Custom Version Bumper Action](https://github.com/so1omon563/custom-semver-bumper/actions/workflows/test.yml/badge.svg)](https://github.com/so1omon563/custom-semver-bumper/actions/workflows/test.yml)
[![Coverage](https://img.shields.io/badge/coverage-73%25-yellow)](https://github.com/so1omon563/custom-semver-bumper/actions/workflows/test.yml)

GitHub Action that **automatically tags every merge commit** with a
[Semantic Versioning 2.0.0][semver-spec]-compliant Git tag. Every time a PR merges
to `main` (or another configured branch), a new versioned tag is created — whether
or not that commit represents a release. Control the bump level with a commit message
marker (`#major`, `#minor`, `#patch`), or let it default to a patch bump. Supports
[Conventional Commits][cc-spec], pre-release tags, and convenience floating reference
tags (`v1`, `v1.3`) for GitHub Actions consumers.

> **Default output uses the `v` prefix** (e.g. `v1.2.3`). This is a widespread
> GitHub/Git tagging convention — the `v` is **not** part of the SemVer spec. The
> version number itself (`1.2.3`) is SemVer-compliant. Set `tag_prefix: ""` to
> produce bare SemVer tags if your toolchain requires strict compliance.

## Table of Contents

- [Custom Version Bumper](#custom-version-bumper)
  - [Table of Contents](#table-of-contents)
  - [Project Scope](#project-scope)
    - [When to use this action](#when-to-use-this-action)
    - [When NOT to use this action](#when-not-to-use-this-action)
    - [In Scope](#in-scope)
    - [Out of Scope](#out-of-scope)
    - [The Key Distinction: Git Tags vs GitHub Releases](#the-key-distinction-git-tags-vs-github-releases)
  - [Quick Start](#quick-start)
  - [How It Works](#how-it-works)
  - [SemVer Compliance](#semver-compliance)
    - [Tag Formats](#tag-formats)
    - [Feature-Level Notes](#feature-level-notes)
    - [Tag Immutability](#tag-immutability)
  - [Requirements](#requirements)
  - [Configuration](#configuration)
    - [Inputs](#inputs)
    - [Outputs](#outputs)
  - [Usage Examples](#usage-examples)
    - [Commit Message Markers](#commit-message-markers)
    - [Skip Markers](#skip-markers)
  - [Advanced Features](#advanced-features)
    - [Moving Major and Minor Tags](#moving-major-and-minor-tags)
    - [Conventional Commits Mode](#conventional-commits-mode)
    - [Pre-release Tags](#pre-release-tags)
      - [Inline Suffix Override](#inline-suffix-override)
      - [Pre-release as Default](#pre-release-as-default)
      - [Full Alpha → RC → Stable Lifecycle Example](#full-alpha--rc--stable-lifecycle-example)
    - [Branch Name Fallback](#branch-name-fallback)
    - [Configuring the Default Bump](#configuring-the-default-bump)
      - [Compound Pre-Release Defaults](#compound-pre-release-defaults)
    - [Build Metadata](#build-metadata)
    - [Chaining with Release Creator](#chaining-with-release-creator)
  - [Troubleshooting](#troubleshooting)
  - [Development](#development)
    - [Contributing](#contributing)
    - [Testing](#testing)

## Project Scope

**This action is a Git tag bumper. It creates semver-compliant Git tags. That is all
it does.**

It reads a merge commit message (or branch name), determines the appropriate version
bump level, computes the next version number, and pushes a new Git tag. It has no
knowledge of — and no opinion about — what happens after the tag is created.

### When to use this action

Use this action when you want **every merge commit to a branch to be automatically
versioned**. The defining characteristic is automation: a tag is created on every
merge, without any manual intervention, whether or not the commit represents a
release.

**This action is a good fit if:**

- You want a permanent, reproducible reference for every commit that lands on a
  long-running branch — not just commits that are explicitly designated as releases.
- You follow a trunk-based or high-frequency merge workflow and want commit
  traceability built in by default.
- You want downstream consumers (other pipelines, deployment workflows, or Action
  pins) to always have a stable, versioned reference they can target.
- You are tagging merges to `main`, but the same pattern applies to any long-running
  branch in your workflow (`develop`, `release/*`, etc.).

### When NOT to use this action

**This action is not the right tool if:**

- You only want to create a tag at an explicit, intentional release point — not at
  every merge. If your workflow involves frequent "work in progress" merges to `main`
  and you do not want each one tagged, this action will create more tags than you want.
- You want to decide manually or on a case-by-case basis which commits deserve a tag.
  In that case, tag with `git tag` directly or trigger tagging from a separate,
  explicit release workflow.
- Your process distinguishes sharply between "merge to main" and "cut a release", and
  you have no use for a tag that is not also a release.

> **In short:** if the phrase "auto-tag every merge" describes what you want, this
> action is for you. If it describes something you are trying to avoid, this action
> will work against your process.

### In Scope

- Parsing commit messages for version bump signals (`#major`, `#minor`, `#patch`,
  `#skip`, `#stable`, `#release`, `#prerelease:<suffix>`)
- Parsing [Conventional Commit][cc-spec] type prefixes as bump signals
- Using branch name prefix as a fallback bump signal when no commit marker is present
- Creating a new semver-compliant Git tag (e.g. `v1.2.3`)
- Appending a pre-release label and auto-incrementing counter to a tag
  (e.g. `v1.2.3-alpha.1`) — this is still a **tagging concern**, not a release concern
- Moving floating major/minor pointer tags (e.g. `v1`, `v1.2`) for GitHub Actions
  consumers that pin to a major or minor ref
- Skipping tag creation on demand (`#skip`, `#no-bump`)
- Supporting configurable tag prefixes and marker detection strategies

### Out of Scope

The following will never be added to this action. They belong in separate tooling
(the [GitHub Releases API][gh-releases], the [GitHub CLI][gh-cli], or a dedicated
release action such as [release-creator][release-creator]):

- **GitHub Releases** — creating release entries, release notes, assets, or changelogs.
  If you need this, use [release-creator][release-creator] or another downstream
  workflow step after this action creates a tag.
- **Tag lifecycle management** — deleting, rotating, or cleaning up old tags of any
  kind. This conflicts with the [tag immutability principle](docs/tagging-policy.md):
  once a versioned tag is pushed, it is an immutable record. If a tagged commit needs
  a fix, the correct response is a new tag on a new commit.
- **Branch-based release gating** — restricting or triggering bumps based on which
  branch is being merged
- **Tag protection or repository rulesets** — enforcing which tags can be deleted or
  who can push tags is a repository administration concern
- **Deployment or publishing** — this action does not deploy anything or publish
  artifacts to any registry
- **Version manifest updates** — updating `package.json`, `pyproject.toml`, or any
  other version file in the repository
- **Changelog or release notes generation**
- **Notifications or third-party integrations**

### The Key Distinction: Git Tags vs GitHub Releases

A **Git tag** is a named pointer to a commit. It exists in the Git object model and is
part of the repository's version history. Creating a tag is a version tracking concern.

A **GitHub Release** is a GitHub product feature built on top of Git tags. It adds a
web UI entry, release notes, downloadable assets, and release lifecycle semantics
(draft, pre-release, latest). Managing releases is a distribution and communication
concern.

This action handles the first. If you need the second, consume this action's outputs
from a downstream step and create the GitHub Release there. See
[Chaining with Release Creator](#chaining-with-release-creator) for a complete example.

## Quick Start

Add this workflow to your repository (e.g. `.github/workflows/bump.yml`):

```yaml
name: Version Bump on PR Merge
on:
  pull_request:
    types: [closed]
    branches: [main]
jobs:
  bump-version:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
      - uses: so1omon563/custom-semver-bumper@v1
        # Pin to a specific version to avoid unexpected breaking changes
        with:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

When a PR merges to `main`, the action reads the merge commit message and creates
a new version tag automatically:

| Commit message contains | Result                                     |
| ----------------------- | ------------------------------------------ |
| `#minor`                | `v1.2.3` → `v1.3.0`                        |
| `#major`                | `v1.2.3` → `v2.0.0`                        |
| `#patch` or nothing     | `v1.2.3` → `v1.2.4` (patch is the default) |
| `#skip`                 | No tag created                             |

## How It Works

The action determines the version bump level by examining the merge commit message,
checking signals in priority order:

1. **Commit title marker** — `#major`, `#minor`, `#patch`, `#skip`, etc. in the **first line** of the commit message *(highest priority — overrides any conflicting marker in the body)*
2. **Commit body marker** — same markers in the body lines, when the title contains no marker
3. **Branch name prefix** — when `branch_name` is provided and the commit has no marker
4. **`default_bump`** — fallback level (`patch` by default) *(lowest priority)*

> **Title wins over body.** If the commit title contains `#minor` and the body
> contains `#skip` (for example, as a usage example in documentation), the title
> marker takes precedence and a minor bump is performed.
>
> `Pre-release:` footers and `BREAKING CHANGE:` footers follow their own documented
> priority and are unaffected by this rule.

A new annotated Git tag (`v1.2.3`) is created and pushed. If no tags exist yet in
the repository, the action starts at `v0.0.1`.

All tags are authored by `GitHub Actions <actions@github.com>`.

## SemVer Compliance

[Semantic Versioning 2.0.0][semver-spec] is the standard this action is built
around. All core version numbers produced (`X.Y.Z`, `X.Y.Z-label.N`) are
spec-compliant. Convenience features that step outside the spec — floating
reference tags, skip markers, workflow escape hatches — are provided to
accommodate real-world CI/CD needs, but they bend to SemVer rather than the
other way around. When a feature is out of spec, it is labelled clearly below.

### Tag Formats

| Tag format              | Example                 | SemVer valid? | Notes                                                                                                                                     |
| ----------------------- | ----------------------- | ------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `X.Y.Z`                 | `1.2.3`                 | ✅ Valid       | Core format per [spec §2][semver-spec]                                                                                                    |
| `X.Y.Z-suffix.N`        | `1.3.0-alpha.1`         | ✅ Valid       | Pre-release per [spec §9][semver-spec]                                                                                                    |
| `X.Y.Z-N`               | `1.2.4-1`               | ✅ Valid       | Numeric-only pre-release identifier, allowed per [spec §9][semver-spec]                                                                   |
| `X.Y.Z+BUILD`           | `1.3.0+build.42`        | ✅ Valid       | Build metadata per [spec §10][semver-spec]; ignored for precedence. Set via `build_metadata` input                                        |
| `X.Y.Z-suffix.N+BUILD`  | `1.3.0-alpha.1+sha.abc` | ✅ Valid       | Pre-release with build metadata — both slots populated                                                                                    |
| `vX.Y.Z` (default)      | `v1.2.3`                | ⚠️ Convention  | The `v` prefix is a widespread Git convention but is **not part** of the SemVer spec. The version number itself (`1.2.3`) is valid SemVer |
| `<prefix>X.Y.Z`         | `release-1.2.3`         | ⚠️ Convention  | Custom `tag_prefix` values are Git tagging conventions, not SemVer                                                                        |
| `vX` (floating major)   | `v1`                    | ❌ Not SemVer  | Created by `move_major_tag`; a convenience reference tag for GitHub Actions consumers (e.g. `@v1`), not a version number                  |
| `vX.Y` (floating minor) | `v1.3`                  | ❌ Not SemVer  | Created by `move_minor_tag`; same — a convenience reference tag, not a version number                                                     |

### Feature-Level Notes

**Fully aligned with SemVer:**

- Major, minor, and patch bump mechanics follow [spec §6–§8][semver-spec] reset
  rules (minor resets patch; major resets both)
- [Conventional Commits][cc-spec] mode maps `feat:` → minor, `fix:` → patch,
  `BREAKING CHANGE` → major — closely matching the SemVer criteria for each level
- Pre-release counter resets when the suffix changes (e.g. `alpha` → `beta`)
- Build metadata (`build_metadata` input) follows [spec §10][semver-spec] — ignored
  for version precedence and stable-tag detection; purely informational

**Valid SemVer format, but user carries semantic responsibility:**

- `default_bump: minor` / `default_bump: major` — bumps at a fixed level for every
  unmarked commit, regardless of whether the changes actually add functionality (minor)
  or break the API (major). The SemVer spec reserves these levels for specific kinds of
  changes ([§7][semver-spec], [§8][semver-spec]); this setting delegates that
  responsibility to the user. Use with care.
- `default_bump: prerelease`, `minor-prerelease`, `major-prerelease` — produces
  valid pre-release tags but applies the bump level as a blanket default. Ensure your
  workflow semantics match SemVer intent.

**Out of SemVer scope (workflow convenience features):**

- Floating major/minor tags (`move_major_tag`, `move_minor_tag`) — useful for GitHub
  Actions consumers but are **not** SemVer version numbers; they are reference pointers
- `tag_prefix` — a Git tagging convention; the `v` or other prefix is not part of the
  SemVer version string
- Skip markers (`#skip`, `#no-bump`) — workflow control with no SemVer equivalent;
  the spec expects every meaningful change to be versioned
- `#stable` / `#release` escape hatches — workflow control for label promotion

### Tag Immutability

**Versioned tags created by this action are immutable.** Once pushed, they are never
deleted, force-pushed, or moved to a different commit.

This is a foundational design principle, not a limitation:

- **Reproducibility** — checking out `v1.5.0-rc.1` or `v1.5.0` always yields exactly
  the same code. This is required for reliable rollbacks and supply-chain provenance.
- **Tooling compatibility** — SemVer-aware package managers, dependency systems, and
  deployment tools rely on tags being stable references.
- **Simple, auditable operations** — moving or reusing tag names creates confusion,
  operational incidents, and security concerns. Creating a new tag is always cheap.

If a tagged commit needs to be fixed, the correct action is to create a **new tag on a
new commit** with an incremented version (e.g. `v1.5.0-rc.1` → `v1.5.0-rc.2`).

**Floating pointer tags are the sole exception.** Tags like `v1` and `v1.3` — created
by `move_major_tag` and `move_minor_tag` — are intentionally moved because they are
**not** versioned SemVer tags. They are convenience aliases for GitHub Actions consumers
who pin to `@v1`. See [Moving Major and Minor Tags](#moving-major-and-minor-tags).

**Enforcing immutability at the platform level** is done via GitHub Repository Rulesets,
not this action. A reference ruleset is provided at
[`docs/protect-semver-tags-ruleset.json`](docs/protect-semver-tags-ruleset.json). It
targets tags matching `refs/tags/v*.*.*` — covering versioned and pre-release tags while
leaving floating pointer tags (`v1`, `v1.3`) unprotected so the action can continue to
move them. The pattern uses the default `tag_prefix` of `v`; if you use a different
prefix (e.g. `release-`), adjust the pattern to match (e.g. `refs/tags/release-*.*.*`).
The `id` and `source` fields are omitted from the JSON — GitHub assigns these on import.

> See [`docs/tagging-policy.md`](docs/tagging-policy.md) for the full tagging and
> release policy that this action is designed to uphold.

[semver-spec]: https://semver.org/

## Requirements

- **`fetch-depth: 0`** on the checkout step — required to access tag history
- **`contents: write`** permission — required to push new tags
- **Runner**: `ubuntu-latest` (Linux environment)
- **Token**: `GITHUB_TOKEN` with appropriate repository access

## Configuration

### Inputs

| Input                         | Required | Default                            | Description                                                                                                                                                                                                                                                                 |
| ----------------------------- | -------- | ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GITHUB_TOKEN`                | ✅        | —                                  | GitHub token for authentication                                                                                                                                                                                                                                             |
| `move_major_tag`              | ❌        | `false`                            | Move the floating major tag (e.g. `v1`) to point to the latest **stable** version. **Skipped automatically when a pre-release tag is produced** — floating pointer tags must only ever reference stable commits.                                                            |
| `move_minor_tag`              | ❌        | `false`                            | Move the floating minor tag (e.g. `v1.3`) to point to the latest **stable** version. **Skipped automatically when a pre-release tag is produced** — same reason as `move_major_tag`.                                                                                        |
| `default_bump`                | ❌        | `patch`                            | Bump level when no marker is found. Values: `patch`, `minor`, `major`, `none`, `prerelease`, `minor-prerelease`, `major-prerelease`, `patch-prerelease`                                                                                                                     |
| `prerelease_suffix`           | ❌        | `""`                               | Append a [SemVer §9 label][semver-spec] identifier and counter (e.g. `alpha` → `v1.3.0-alpha.1`). Not limited to pre-release signaling — any identifier is valid (see [Pre-release Tags](#pre-release-tags))                                                                |
| `allowed_prerelease_suffixes` | ❌        | `alpha beta rc preview canary dev` | Suffixes a commit message may specify inline                                                                                                                                                                                                                                |
| `marker_style`                | ❌        | `hashtag`                          | Detection strategy: `hashtag` or `conventional-commits`                                                                                                                                                                                                                     |
| `cc_type_map`                 | ❌        | `feat=minor` / `fix=patch`         | Conventional Commit type → bump level, one `type=level` entry per line                                                                                                                                                                                                      |
| `branch_name`                 | ❌        | `""`                               | Branch name as a fallback signal (typically `${{ github.head_ref \|\| '' }}`)                                                                                                                                                                                               |
| `branch_prefix_map`           | ❌        | *(see below)*                      | Branch prefix → bump level, one `prefix=level` entry per line                                                                                                                                                                                                               |
| `tag_prefix`                  | ❌        | `v`                                | Prefix for all version tags (convention, not part of the SemVer spec). Use `""` for bare `1.2.3`, or e.g. `release-` for `release-1.2.3`                                                                                                                                    |
| `build_metadata`              | ❌        | `""`                               | SemVer §10 build metadata to append (e.g. `build.${{ github.run_number }}` → `v1.3.0+build.42`). Use `sha` as a shorthand to auto-resolve to `sha.<7-char-git-sha>`. Only affects the versioned tag — floating pointer tags (`v1`, `v1.3`) are never updated with metadata. |
| `release_marker`              | ❌        | `#release #publish #ship`          | Space-separated tokens that trigger the `should_release=true` output when found in the merge commit message. Detection is case-insensitive. Set to `""` to disable. See [Chaining with Release Creator](#chaining-with-release-creator). |

**Default `branch_prefix_map`:**

| Branch prefix             | Bump level |
| ------------------------- | ---------- |
| `feat`, `feature`         | `minor`    |
| `fix`, `hotfix`, `bugfix` | `patch`    |
| `breaking`                | `major`    |
| `major`                   | `major`    |
| `minor`                   | `minor`    |
| `patch`                   | `patch`    |

> **Tip:** Set a prefix to `none` to skip the version bump for that branch type
> (e.g. `docs=none` prevents a bump on `docs/*` branches).

### Outputs

| Output             | Example  | Description                                                      |
| ------------------ | -------- | ---------------------------------------------------------------- |
| `new_version`      | `v1.3.0` | The new tag created. Empty when skipped                          |
| `previous_version` | `v1.2.4` | The tag before the bump                                          |
| `bump_type`        | `minor`  | Bump applied: `major`, `minor`, `patch`, `prerelease`, or `skip` |
| `skipped`          | `false`  | `true` if the bump was skipped                                   |
| `should_release`   | `false`  | `true` when a `release_marker` token was found AND bump was not skipped. Use to conditionally trigger a release job. |

> **Note:** `bump_type` returns `prerelease` when a pre-release tag is created
> (i.e. when `prerelease_suffix` is set or `default_bump` is any prerelease variant).

**Example — consuming outputs in a downstream step:**

```yaml
- id: version
  uses: so1omon563/custom-semver-bumper@v1
  with:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

- name: Print version info
  if: steps.version.outputs.skipped == 'false'
  run: echo "Released ${{ steps.version.outputs.new_version }}"
```

## Usage Examples

### Commit Message Markers

Include a marker in the PR merge commit message to control the bump level:

```text
"Fix critical security issue #major"     → v1.2.3 → v2.0.0
"Add user authentication #minor"         → v1.2.3 → v1.3.0
"Update documentation #patch"            → v1.2.3 → v1.2.4
"Refactor database layer #MINOR"         → Case-insensitive
"Fix bug and add feature #minor #major"  → Major wins (highest marker applies)
"Regular bug fix"                        → Default bump (patch)
```

> **Note:** The `#` prefix is required. Words like `major` or `minor` without `#` are ignored.

### Skip Markers

> **Out of SemVer scope:** Skipping a version bump is a workflow control
> mechanism with no equivalent in the SemVer spec. Use sparingly — the spec
> expects every meaningful change to be versioned.

Add any of these markers to the commit message to skip the version bump entirely:

| Marker          | Example commit message        |
| --------------- | ----------------------------- |
| `#skip`         | `Deploy config update #skip`  |
| `#no-bump`      | `Hotfix deploy only #no-bump` |
| `#skip-version` | `Infra change #skip-version`  |

When a bump is skipped, `skipped=true` and `new_version` is empty.

## Advanced Features

### Moving Major and Minor Tags

> **SemVer note:** Floating tags like `v1` and `v1.3` are **not** valid SemVer
> version numbers (SemVer requires the full `X.Y.Z` format). They are convenience
> reference tags for GitHub Actions consumers who pin to `@v1`. See
> [SemVer Compliance](#semver-compliance) for details.

Enable floating tags that always point to the latest version in their line. This is
useful when consumers reference `uses: my-org/my-action@v1` and expect to get the
latest patch automatically.

```yaml
- uses: so1omon563/custom-semver-bumper@v1
  with:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    move_major_tag: true   # Keeps v1 pointing to the latest v1.x.x
    move_minor_tag: true   # Keeps v1.3 pointing to the latest v1.3.x
```

For example, bumping from `v1.2.3` to `v1.3.0` will also move `v1` and `v1.3` to
point to the same commit as `v1.3.0`.

> **Immutability note:** Versioned tags (`v1.2.3`, `v1.3.0-alpha.1`) are **never**
> moved or deleted — they are immutable records. Floating pointer tags (`v1`, `v1.3`)
> are the sole exception: moving them is intentional because they are not versioned
> SemVer tags. They are reference aliases, not version numbers.
>
> **Pre-release note:** Floating pointer tags are **never moved when the produced tag
> is a pre-release** (e.g. `v1.3.0-alpha.1`). Moving them to a pre-release commit
> would break consumers who pin to `@v1` and expect only stable releases. When
> `move_major_tag` or `move_minor_tag` is `true` and a pre-release is produced, the
> action logs a skip message and leaves the floating tags unchanged.

### Conventional Commits Mode

If your team uses [Conventional Commits][cc-spec], set `marker_style: conventional-commits`
to drive version bumps from commit type prefixes instead of hashtag markers.

| Commit pattern                            | Bump                            |
| ----------------------------------------- | ------------------------------- |
| `fix: …`                                  | patch                           |
| `feat: …`                                 | minor                           |
| `feat!: …` or `BREAKING CHANGE:` footer   | major                           |
| Any scoped variant (e.g. `feat(auth): …`) | same rules apply                |
| Type not in `cc_type_map`                 | falls through to `default_bump` |

```yaml
- uses: so1omon563/custom-semver-bumper@v1
  with:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    marker_style: conventional-commits
```

**Extending the type map:**

```yaml
- uses: so1omon563/custom-semver-bumper@v1
  with:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    marker_style: conventional-commits
    default_bump: none   # Types not in the map → skip the bump
    cc_type_map: |
      feat=minor
      fix=patch
      perf=patch
      refactor=patch
```

`BREAKING CHANGE` footers and the `!` suffix always map to `major` and cannot be
overridden via `cc_type_map`. The `#skip`, `#no-bump`, and `#skip-version` escape
hatches still work in this mode.

### Pre-release Tags

> **SemVer note:** All pre-release tag formats produced by this action
> (`X.Y.Z-suffix.N` and `X.Y.Z-N`) are valid [SemVer 2.0.0][semver-spec]
> pre-release versions per spec §9.
>
> **Naming note:** This action uses the term "pre-release" to match SemVer §9's
> own name for the label slot (`X.Y.Z-<label>`). However, the label content is
> **not** restricted to pre-release signaling. The identifier can convey any
> meaningful information — build channels, deployment rings, team variants, etc.:
>
> | Label | Example tag | Meaning |
> | --- | --- | --- |
> | `alpha`, `beta`, `rc` | `v1.3.0-alpha.1` | Classic pre-release stages |
> | `nightly` | `v1.3.0-nightly.42` | Nightly build channel |
> | `enterprise` | `v1.3.0-enterprise.1` | Edition variant |
> | `team-blue` | `v1.3.0-team-blue.3` | Parallel team build |
> | `canary` | `v1.3.0-canary.7` | Canary deployment ring |

Set `prerelease_suffix` to append a label identifier to the tag. The counter
auto-increments for each run that targets the same base version:

```yaml
- uses: so1omon563/custom-semver-bumper@v1
  with:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    prerelease_suffix: alpha
```

With `v1.2.0` as the current stable tag:

| Commit message           | Tag produced     | Notes                                         |
| ------------------------ | ---------------- | --------------------------------------------- |
| `Fix bug #minor`         | `v1.3.0-alpha.1` | `#minor` → base `v1.3.0`; first alpha counter |
| `Fix bug #minor` (again) | `v1.3.0-alpha.2` | Same base — counter increments                |
| `Fix bug #patch`         | `v1.2.1-alpha.1` | Different base — new counter                  |

Pre-release tags are excluded from the stable-version baseline. Typical suffix values
(conventional pre-release signaling, though any valid label is accepted):
`alpha`, `beta`, `rc`, `preview`, `canary`, `dev`.

#### Inline Suffix Override

Specify the suffix directly in the commit message (must be in `allowed_prerelease_suffixes`).
Starting from `v1.2.3` as the current stable tag:

```text
"Add login feature #minor #prerelease:beta"  → v1.3.0-beta.1
"Release candidate build #prerelease:rc"     → v1.2.4-rc.1  (default patch base)
"Hotfix #pre:alpha"                          → v1.2.4-alpha.1 (#pre: is an alias)
```

Or use a `Pre-release:` footer in the commit body:

```text
feat: add new dashboard

Pre-release: beta
```

Detection priority (highest → lowest): `Pre-release:` footer → CC scope hint (`pre:<suffix>`)
→ `#prerelease:<suffix>` hashtag.

#### Pre-release as Default

Set `default_bump: prerelease` to produce a pre-release tag on every commit by default.
Use `#stable` or `#release` in a commit message to force a stable tag when ready.
(`#stable` and `#release` are out-of-SemVer-scope escape hatches — they exist to
accommodate CI/CD workflows, not because SemVer defines a promotion concept.)

In your workflow's `with:` block:

```yaml
# Counter-only pre-releases (no suffix configured)
default_bump: prerelease   # → v1.2.4-1, v1.2.4-2, …

# Named pre-releases (with suffix)
default_bump: prerelease
prerelease_suffix: alpha   # → v1.2.4-alpha.1, v1.2.4-alpha.2, …
```

```text
# Promote to stable at any time
feat: promote to stable #minor #stable  → v1.3.0
```

#### Full Alpha → RC → Stable Lifecycle Example

> **How the base version is anchored:** The action always calculates the next
> version from the latest **stable** tag (pre-release tags are excluded). To
> keep all commits in a series targeting the same base (e.g. `v1.3.0`), every
> commit must either carry an explicit bump marker or use a
> `default_bump: minor-prerelease` workflow config.

**Option A — Explicit `#minor` marker on every commit** (no workflow-level suffix):

Starting from stable `v1.2.0`:

| Commit message                                  | Tag produced     | Why                                                   |
| ----------------------------------------------- | ---------------- | ----------------------------------------------------- |
| `feat: new dashboard #minor #prerelease:alpha`  | `v1.3.0-alpha.1` | `#minor` → base `v1.3.0`; `#prerelease:alpha` → label |
| `fix: dashboard crash #minor #prerelease:alpha` | `v1.3.0-alpha.2` | `#minor` re-anchors base; counter increments          |
| `fix: final tweaks #minor #prerelease:beta`     | `v1.3.0-beta.1`  | suffix changes → counter resets                       |
| `fix: review feedback #minor #prerelease:rc`    | `v1.3.0-rc.1`    | suffix changes → counter resets                       |
| `chore: release v1.3.0 #minor`                  | `v1.3.0`         | `#minor`, no label → stable                           |

**Option B — Workflow-level `default_bump: minor-prerelease` (recommended):**

```yaml
default_bump: minor-prerelease
prerelease_suffix: alpha
```

Starting from stable `v1.2.0`:

| Commit message                        | Tag produced     | Why                                                |
| ------------------------------------- | ---------------- | -------------------------------------------------- |
| `feat: new dashboard`                 | `v1.3.0-alpha.1` | minor base from config; alpha from workflow suffix |
| `fix: dashboard crash`                | `v1.3.0-alpha.2` | minor base; counter increments                     |
| `fix: final tweaks #prerelease:beta`  | `v1.3.0-beta.1`  | inline suffix override; counter resets             |
| `fix: review feedback #prerelease:rc` | `v1.3.0-rc.1`    | inline suffix override; counter resets             |
| `chore: release v1.3.0 #stable`       | `v1.3.0`         | `#stable` escape hatch forces stable               |

### Branch Name Fallback

When commit messages alone are not enough, pass the branch name as a fallback signal.
The action uses the branch prefix only when no explicit commit marker is found.

```yaml
- uses: so1omon563/custom-semver-bumper@v1
  with:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    branch_name: ${{ github.head_ref || '' }}
```

| Branch                     | Detected prefix | Bump  |
| -------------------------- | --------------- | ----- |
| `feat/add-login`           | `feat`          | minor |
| `fix/null-pointer`         | `fix`           | patch |
| `hotfix/urgent-crash`      | `hotfix`        | patch |
| `breaking/v2-api`          | `breaking`      | major |

**Detection priority:** commit title marker > commit body marker > branch name prefix > `default_bump`

**Custom prefixes:**

```yaml
    branch_name: ${{ github.head_ref || '' }}
    branch_prefix_map: |
      feat=minor
      feature=minor
      fix=patch
      hotfix=patch
      chore=patch
      breaking=major
```

Prefixes not in the map fall through to `default_bump`.

### Configuring the Default Bump

Control what happens when no marker is found in the commit message:

```yaml
# Strict mode: only bump when an explicit marker is present
- uses: so1omon563/custom-semver-bumper@v1
  with:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    default_bump: none
```

Allowed values: `patch` (default), `minor`, `major`, `none`, `prerelease`,
`minor-prerelease`, `major-prerelease`, `patch-prerelease`.

#### Compound Pre-Release Defaults

Use a compound value to set both the base bump level **and** activate pre-release
mode as the default for unmarked commits:

| Value              | Base bump | Equivalent to          | Example tag                    |
| ------------------ | --------- | ---------------------- | ------------------------------ |
| `prerelease`       | patch     | `#patch #prerelease`   | `v1.2.4-1` or `v1.2.4-alpha.1` |
| `patch-prerelease` | patch     | alias for `prerelease` | `v1.2.4-1` or `v1.2.4-alpha.1` |
| `minor-prerelease` | minor     | `#minor #prerelease`   | `v1.3.0-1` or `v1.3.0-alpha.1` |
| `major-prerelease` | major     | `#major #prerelease`   | `v2.0.0-1` or `v2.0.0-alpha.1` |

```yaml
# Every unmarked commit produces a minor pre-release
- uses: so1omon563/custom-semver-bumper@v1
  with:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    default_bump: minor-prerelease
    prerelease_suffix: alpha   # → v1.3.0-alpha.1, v1.3.0-alpha.2, …
```

Explicit commit markers (`#major`, `#minor`, `#patch`) override the compound default's
**base bump level** and produce a stable release — **provided** no workflow-level
`prerelease_suffix` is configured. If `prerelease_suffix` is set in your workflow's
`with:` block, even explicit markers still produce labeled tags; use `#stable` or
`#release` to force a stable tag in that case. In `marker_style: conventional-commits`
mode, mapped Conventional Commit types (such as `feat:`/`fix:`) and breaking-change
indicators are also treated as explicit markers and likewise suppress the default
prerelease behavior.

> **⚠️ SemVer note:** The SemVer spec ties minor bumps to new backward-compatible
> functionality ([§7][semver-spec]) and major bumps to incompatible API changes
> ([§8][semver-spec]). Compound prerelease defaults apply a fixed bump level to
> every unmarked commit regardless of content — ensure your workflow semantics
> match SemVer intent. See [SemVer Compliance](#semver-compliance) for details.

### Chaining with Release Creator

> **Key constraint:** Tags pushed by `GITHUB_TOKEN` do not fire `push: tags:` events in
> other workflows (GitHub prevents this to avoid infinite loops). The release step must
> therefore run **in the same workflow run** as the bump.

Add `#release`, `#publish`, or `#ship` anywhere in the merge commit message. The marker
can stand alone or combine with a bump marker:

```text
#minor          → bump to next minor, no release
#minor #release → bump to next minor AND create a GitHub Release
#release        → bump with the default level AND create a GitHub Release
```

The `should_release` output is `true` when any configured marker is found and the bump
was not skipped. A downstream job consumes it:

> **Tip:** When chaining with `so1omon563/release-creator`, let the release creator
> own the floating pointer tags (`v1`, `v1.3`). Leave `move_major_tag` and
> `move_minor_tag` unset on the bumper so that floating tags only move when a release
> is actually published — not on every merge.

```yaml
name: Version Bump

on:
  pull_request:
    types: [closed]
    branches: [main]

jobs:
  bump-version:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    permissions:
      contents: write

    outputs:
      new-tag: ${{ steps.bump.outputs.new_version }}
      skipped: ${{ steps.bump.outputs.skipped }}
      should-release: ${{ steps.bump.outputs.should_release }}

    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - name: Bump version
        id: bump
        uses: so1omon563/custom-semver-bumper@v1
        with:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # release_marker: "#release #publish #ship"  # default — customise as needed
          # Floating pointer tags are owned by create-release below; do not set
          # move_major_tag or move_minor_tag here.

  create-release:
    name: Create GitHub Release
    needs: bump-version
    if: |
      needs.bump-version.outputs.should-release == 'true' &&
      needs.bump-version.outputs.skipped != 'true'
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
      - uses: so1omon563/release-creator@v1
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          tag: ${{ needs.bump-version.outputs.new-tag }}
          tag-prefix: v
          notes-format: grouped
          move-major-tag: 'true'
          move-minor-tag: 'true'
```

To customise the markers, set `release_marker` to a space-separated list of tokens:

```yaml
release_marker: "#release #deploy #publish"
```

Set `release_marker: ""` to disable marker detection entirely
(the `should_release` output will always be `false`).

### Build Metadata

Append [SemVer §10][semver-spec] build metadata to the version tag for traceability.
Build metadata is **ignored for version precedence** — it has no effect on which base
version is bumped to or how stable tags are detected.

```yaml
- uses: so1omon563/custom-semver-bumper@v1
  with:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    build_metadata: "build.${{ github.run_number }}"
    # Produces e.g. v1.3.0+build.42
```

Use the `sha` shorthand to automatically append the commit SHA:

```yaml
    build_metadata: sha
    # Produces e.g. v1.3.0+sha.a1b2c3d
```

| Input value                      | Tag produced            |
| -------------------------------- | ----------------------- |
| `build.${{ github.run_number }}` | `v1.3.0+build.42`       |
| `sha`                            | `v1.3.0+sha.a1b2c3d`    |
| `sha.${{ github.sha }}`          | `v1.3.0+sha.<full-sha>` |
| *(empty — default)*              | `v1.3.0`                |

> **Note:** Floating pointer tags (`v1`, `v1.3`) are **never** updated with build
> metadata. `move_major_tag` and `move_minor_tag` always point to the clean version.

## Troubleshooting

**Action not creating tags:**

- Verify `contents: write` permission is set
- Ensure `fetch-depth: 0` is set in the checkout step
- Confirm the PR was actually merged (not just closed)

**"No tags found" / starts at `v0.0.1`:**

- This is expected for new repositories — `v0.0.1` is the correct starting behavior

**Permission denied errors:**

```yaml
permissions:
  contents: write   # Required for tag creation
```

**Tags not appearing after merge:**

- Check the Actions run logs for detailed error messages
- Verify `GITHUB_TOKEN` has appropriate repository access

**Major tag conflicts:**

- The action handles existing major tags automatically when `move_major_tag: true`

## Development

### Contributing

1. Run the test suite: `cd tests/ && ./run_tests.sh`
2. Ensure scripts are executable: `chmod +x tests/*.sh`
3. Install optional test deps: `make install-deps` (macOS with Homebrew)

For detailed local workflow notes, see [CONTRIBUTING.md](CONTRIBUTING.md).

### Testing

| Suite       | Command                 | What it covers                               |
| ----------- | ----------------------- | -------------------------------------------- |
| All         | `make test-all`         | Runs all suites                              |
| Unit        | `make test-unit`        | Core version bumping logic                   |
| Integration | `make test-integration` | Full Git repository simulation               |
| BATS        | `make test-bats`        | Structured assertions (requires `bats-core`) |

[cc-spec]: https://www.conventionalcommits.org/
[gh-releases]: https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository
[gh-cli]: https://cli.github.com/manual/gh_release
[release-creator]: https://github.com/so1omon563/release-creator
