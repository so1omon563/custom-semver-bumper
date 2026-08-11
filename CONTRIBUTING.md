# Contributing to custom-semver-bumper

This repository is maintained as a personal GitHub Action project. The notes below
cover the local workflow for making and validating changes.

## Prerequisites

- Bash on macOS or Linux
- Git with `user.name` and `user.email` configured
- `make`
- `bats-core` for the full `make test-all` suite
- Optional: `shellcheck` for static analysis

## Setup

```bash
git clone https://github.com/so1omon563/custom-semver-bumper.git
cd custom-semver-bumper
make setup
```

The tests create temporary Git repositories, so Git user configuration is required:

```bash
git config user.name "Your Name"
git config user.email "you@example.com"
```

## Development Workflow

Create a branch from `main` for each change:

```bash
git checkout -b feat/your-short-description
```

Recommended branch prefixes:

| Prefix      | Use case                                    |
| ----------- | ------------------------------------------- |
| `feat/`     | New features or capabilities                |
| `fix/`      | Bug fixes                                   |
| `docs/`     | Documentation-only changes                  |
| `refactor/` | Code restructuring without behavior change  |
| `chore/`    | Maintenance, dependency updates             |
| `ci/`       | CI/CD pipeline changes                      |
| `test/`     | Test additions or updates                   |

## Commit Conventions

Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages:

```text
<type>(<scope>): <short description>

[optional body]

[optional footer(s)]
```

Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `perf`,
and `style`.

Common scopes: `action`, `scripts`, `tests`, `workflows`, and `docs`.

Examples:

```text
feat(scripts): add support for pre-release suffix
fix(action): handle missing git tag gracefully
docs: update README with new input parameters
```

## Testing

Run the full suite before committing:

```bash
make test-all
```

Useful targeted commands:

```bash
make test-unit          # Core version bumping logic
make test-integration   # Git repository simulation tests
make test-bats          # BATS helper-function tests
make test-script        # BATS script-level tests
make check-contract     # Verify action.yml inputs are covered
make shellcheck         # Static analysis for shell scripts
```

The non-BATS targets (`test-unit`, `test-integration`, and `check-contract`) do
not require `bats-core`; `test-all`, `test-bats`, and `test-script` do.

All behavior changes should include tests. The most important suite is
`tests/test_script.bats` because it invokes `scripts/bump-version.sh` directly in a
real isolated Git repository.

## Opening an Issue

Search [existing issues](https://github.com/so1omon563/custom-semver-bumper/issues)
first, then use the Bug Report or Feature Request form. A useful issue gives
someone else enough information to reproduce the behavior without guessing.

For a bug report, include:

1. The action version or commit SHA, plus the runner OS when relevant.
2. The exact command or workflow configuration that was used, with secrets removed.
3. The triggering event and input, such as the complete merge commit title/body,
   relevant action inputs, or the exact test command and test name.
4. The expected result and the actual result.
5. Observable evidence: full relevant output, error text, created tags, action
   outputs, or the test summary—not only a description of the symptom.
6. A minimal reproduction or step-by-step reproduction. If the issue is intermittent,
   say how often it reproduces.

For test or test-runner issues, report the exact command, failing test name(s),
pass/fail counts, and the complete failure summary. A pasted summary without the
command and failure evidence is not enough to diagnose the problem.

Do not include credentials, tokens, private repository data, or other secrets.
Report security vulnerabilities privately through the [security advisory form](https://github.com/so1omon563/custom-semver-bumper/security/advisories/new).

## What to Test

| Change type                               | Where to add tests                                               |
| ----------------------------------------- | ---------------------------------------------------------------- |
| New commit message marker or parsing rule | `tests/test.sh` + `tests/test_script.bats`                       |
| New or changed Git tag behavior           | `tests/integration_test.sh` + `tests/test_script.bats`           |
| New action input (`action.yml`)           | `tests/test_script.bats`; the contract check must pass           |
| Conventional Commits logic                | `tests/test.sh` + `tests/test_script.bats`                       |
| Pre-release suffix handling               | `tests/test.sh` + `tests/test_script.bats`                       |

## Feature Request Policy

This action is intentionally narrow: it computes and pushes SemVer-compatible Git
tags. Features should stay focused on version bump detection, tag creation, tag
formatting, or outputs that help downstream workflows.

Out of scope:

- Creating GitHub Releases
- Generating changelogs or release notes
- Deploying or publishing artifacts
- Updating package manifests or other version files
- Managing old tags beyond the documented floating major/minor refs

Use separate workflow steps or dedicated tools for those concerns.

## Security

Report security issues privately through GitHub:

https://github.com/so1omon563/custom-semver-bumper/security/advisories/new
