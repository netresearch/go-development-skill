---
name: go-development
description: "Use when developing Go applications, implementing job schedulers or cron, Docker API integrations, LDAP/AD clients, building resilient services with retry logic, setting up Go test suites (unit/integration/fuzz/mutation), running golangci-lint, or optimizing Go performance."
license: "(MIT AND CC-BY-SA-4.0). See LICENSE-MIT and LICENSE-CC-BY-SA-4.0"
compatibility: "Requires go 1.21+, golangci-lint, docker."
metadata:
  author: Netresearch DTT GmbH
  version: "1.8.0"
  repository: https://github.com/netresearch/go-development-skill
allowed-tools: Bash(go:*) Bash(make:*) Bash(docker:*) Bash(golangci-lint:*) Read Write Glob Grep
---

# Go Development Patterns

## When to Use

- Building Go services or CLI applications
- Implementing job scheduling or task orchestration
- Integrating with Docker API
- Building LDAP/Active Directory clients
- Designing resilient systems with retry logic
- Setting up comprehensive test suites

## Required Workflow

**For comprehensive reviews, ALWAYS invoke these related skills:**

1. **Security audit** - Invoke `/netresearch-skills-bundle:security-audit` for OWASP analysis, vulnerability assessment, and security patterns
2. **Enterprise readiness** - Invoke `/netresearch-skills-bundle:enterprise-readiness` for OpenSSF Scorecard, SLSA compliance, supply chain security
3. **GitHub project setup** - Invoke `/netresearch-skills-bundle:github-project` for branch protection, rulesets, CI workflow validation

A Go review is NOT complete until all related skills have been executed.

## Core Principles

### Type Safety

- **Avoid:** `interface{}` (use `any`), `sync.Map`, scattered type assertions, reflection
- **Prefer:** Generics `[T any]`, `errors.AsType[T]` (Go 1.26), concrete types
- Run `go fix ./...` after upgrades

### Consistency

- One pattern per problem domain
- Match existing codebase patterns
- Refactor holistically or not at all

### Conventions

- Errors: lowercase, no punctuation (`errors.New("invalid input")`)
- Naming: ID, URL, HTTP (not Id, Url, Http)
- Error wrapping: `fmt.Errorf("failed to process: %w", err)`

## References

Git hooks: `ls lefthook.yml 2>/dev/null && lefthook install || echo "Add lefthook — see references/lefthook-template.md"`

Load as needed:

| Reference | Purpose |
|-----------|---------|
| `references/architecture.md` | Package structure, config management, middleware chains |
| `references/logging.md` | Structured logging with log/slog, migration from logrus |
| `references/cron-scheduling.md` | go-cron patterns: named jobs, runtime updates, context, resilience |
| `references/resilience.md` | Retry logic, graceful shutdown, context propagation |
| `references/docker.md` | Docker client patterns, buffer pooling |
| `references/ldap.md` | LDAP/Active Directory integration |
| `references/testing.md` | Test strategies, build tags, table-driven tests |
| `references/linting.md` | golangci-lint v2, staticcheck, code quality |
| `references/api-design.md` | Bitmask options, functional options, builders |
| `references/fuzz-testing.md` | Go fuzzing patterns, security seeds |
| `references/mutation-testing.md` | Gremlins configuration, test quality measurement |
| `references/makefile.md` | Standard Makefile interface for CI/CD |
| `references/modernization.md` | Go 1.26 modernizers, `go fix`, `errors.AsType[T]`, `wg.Go()` |
| `references/lefthook-template.md` | Ready-to-use lefthook.yml for Go project git hooks |

## Quality Gates

Run before completing any review:

```bash
golangci-lint run --timeout 5m    # Linting
go vet ./...                       # Static analysis
staticcheck ./...                  # Additional checks
govulncheck ./...                  # Vulnerability scan
go test -race ./...                # Race detection
```

## Stdlib Vulnerability Fixes

When `govulncheck` reports stdlib vulnerabilities: check fix version via `vuln.go.dev`, update `go X.Y.Z` in `go.mod`, run `go mod tidy`. Use PR branches for repos with branch protection.

---

> **Contributing:** Submit improvements to https://github.com/netresearch/go-development-skill
