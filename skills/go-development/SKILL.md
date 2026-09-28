---
name: go-development
description: "Use when fixing a reported Go bug or security issue (a fix leaves go.mod, go.sum and unrelated files untouched and adds a unit test the default go test runs without a container), developing Go applications, implementing job schedulers or cron (netresearch/go-cron, ofelia), Docker API integrations, LDAP/AD clients, building resilient services with retry logic, setting up Go test suites (unit/integration/fuzz/mutation), or running golangci-lint."
license: "(MIT AND CC-BY-SA-4.0). See LICENSE-MIT and LICENSE-CC-BY-SA-4.0"
compatibility: "Requires go 1.21+, golangci-lint, docker."
metadata:
  author: Netresearch DTT GmbH
  version: "1.14.0"
  repository: https://github.com/netresearch/go-development-skill
allowed-tools: Bash(go:*) Bash(make:*) Bash(docker:*) Bash(golangci-lint:*) Read Write Glob Grep
---

# Go Development Patterns

## Required Workflow

**For reviews, invoke related skills:** security-audit (OWASP), enterprise-readiness (OpenSSF/SLSA), github-project (branch protection).

## Core Principles

### Type Safety

- **Avoid:** `interface{}` (use `any`), `sync.Map`, scattered type assertions, reflection
- **Prefer:** Generics `[T any]`, `errors.AsType[T]` (Go 1.26), concrete types
- Run `go fix ./...` after upgrades

### Consistency

- One pattern per problem domain
- Match existing codebase patterns
- Refactor holistically or not at all
- Config precedence: defaults < config file < env vars < flags

### Testing

- Build tags isolate test tiers: unit (default), `integration`, `e2e`
- Always use `t.Parallel()`, `t.Helper()`, table-driven subtests
- Use `log/slog` directly -- never wrap it in custom Logger interfaces

### Conventions

- Naming: ID, URL, HTTP (not Id, Url, Http) — not tool-enforced (ST1003 is off by default)
- Error wrapping: `fmt.Errorf("failed to process: %w", err)`

## References

Git hooks: `ls lefthook.yml 2>/dev/null && lefthook install || echo "Add lefthook — see references/lefthook-template.md"`

| Reference | Purpose |
|-----------|---------|
| `references/reported-defects.md` | Fixing a reported bug: guard test, minimal diff |
| `references/architecture.md` | Package structure, state mutation completeness |
| `references/logging.md` | log/slog, migration from logrus |
| `references/cron-scheduling.md` | go-cron patterns, runtime updates |
| `references/resilience.md` | Pointer to go-cron's built-in retry/circuit-breaker/timeout wrappers |
| `references/docker.md` | Docker client patterns, buffer pooling |
| `references/ldap.md` | LDAP/Active Directory integration |
| `references/testing.md` | Build tags, resource isolation, race gotchas |
| `references/linting.md` | golangci-lint v2, staticcheck, code quality |
| `references/api-design.md` | Defensive enum handling |
| `references/fuzz-testing.md` | Go fuzzing patterns, security seeds |
| `references/contracts-and-invariants.md` | Contracts, invariants, property tests |
| `references/mutation-testing.md` | Gremlins mutation testing |
| `references/makefile.md` | Standard Makefile interface for CI/CD |
| `references/modernization.md` | Go 1.26 modernizers, `go fix`, `errors.AsType[T]`, `wg.Go()` |
| `references/dependencies.md` | Upgrades: `go get -u all`, majors |
| `references/lefthook-template.md` | lefthook.yml for Go git hooks |
| `references/reusable-workflows.md` | Reusable workflow callers, permissions |
| `references/single-build-release.md` | Cross-compile once for release and container |
| `references/awesome-go-submission.md` | awesome-go submission |

## Quality Gates

Before any review:

```bash
golangci-lint run --timeout 5m
go vet ./...
staticcheck ./...
govulncheck ./...
go test -race ./...
```

## Stdlib Vulnerability Fixes

When `govulncheck` reports stdlib vulnerabilities: check fix version via `vuln.go.dev`, update `go X.Y.Z` in `go.mod`, run `go mod tidy`.

---

> **Contributing:** Submit improvements to https://github.com/netresearch/go-development-skill
