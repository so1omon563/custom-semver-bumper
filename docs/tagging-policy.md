# Tagging and Release Policy

> **Note:** The [Custom Version Bumper action](../README.md) is designed to be
> consistent with this policy. It creates immutable SemVer-compliant Git tags on
> every merge to `main` and never deletes, moves, or overwrites a versioned tag.
> See [Action Alignment](#action-alignment) for specifics.

## Status

Accepted

## Context

We use Git tags and CI to:

- Uniquely identify every merge to `main`.
- Publish stable releases that consumers can safely pin to.
- Publish pre-release builds (alpha, beta, rc, etc.) for testing and early adoption.

Git and our tooling assume that once a tag is published, it is effectively immutable.
Pre-release and build metadata follow the Semantic Versioning 2.0.0 specification.

## Decision

### 1. All pushed tags are immutable

- Once a tag is pushed to the shared remote, we do not change what commit it points to.
- If a tagged commit is bad, we create a **new** tag on a new commit; we do *not*
  retag an existing name.

### 2. We use SemVer for all tags

All tags follow [Semantic Versioning 2.0.0][semver-spec]:

- `MAJOR.MINOR.PATCH`
- Optional pre-release label: `-PRERELEASE` (e.g., `-alpha.1`, `-beta.2`, `-rc.1`).
- Optional build metadata: `+BUILD` (e.g., `+sha.9c2af`, `+build.1234`).

### 3. Stable releases

- Stable releases use **no** pre-release label, for example: `1.4.2`.
- These tags are created on vetted commits from `main` and are the primary references
  for production use.
- Release-marked merge commits can also publish a GitHub Release for the new stable tag.

### 4. Pre-release tags

Unstable or not-yet-final versions use pre-release identifiers, for example:

- `1.5.0-alpha.1` (early development, unstable).
- `1.5.0-beta.2` (feature-complete, likely bugs).
- `1.5.0-rc.1` (release candidate).

Pre-release versions have lower precedence than the corresponding stable version
(for example, `1.5.0-rc.1 < 1.5.0`).

Pre-release tags are useful for testing, early adoption, and other non-stable
channels. Consumers that want only stable builds should depend on tags **without**
pre-release labels.

### 5. Tagging every merge to `main`

Each merge to `main` is tagged by CI with a SemVer that may include a pre-release
label and/or build metadata, for example:

- `1.6.0-alpha.3+build.1234`
- `1.6.0-beta.1+sha.9c2af`

These tags provide traceability for all builds while still remaining SemVer-compliant
for tools that parse versions.

### 6. Releases are not moved or reused

- We never move an existing tag (for example, `1.5.0`, `1.5.0-rc.1`) to point at a
  different commit once published.
- Fixes are done by incrementing the version and creating a new tag, for example:
  - From `1.5.0-rc.1` (bad) to `1.5.0-rc.2`.
  - From `1.5.0` (bad) to `1.5.1` or `2.0.0`, depending on impact.

### 7. Tag protection in hosting platform

We configure our Git hosting platform (GitHub) to enforce tag immutability using
**Repository Rulesets** (Settings → Rules → Rulesets).

The ruleset targets tags matching the pattern `refs/tags/<prefix>*.*.*`, which
covers all versioned SemVer tags — including pre-release and build metadata variants
such as `v1.2.3-alpha.1+sha.abc1234` — while intentionally **excluding** floating
pointer tags like `v1` and `v1.3`, which must remain movable (see Decision 6 and
[Floating pointer tags](#floating-pointer-tags) in the Action Alignment section).

Two rules are enforced:

- **Restrict deletions** — prevents `git push --delete <tag>` on any matching tag.
- **Block force pushes** — prevents moving a tag ref to a different commit.

> **`tag_prefix` note:** The pattern above uses the default prefix `v`, producing
> `refs/tags/v*.*.*`. If your repository uses a different `tag_prefix` (e.g.
> `release-`), adjust the pattern accordingly (e.g. `refs/tags/release-*.*.*`). For
> unprefixed tags (`tag_prefix: ""`), use `refs/tags/*.*.*`.

A reference ruleset export is provided at
[`protect-semver-tags-ruleset.json`](protect-semver-tags-ruleset.json). It uses the
default `v` prefix and grants bypass rights to repository admins and maintainers for
emergency tag removal. The `id` and `source` fields are intentionally omitted —
GitHub assigns these automatically on import.

## Rationale

- **Consistency with SemVer-aware tooling:** Package managers, deployment tools, and
  dependency systems rely on SemVer strings and their ordering rules; valid pre-release
  and build metadata keep those tools happy.
- **Reproducibility and trust:** Immutable tags mean checking out `1.5.0-rc.1` or
  `1.5.0` always yields the same code, which is required for reliable rollbacks and
  supply-chain guarantees.
- **Clear stability signals:** Pre-release identifiers communicate instability or
  "early access," while plain `MAJOR.MINOR.PATCH` communicates stable releases.
- **Simple operations:** Creating new tags for new builds is cheap and avoids the
  confusion, incidents, and security concerns that come from moving tags.

## Consequences

- Version numbers will advance frequently, including pre-release identifiers, but they
  will remain meaningful and machine-readable.
- Consumers who want stable releases can filter on tags without pre-release labels;
  those who want bleeding-edge can opt into pre-release tags.
- Any proposal to move or reuse a tag name conflicts with this policy and must be
  rejected or escalated as an explicit exception.

## Tags vs Releases

**A Git tag is not a GitHub Release.** This distinction is fundamental.

A **Git tag** is a named pointer to a commit in the Git object model. It is part of
the repository's version history. Creating, finding, and comparing tags is a
version-tracking concern. This policy governs tags.

A **GitHub Release** is a product feature built on top of a Git tag. It adds a web
UI entry, release notes, downloadable assets, and lifecycle semantics (draft,
pre-release, latest). It is a distribution and communication concern. Release
management is downstream of this policy and handled separately.

The reason this distinction matters here:

- **Every merge to `main` gets a tag.** That is a version-tracking operation.
- **Not every tag becomes a release.** Whether and when to create a GitHub Release
  from a tag is a separate workflow decision.
- Requests to skip tagging in order to avoid "noise" in GitHub Releases misunderstand
  the separation. Tags are immutable version records; releases are curated announcements.

Pre-release tags (e.g. `1.5.0-alpha.1`) follow the same immutability principle as
stable tags. They identify a specific non-stable build for testing or early adoption.
Whether a corresponding GitHub Release is created for an alpha tag is a release
management decision, not a tagging decision.

## Action Alignment

The Custom Version Bumper action implements the tagging half of this policy:

| Policy decision                           | Action behaviour                                                                                                                                                                                    |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Immutable versioned tags (Decisions 1, 6) | The action creates new tags; it never deletes, force-pushes, or rewrites a versioned tag (`X.Y.Z` or `X.Y.Z-label.N`)                                                                               |
| SemVer compliance (Decision 2)            | All produced tags are SemVer-compliant; see [SemVer Compliance](../README.md#semver-compliance)                                                                                                     |
| Build metadata (Decision 2)               | Supported via the `build_metadata` input; use `sha` shorthand to auto-append the commit SHA                                                                                                         |
| Stable releases (Decision 3)              | Default output is a plain `X.Y.Z` tag; `prerelease_suffix` is opt-in                                                                                                                                |
| Pre-release tags (Decision 4)             | Supported via the `prerelease_suffix` input; counter auto-increments per base version                                                                                                               |
| Tag every merge (Decision 5)              | Default behaviour; use `#skip` or `default_bump: none` to opt out per-commit or globally                                                                                                            |
| No retag/reuse (Decision 6)               | The action never overwrites an existing versioned tag; a conflict causes the action to fail visibly                                                                                                 |
| Tag protection (Decision 7)               | **Out of scope for this action** — configure tag protection rules in your repository settings using the reference ruleset at [`protect-semver-tags-ruleset.json`](protect-semver-tags-ruleset.json) |

### Floating pointer tags

The `move_major_tag` and `move_minor_tag` inputs create or move tags like `v1` and
`v1.3`. These are **not** versioned SemVer tags — they are convenience aliases for
GitHub Actions consumers who pin to `@v1`. Moving them is intentional and does not
conflict with the immutability principle, which applies only to versioned tags
(`X.Y.Z` and `X.Y.Z-label.N`). Floating pointer tags are never updated with build
metadata.

## References

- **GitHub Docs – Immutable releases**
  GitHub recommends immutable releases that lock the associated Git tag to a specific
  commit and prevent moving or deleting it, to preserve integrity and provenance.
  <https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases>

- **GitHub Docs – Using immutable releases and tags**
  Describes using immutable releases and tags for GitHub Actions and stresses that
  tags for published releases should not change once created.
  <https://docs.github.com/en/actions/how-tos/create-and-publish-actions/using-immutable-releases-and-tags-to-manage-your-actions-releases>

- **GitHub Changelog – Immutable releases GA**
  Announces immutable releases as a security feature that protects release tags from
  being moved or deleted after publication.
  <https://github.blog/changelog/2025-10-28-immutable-releases-are-now-generally-available/>

- **GitLab Docs – Immutable container tags**
  Defines immutable tags as tags that cannot be updated or deleted, to prevent
  accidental or malicious changes to important tagged artifacts.
  <https://docs.gitlab.com/user/packages/container_registry/immutable_container_tags/>

- **GitLab Epic – Tag immutability**
  Explains tag immutability as a way to ensure once an image is tagged (for example,
  `v1.0.0`), that tag cannot later be replaced with different content.
  <https://gitlab.com/groups/gitlab-org/-/epics/15139>

- **Stack Overflow – "Git retagging sane and insane advice"**
  Widely cited answer stating that tags are meant to be immutable and force-changing
  tags, especially release tags, is error-prone and a security concern.
  <https://stackoverflow.com/questions/50318271/git-retagging-sane-and-insane-advice>

- **Semantic Versioning 2.0.0 (official spec)**
  Defines `MAJOR.MINOR.PATCH`, pre-release identifiers (for example, `-alpha.1`,
  `-rc.1`), and build metadata, and how version precedence works.
  <https://semver.org>

- **Semantic Versioning best-practices guides**
  Explain how SemVer communicates compatibility and how pre-release labels and build
  metadata should be used in real projects.
  <https://talent500.com/blog/semantic-versioning-explained-guide/>
  <https://www.baeldung.com/cs/semantic-versioning>

- **Microsoft .NET Blog – Supporting SemVer 2.0.0**
  Shows a major ecosystem adopting SemVer 2.0.0, including pre-release and build
  metadata, as the standard for package versioning.
  <https://devblogs.microsoft.com/dotnet/supporting-semver-2-0-0/>

- **Go ecosystem discussion – SemVer releases and reproducibility**
  Emphasizes that reproducible builds require non-changing tags or hashes and
  encourages SemVer releases for libraries.
  <https://forum.golangbridge.org/t/please-start-doing-semver-releases-of-your-go-packages-libraries/1517>

[semver-spec]: https://semver.org
