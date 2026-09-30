<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: Netresearch DTT GmbH -->

# Go Development Skill

Production-grade Go development patterns for building resilient services, extracted from real-world projects including job schedulers, Docker integrations, and LDAP clients.

## 🔌 Compatibility

This is an **Agent Skill** following the [open standard](https://agentskills.io) originally developed by Anthropic and released for cross-platform use.

**Supported Platforms:**
- ✅ Claude Code (Anthropic)
- ✅ Cursor
- ✅ GitHub Copilot
- ✅ Other skills-compatible AI agents

> Skills are portable packages of procedural knowledge that work across any AI agent supporting the Agent Skills specification.


## Features

- **Architecture Patterns**: Package structure conventions, state mutation completeness
- **Cron Scheduling**: go-cron patterns — named jobs, runtime updates, per-entry context, resilience wrappers, observability, FakeClock testing, bitmask parser options
- **Resilience Patterns**: go-cron's built-in retry/circuit-breaker/timeout wrappers for scheduled jobs
- **Docker Integration**: Optimized Docker client patterns, buffer pooling for performance, container execution patterns
- **LDAP Integration**: Active Directory patterns, user and group management, authentication flows
- **Testing Strategy**: Build tags for test isolation (unit/integration/e2e), race-condition and Fiber v2 test gotchas, resource isolation
- **Observability**: Prometheus metrics integration, structured logging, error tracking

## Installation

### Marketplace (Recommended)

Add the [Netresearch marketplace](https://github.com/netresearch/claude-code-marketplace) once, then browse and install skills:

```bash
# Claude Code
/plugin marketplace add netresearch/claude-code-marketplace
/plugin install go-development@netresearch-claude-code-marketplace
```

### Without a marketplace

Since Claude Code 2.1.157 a plugin directory under your personal skills directory loads on its own:

```bash
mkdir -p ~/.claude/skills
git clone https://github.com/netresearch/go-development-skill.git \
  ~/.claude/skills/go-development
```

It loads as `go-development@skills-dir` on the next session. Update with `git -C ~/.claude/skills/go-development pull` and start a new session; remove it by deleting the directory. This route has no `claude plugin update`.

### npx ([skills.sh](https://skills.sh))

Install with any [Agent Skills](https://agentskills.io)-compatible agent:

```bash
npx skills add https://github.com/netresearch/go-development-skill --skill go-development
```

### Download Release

Download the [latest release](https://github.com/netresearch/go-development-skill/releases/latest) and extract to your agent's skills directory.

### Git Clone

```bash
git clone https://github.com/netresearch/go-development-skill.git
```

### Composer (PHP Projects)

```bash
composer require netresearch/go-development-skill
```

Requires [netresearch/composer-agent-skill-plugin](https://github.com/netresearch/composer-agent-skill-plugin).
## Usage

This skill is automatically triggered when:

- Building Go services or CLI applications
- Implementing job scheduling or task orchestration
- Integrating with Docker API
- Building LDAP/Active Directory clients
- Designing resilient systems with retry logic
- Setting up comprehensive test suites

Example queries:
- "Create a resilient job scheduler in Go"
- "Implement Docker container execution with retry logic"
- "Build LDAP authentication client"
- "Set up graceful shutdown for Go service"
- "Implement buffer pooling for high-throughput operations"
- "Create comprehensive test suite with build tags"

## Structure

```
go-development-skill/
├── skills/go-development/
│   ├── SKILL.md                              # Skill metadata and core patterns
│   ├── checkpoints.yaml                      # Assessment checkpoints for Go projects
│   ├── evals/evals.json                      # Skill evaluation cases
│   ├── scripts/verify-go-project.sh          # Go project verification
│   └── references/
│       ├── api-design.md                     # Enum/status defensive handling
│       ├── architecture.md                   # Package structure, state mutation completeness
│       ├── awesome-go-submission.md          # Submitting a project to awesome-go
│       ├── branch-protection.md              # Branch protection standard for Go repos
│       ├── contracts-and-invariants.md       # Contracts and invariants
│       ├── cron-scheduling.md                # go-cron: named jobs, updates, context, resilience
│       ├── dependencies.md                   # Dependency upgrades
│       ├── docker.md                         # Docker client patterns
│       ├── fuzz-testing.md                   # Go fuzzing patterns, security seeds
│       ├── ldap.md                           # LDAP/Active Directory integration
│       ├── lefthook-template.md              # Lefthook git hooks for Go projects
│       ├── linting.md                        # golangci-lint v2 configuration
│       ├── logging.md                        # Structured logging with log/slog
│       ├── makefile.md                       # Standard Makefile interface
│       ├── modernization.md                  # Go 1.26 modernizers, go fix, errors.AsType
│       ├── mutation-testing.md               # Gremlins test quality measurement
│       ├── resilience.md                     # Pointer to go-cron's resilience wrappers
│       ├── reusable-workflows.md             # Reusable GitHub workflows for Go repos
│       ├── single-build-release.md           # Single-build release pipeline
│       └── testing.md                        # Build tags, race and Fiber v2 gotchas
├── Build/                                    # Plugin version check and pre-push hook
├── scripts/verify-harness.sh                 # Agent harness consistency checker
├── tests/                                    # Behavioural tests for the scripts
└── docs/ARCHITECTURE.md                      # Architecture of this repository
```

## Expertise Areas

### Architecture Patterns
- Package structure conventions
- State mutation completeness (avoiding partial updates)

### Cron Scheduling (go-cron)
- Named jobs with O(1) lookup
- Runtime updates (UpsertJob, UpdateSchedule, UpdateEntry)
- Per-entry context with automatic cancellation
- Resilience wrappers (retry, circuit breaker, timeout)
- Observability hooks (Prometheus integration)
- FakeClock for deterministic testing
- Missed job catch-up policies

### Resilience Patterns
- Retry, circuit-breaker, and timeout wrappers built into go-cron for scheduled jobs
- Standard library-backed patterns (rate limiting, graceful shutdown) outside the job scheduler

### Docker Integration
- Optimized Docker client patterns
- Buffer pooling for performance
- Container execution patterns

### LDAP Integration
- Active Directory patterns
- User and group management
- Authentication flows

### Testing Strategy
- Build tags for test isolation (unit/integration/e2e)
- Race-condition gotchas and fixes
- Resource isolation (one instance per test)
- Fiber v2 test patterns

## Running Go Tests

The test commands the skill recommends for Go projects:

```bash
# Unit tests only (default)
go test ./...

# With integration tests
go test -tags=integration ./...

# Full suite including E2E
go test -tags=e2e ./...

# With race detector
go test -race ./...

# With coverage
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out
```

## Quality Gates

### Recommended Tooling

```makefile
.PHONY: dev-check
dev-check: fmt vet lint security test

fmt:
	gofmt -w $(shell git ls-files '*.go')
	gci write .

vet:
	go vet ./...

lint:
	golangci-lint run --timeout 5m

security:
	gosec ./...
	gitleaks detect

test:
	go test -race ./...
```

## Related Skills

This skill focuses on Go code patterns and quality. For complete project setup:

| Skill | Purpose |
|-------|---------|
| `github-project` | Repository setup, branch protection, auto-merge workflows |
| `enterprise-readiness` | OpenSSF Scorecard, SLSA provenance, signed releases |
| `security-audit` | OWASP Top 10, CVE analysis, security hardening |

## Tests

This section is about the tests of this repository; the Go test commands above are what the skill recommends for Go projects. The behavioural tests live in `tests/` and run offline; they need bash, git, python3 and the usual coreutils, find, grep and awk. No Go toolchain is needed:

```bash
bash tests/verify-go-project.sh    # skills/go-development/scripts/verify-go-project.sh
bash tests/check-plugin-version.sh # Build/Scripts/check-plugin-version.sh and Build/hooks/pre-push
```

- `tests/verify-go-project.sh` runs the verifier against fixture projects with a stub `go` on `PATH` that records where `go vet` ran and exits with a chosen status, or with no `go` on `PATH` at all. It checks the exit codes, that every section runs after a failed item, the error and warning counts, and that a relative project path is resolved correctly.
- `tests/check-plugin-version.sh` builds throwaway git repositories and checks that a semver tag at `HEAD` must match the version in `.claude-plugin/plugin.json`, and that the pre-push hook passes the result on.

Each check prints `ok` or `FAIL`; a `FAIL` line names the expectation that was not met and is followed by the script's output. A test file exits 1 when any check failed. In CI, the Skill Tests workflow (`.github/workflows/tests.yml`) runs every `tests/**/*.sh` on each pull request and on pushes to `main`, and fails when the repository ships scripts under `skills/*/scripts/` but no test ran.

`scripts/verify-harness.sh` has no test of its own; on pull requests, Harness Verification (`harness-verify.yml`) checks `AGENTS.md` (presence, length, links, documented commands) and `docs/ARCHITECTURE.md` with its own steps. The skill's Markdown is not executed here; Skill Validation and Eval Validation check its structure and the eval definitions in `skills/go-development/evals/evals.json`. A pull request that adds or changes behaviour in a script adds or updates a check in `tests/` that fails without the change.

## Governance and policies

This repository follows the Netresearch organisation policies:

- [Governance](https://github.com/netresearch/.github/blob/main/GOVERNANCE.md): ownership, roles, how decisions are made and disputes resolved, and continuity.
- [Roadmap](https://github.com/netresearch/.github/blob/main/ROADMAP.md): planned and explicitly excluded work for the coming year.
- [Handling of dependency and code analysis findings](https://github.com/netresearch/.github/blob/main/SECURITY.md#handling-of-dependency-and-code-analysis-findings): thresholds, deadlines and the exception process for dependency (SCA) and static analysis (SAST) findings.
- [Secret management](https://github.com/netresearch/.github/blob/main/SECURITY.md#secret-management): how CI and release credentials are stored, accessed and rotated.
- [Access roster](https://github.com/netresearch/.github/blob/main/docs/access-roster.md): who holds administrative access to this repository and the organisation.

The security assurance case for this skill (threat model, trust boundaries, countermeasures and limits) is in [docs/SECURITY-ASSURANCE.md](docs/SECURITY-ASSURANCE.md).

Checks that run on pull requests in this repository:

- Every pull request: Skill Validation (`lint.yml`: skill structure, markdownlint, yamllint, actionlint, JSON syntax, ShellCheck, ruff, checkpoint schema), Eval Validation (`eval-validate.yml`) and Skill Tests (`tests.yml`).
- Pull requests to `main`: `security.yml` with Betterleaks (secret scanning), zizmor (workflow static analysis), dependency review, Composer Audit and Opengrep SAST; Harness Verification (`harness-verify.yml`) and Template Drift (`check-template-drift.yml`). The organisation's security policy sets when dependency review and Opengrep fail: see [dependencies](https://github.com/netresearch/.github/blob/main/SECURITY.md#dependencies-software-composition-analysis) and [static analysis (SAST)](https://github.com/netresearch/.github/blob/main/SECURITY.md#static-analysis-sast).
- Also on every pull request: Labeler (`labeler.yml`), the DCO sign-off check and SonarCloud Code Analysis (both GitHub Apps) and, for dependency-update pull requests, auto-merge (`auto-merge-deps.yml`). CodeQL for `actions` runs through GitHub's default setup.

## License

This project uses split licensing:

- **Code** (scripts, workflows, configs): [MIT](LICENSE-MIT)
- **Content** (skill definitions, documentation, references): [CC-BY-SA-4.0](LICENSE-CC-BY-SA-4.0)

See the individual license files for full terms.
## Credits

Developed and maintained by [Netresearch DTT GmbH](https://www.netresearch.de/).

---

**Made with ❤️ for Open Source by [Netresearch](https://www.netresearch.de/)**
