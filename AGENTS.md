# Repository Guidelines

## Project Structure & Module Organization

This repository contains a composite GitHub Action for automatic SemVer tag creation.
The action contract lives in `action.yml`. Runtime behavior is implemented in
`scripts/bump-version.sh`. Tests live under `tests/`, including shell unit tests,
integration tests that create temporary Git repositories, and BATS suites. Supporting
documentation is in `README.md`, `CONTRIBUTING.md`, and `docs/`. GitHub workflows and
issue templates are stored in `.github/`.

## Build, Test, and Development Commands

- `make help`: Show all available developer commands.
- `make setup`: Mark test scripts executable.
- `make test-unit`: Run core version calculation tests.
- `make test-integration`: Run Git repository simulation tests.
- `make test-bats`: Run BATS helper tests.
- `make test-script`: Run BATS tests against `scripts/bump-version.sh`.
- `make check-contract`: Verify `action.yml` inputs are covered in script tests.
- `make shellcheck`: Run ShellCheck against shell scripts.
- `make test-all`: Run the full local test suite.
- `make coverage`: Generate `kcov` coverage for `bump-version.sh` on Linux.

## Coding Style & Naming Conventions

Use Bash consistently and keep logic explicit. Quote variables, prefer `[[ ... ]]`
for conditionals, and keep parsing behavior readable with short comments where the
rules are non-obvious. Environment-driven configuration uses uppercase names such
as `DEFAULT_BUMP`, `TAG_PREFIX`, and `MARKER_STYLE`. Branch names should use prefixes
such as `feat/`, `fix/`, `docs/`, `test/`, `ci/`, or `chore/`.

## Testing Guidelines

Behavior changes require tests. Add parser and bump-decision coverage in
`tests/test.sh`. Add real Git/tag behavior coverage in `tests/integration_test.sh`
or `tests/test_script.bats`. New action inputs must be exercised in
`tests/test_script.bats`, and `make check-contract` must pass. BATS tests require
`bats-core`; ShellCheck is expected for shell changes.

## Commit & Pull Request Guidelines

Use Conventional Commits:

```text
feat(scripts): add prerelease suffix validation
fix(action): handle missing tag prefix
docs: update usage examples
```

Open changes through pull requests against `main`. PRs should include a concise
summary, linked issues when relevant, notes about action input/output changes, and
the test commands run. Screenshots are only useful for documentation-rendering
changes.

## Security & Configuration Tips

Tests require Git identity configuration because they create commits:

```bash
git config user.name "Your Name"
git config user.email "you@example.com"
```

Do not put tokens, private repository names, or organization-specific secrets in
examples. Keep repository protection and tag rules in GitHub settings or rulesets,
not in runtime scripts.
