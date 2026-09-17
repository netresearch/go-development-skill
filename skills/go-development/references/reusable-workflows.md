# Reusable Workflows for Go Repos

Patterns for unifying CI/CD across multiple Go repositories by calling shared reusable workflows instead of duplicating action configuration per-repo.

## Why

Four repos that each re-declare their own `golangci-lint`, `govulncheck`, build, and release jobs drift apart. Pinning actions becomes 4× the work; a new linter rule must be added in 4 places; a security bump must be chased through 4 repos. Reusable workflows fix this by making the caller a thin YAML file that passes inputs and forwards permissions.

## Caller File (Minimal)

```yaml
# .github/workflows/ci.yml in a Go repo that delegates to a shared workflow
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  go-ci:
    uses: netresearch/shared-ci/.github/workflows/go-ci.yml@v3
    with:
      go-version: "1.23"
      lint-timeout: 5m
    permissions:
      contents: read
      checks: write       # required if the reusable workflow writes check annotations
      pull-requests: read # required if the reusable workflow reads PR metadata
    secrets:
      CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}
```

## Permission Propagation (The Recurring Gotcha)

Reusable workflows run under the **caller's** token, with permissions capped by the caller's `permissions:` block. Two failure modes:

1. **Caller too narrow**: Caller declares `permissions: contents: read`, but the reusable workflow needs `checks: write` to publish annotations → annotations silently don't appear.
2. **Caller uses `secrets: inherit`**: Exposes every org secret to every action in the reusable workflow, including transitively called third-party actions. High blast radius on supply chain compromise.

### Rules

- **Explicit per-permission grants at the caller job level**, matching what the reusable workflow documents as required. Never just `permissions: write-all`.
- **Explicit per-secret forwarding**: `secrets: { CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }} }`. Never `secrets: inherit`.
- **Reusable workflow documents its required permissions** in a comment block at the top of its file — treat this as contract.

### Required-permissions table (document in the reusable workflow)

```yaml
# Required caller permissions:
#   contents: read          # checkout
#   checks: write           # annotations from golangci-lint-action, gotestsum
#   pull-requests: read     # auto-merge eligibility check
#   security-events: write  # govulncheck SARIF upload (only if scan-mode is enabled)
#
# Required caller secrets (forward explicitly):
#   CODECOV_TOKEN           # optional; skip if code-coverage-upload: false
```

## Exposing Release Gates via Outputs

Release workflows need the SHA and tag emitted by the build job so downstream jobs (provenance, attestation, signing) can attach artifacts. Expose them as job outputs:

```yaml
# shared-ci go-release.yml (reusable)
on:
  workflow_call:
    outputs:
      image_digest:
        value: ${{ jobs.build.outputs.digest }}
      tag:
        value: ${{ jobs.build.outputs.tag }}

jobs:
  build:
    outputs:
      digest: ${{ steps.buildx.outputs.digest }}
      tag:    ${{ steps.meta.outputs.tags }}
    # ...
```

Caller consumes outputs:

```yaml
jobs:
  release:
    uses: netresearch/shared-ci/.github/workflows/go-release.yml@v3
    # ...

  provenance:
    needs: release
    uses: slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@v2.0.0
    with:
      image: "ghcr.io/${{ github.repository }}"
      digest: ${{ needs.release.outputs.image_digest }}
```

Without exposed outputs, release gates degrade to "find the SHA by re-querying the registry" — racy, slow, and often wrong.

## Pinning Reusable Workflows

Always reference reusable workflows by a released tag (or SHA), never by `@main`:

```yaml
uses: netresearch/shared-ci/.github/workflows/go-ci.yml@v3      # preferred
uses: netresearch/shared-ci/.github/workflows/go-ci.yml@<40-char-SHA>  # most strict
uses: netresearch/shared-ci/.github/workflows/go-ci.yml@main    # AVOID — moving target
```

`@main` means your CI behavior can change without a PR in the caller repo. A surprise lint failure from a reusable-workflow bump has no changelog in your repo — treat this as a supply-chain risk.

## Migrating From Per-Repo Actions to Callers

Incremental migration:

1. Publish the reusable workflow in `shared-ci` with a `v0.x` tag.
2. In one pilot Go repo, swap the existing `.github/workflows/ci.yml` for a caller — open as PR, observe CI behavior for at least one merge cycle.
3. Roll out to remaining repos only after the pilot is stable for a week.
4. Delete per-repo action configs after callers are merged and CI is green on each.

Do not batch steps 2-4 across all repos on day one. One pilot, then fan out.

## Codecov: Go names files by import path, so `ignore` silently never fires

A Go coverage profile identifies files by import path, so every entry reaches
Codecov as `github.com/<org>/<repo>/users.go` rather than `users.go`. Nothing
strips that prefix by default, and two things break quietly:

- **`ignore:` stops matching.** Codecov compiles `examples/**` to
  `(?s:examples/.*)\Z`, anchored at the start, which a prefixed path cannot
  satisfy. Excluded directories stay in the project total at 0% and drag it
  down.
- **Codecov cannot map a report entry to a file in the repository**, so files
  can read 0% against a suite that covers them, and uploads merge
  unpredictably.

Add a `fixes:` entry with the module path:

```yaml
fixes:
  - "github.com/<org>/<repo>/::"     # strip the import-path prefix
```

The tell is a project percentage that does not move: totals identical across
commits that changed the tree (`lines` and `hits` byte-for-byte equal) mean the
report is not being recomputed, not that coverage happens to be stable. On one
repository this stood at 19.36% for thirty-two commits; after the `fixes:` entry
the same tree measured 88.77%, with the ignored directories gone from the report
and a previously absent flag appearing in it.

Validate before merging — the endpoint both checks the file and prints how each
pattern compiled, which is how you confirm an `ignore` entry can match at all:

```bash
curl -X POST --data-binary @codecov.yml https://codecov.io/validate
```

Two neighbouring traps once the paths are correct:

- **Per-flag `paths:` filters** such as `"**/*.go"` cannot match a prefixed entry
  either, so a flag's report can be filtered to nothing before the merge. In a
  single-language repository they restrict nothing `ignore` does not already
  cover; drop them rather than maintain a second place for a path mismatch to
  discard data.
- **Repairing the paths can arm a gate that was inert.** A `patch` status with
  `target: 100%` posts nothing while the report is broken; the moment paths
  resolve it starts failing pull requests against a threshold nobody chose. Set
  it `informational: true` in the same change and calibrate the target from the
  first corrected run.

## Common Anti-Patterns

| Anti-pattern | Consequence | Fix |
|--------------|-------------|-----|
| `secrets: inherit` | All org secrets exposed to every action in the chain | Explicit `secrets: { NAME: ${{ secrets.NAME }} }` per secret |
| Caller `permissions: write-all` | Overbroad; blast radius on compromised action | Enumerate only what the reusable workflow documents |
| Reusable workflow pinned `@main` | Silent behavior drift | Pin to released tag or full SHA |
| Missing outputs on reusable workflow | Downstream release gates can't get SHA/tag | Declare job outputs + workflow outputs |
| Per-repo duplication of `golangci-lint` config | Drift across repos; 4× maintenance | Centralize in reusable workflow + `.golangci.yml` template |
| `version: latest` for `golangci-lint-action` in CI | CI behavior drifts from local runs; rules fire in one but not the other | Pin the golangci-lint version in both; see `references/linting.md` → *golangci-lint: CI vs Local Version Drift* for the dual-`nolint` workaround when pinning isn't possible |
