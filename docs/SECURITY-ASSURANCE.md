<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: Netresearch DTT GmbH -->

# Security assurance case — go-development-skill

This document states what a user can expect from this repository in terms of security, and argues why that expectation holds. Every claim names the file that implements it. Reporting a vulnerability: see the [security policy](https://github.com/netresearch/.github/blob/main/SECURITY.md). Components: [ARCHITECTURE.md](ARCHITECTURE.md).

## What the repository ships

| Part | Files | Runs where |
| --- | --- | --- |
| Skill instructions for an AI agent | `skills/go-development/SKILL.md`, `skills/go-development/references/*.md` | Read by the agent as instructions; not executed. The agent may run the `go`, `make`, `docker` and `golangci-lint` commands they describe in the user's Go project. |
| Verifier script | `skills/go-development/scripts/verify-go-project.sh` | On the user's machine, in the Go project directory it is given. |
| Checkpoints | `skills/go-development/checkpoints.yaml` | Only when an assessment tool runs its `command` patterns in a user's project, or hands its `llm_reviews` prompts to a model. |
| Eval definitions | `skills/go-development/evals/evals.json` | Data read by the eval validator; not executed. |
| Repository checks | `Build/Scripts/check-plugin-version.sh`, `Build/hooks/pre-push`, `scripts/verify-harness.sh`, `tests/*.sh` | In this repository's CI and on contributors' machines. |

The repository ships no server component, no container image and no Go code. It stores nothing and handles no user accounts or credentials of its own.

## Security requirements

1. `verify-go-project.sh` and the checkpoints only read the assessed project: they change no file in it.
2. The verifier reports every check it runs and fails when a required item (`go.mod`, a clean `go vet`) is missing, so a failed result is not hidden by an earlier one.
3. Nothing committed to this repository contains a secret.
4. A release carries the version that `.claude-plugin/plugin.json` states, and its archives can be verified against the build that produced them.
5. Changes reach `main` only through pull requests that pass the checks listed in the README.

## Actors and trust boundaries

- **Skill user and agent.** The agent reads `SKILL.md` and the references and runs commands in the user's project with the user's privileges. What it runs is decided by the agent and the user, not by this repository. `allowed-tools` in `SKILL.md` pre-approves `go`, `make`, `docker`, `golangci-lint`, `Read`, `Write`, `Glob` and `Grep`; it does not take any tool away from the agent.
- **Assessed Go project.** `verify-go-project.sh` reads files below the directory it is given and runs `go vet ./...` inside it. The project's `go.mod`, source and build configuration are input from outside this repository; `go vet` compiles the packages and resolves their modules through the user's Go toolchain and module settings.
- **Assessment tool.** `checkpoints.yaml` patterns of `type: command` run as shell commands in the assessed project's working directory with the privileges of whoever starts the tool.
- **GitHub API.** `scripts/verify-harness.sh` sends one read request (`gh api repos/<org>/.github/contents/pull_request_template.md`) with the contributor's `gh` authentication, and ignores its failure.
- **Contributors.** Changes reach `main` through pull requests, checked by the workflows in `.github/workflows/`. `.envrc` (used by direnv) sets `core.hooksPath` to `Build/hooks`, so a contributor who allows it runs the repository's `pre-push` hook.
- **CI.** Workflows run on GitHub-hosted runners with `permissions: {}` at the top level and grant each job only the scopes its called reusable workflow needs (`.github/workflows/*.yml`). The two `pull_request_target` workflows (`auto-merge-deps.yml`, `labeler.yml`) only call reusables that merge or label and do not check out pull request code; `auto-merge-deps.yml` passes two named secrets instead of `secrets: inherit`.

## Threats and countermeasures

| Threat | Countermeasure | Evidence |
| --- | --- | --- |
| A project path with spaces or shell metacharacters is split or interpreted by the shell (CWE-78) | The directory argument is used only in double-quoted expansions; `go vet` runs in a subshell after `cd "$PROJECT_DIR"` | `verify-go-project.sh` |
| The verifier checks the wrong directory and reports items as present or missing that are not | `go vet` runs in a subshell, so later checks resolve paths against the directory given, including relative paths | `verify-go-project.sh`; `tests/verify-go-project.sh` ("test files are found for a relative project path", "go vet runs inside the project directory") |
| A missing item stops the run, and the result hides the remaining checks | Counters are incremented with `X=$((X + 1))`, which cannot fail under `set -e`; the summary and exit status always follow all sections | `verify-go-project.sh`; `tests/verify-go-project.sh` ("missing go.mod does not stop the run", "go vet findings do not stop the run") |
| A `go vet` finding or a missing `go.mod` is reported as a pass | Both increment the error count; any error makes the verifier exit 1 | `verify-go-project.sh`; `tests/verify-go-project.sh` ("missing go.mod fails", "go vet findings fail the run") |
| A checkpoint modifies the assessed project | Every `command` pattern is a `test`, `find` or `grep` pipeline that only reads files and exits with a status; the other checkpoints are file-existence, content and regex checks and model prompts | `checkpoints.yaml` |
| A release is tagged with a version that disagrees with `plugin.json` | The pre-push hook runs `check-plugin-version.sh`, which fails when a semver tag at `HEAD` differs from `.claude-plugin/plugin.json` | `Build/hooks/pre-push`, `Build/Scripts/check-plugin-version.sh`; `tests/check-plugin-version.sh` |
| A released archive is tampered with | The release workflow publishes a Cosign-signed `SHA256SUMS.txt` and build-provenance attestations for the archives | `.github/workflows/release.yml` (calls the skill-repo-skill release reusable) |
| A secret is committed | Betterleaks scans every push to `main` and every pull request to `main` | `.github/workflows/security.yml` |
| A vulnerable or malicious dependency is added | Dependency review checks the dependencies a pull request adds or changes against known vulnerabilities; Composer Audit checks the Composer dependency (`netresearch/composer-agent-skill-plugin`) against known advisories; Renovate proposes updates, including pre-commit hook revisions | `.github/workflows/security.yml`, `composer.json`, `renovate.json` |
| Insecure code or workflow patterns | Opengrep scans the code for insecure patterns; zizmor analyses the workflows; ShellCheck runs on every `*.sh` file in Skill Validation, and the pre-commit hook runs it at its default `style` severity | `.github/workflows/security.yml`, `.github/workflows/lint.yml`, `.pre-commit-config.yaml` |
| A behaviour change in a shipped script goes unnoticed | Skill Tests runs `tests/**/*.sh` on every pull request and fails when scripts ship under `skills/*/scripts/` without a test run | `.github/workflows/tests.yml`, `tests/` |
| A failing step continues with partial state | `check-plugin-version.sh` and `verify-harness.sh` run with `set -euo pipefail`; `verify-go-project.sh` runs with `set -e` and counts results without commands that can fail | the scripts named |

Which of these checks must pass before a pull request can merge is set in the branch protection of `main`, not in this repository.

## Secure design principles applied

- **Least privilege:** the verifier and the checkpoints only read; `verify-harness.sh` sends one read request. Workflows start from `permissions: {}` and grant per job.
- **Fail-safe defaults:** the verifier exits 1 on any error and prints every check; `check-plugin-version.sh` fails when it cannot read a version while a semver tag is present.
- **Economy of mechanism:** the scripts need bash, coreutils, `find`, `grep`, `awk`, `git` and, for the version check, `python3`; the verifier uses `go` only when it is installed.
- **Open design:** everything the skill tells an agent to do is plain text in `SKILL.md` and `references/`, reviewable before use.

## What a user cannot expect

- The skill gives guidance; it does not enforce it. The agent runs commands with the user's privileges, and `allowed-tools` only removes the confirmation prompt for the tools it lists. Review what an agent proposes to run.
- `verify-go-project.sh` runs `go vet ./...` in the given project. That compiles the project's packages (including cgo code), may download its modules, and, depending on the user's `GOTOOLCHAIN` setting, may download and run the Go toolchain version that `go.mod` requests. Run the verifier only on projects you trust.
- The verifier checks the presence of files and a clean `go vet`, not the quality of tests, Dockerfile or Makefile.
- The checkpoints run shell commands in the assessed project when an assessment tool executes them; run them only in projects you trust. The LLM review checkpoints are judgements by a model and can miss issues.
- Code in `references/` is example code to adapt. For instance, the LDAP client in `references/ldap.md` takes configuration options that connect without TLS or skip certificate verification; a project adopting it decides how those are set.
- Security fixes follow the supported-versions rules of the organisation's security policy; older releases may not receive them.
