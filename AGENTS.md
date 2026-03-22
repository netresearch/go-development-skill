# Go Development Skill

Production-grade Go development patterns for building resilient services, job schedulers, Docker integrations, and LDAP clients.

## Repo Structure

```
├── skills/go-development/
│   ├── SKILL.md                    # Skill metadata and core patterns
│   ├── checkpoints.yaml            # Skill checkpoints
│   ├── evals/                      # Skill evaluations
│   ├── references/                 # Detailed reference docs (see below)
│   └── scripts/
│       └── verify-go-project.sh    # Go project verification
├── Build/
│   ├── Scripts/                    # Build/validation scripts
│   └── hooks/                      # Git hook templates (pre-push)
├── scripts/
│   └── verify-harness.sh           # Harness consistency checker
├── .github/workflows/              # CI workflows (lint, release, auto-merge)
├── docs/                           # Architecture and planning docs
├── composer.json                   # Composer package manifest
└── README.md
```

## Commands

No build system scripts defined in composer.json. Basic operations:

- `bash skills/go-development/scripts/verify-go-project.sh` -- verify Go project setup
- `bash scripts/verify-harness.sh --status` -- check harness maturity level
- `go test ./...` -- run unit tests
- `go test -tags=integration ./...` -- run integration tests
- `golangci-lint run` -- lint Go code

## Rules

- Prefer generics `[T any]` over `interface{}`; use `errors.AsType[T]` (Go 1.26+)
- Errors: lowercase, no punctuation (`errors.New("invalid input")`)
- One pattern per problem domain; match existing codebase patterns
- Test pyramid: unit (<100ms) / integration (1-5s) / e2e (5-30s) with build tags
- Configuration precedence: defaults < config file < external source < flags < env vars
- Always run related skills for comprehensive reviews (security-audit, enterprise-readiness, github-project)
- Load reference files on-demand based on content triggers (see SKILL.md)

## References

- [SKILL.md](skills/go-development/SKILL.md) -- core skill definition and triggers
- [Architecture Patterns](skills/go-development/references/architecture.md)
- [Cron Scheduling](skills/go-development/references/cron-scheduling.md)
- [Resilience Patterns](skills/go-development/references/resilience.md)
- [Docker Integration](skills/go-development/references/docker.md)
- [LDAP Integration](skills/go-development/references/ldap.md)
- [Testing Strategy](skills/go-development/references/testing.md)
- [Linting (golangci-lint)](skills/go-development/references/linting.md)
- [API Design](skills/go-development/references/api-design.md)
- [Fuzz Testing](skills/go-development/references/fuzz-testing.md)
- [Mutation Testing](skills/go-development/references/mutation-testing.md)
- [Makefile Patterns](skills/go-development/references/makefile.md)
- [Go Modernization](skills/go-development/references/modernization.md)
- [Logging](skills/go-development/references/logging.md)
- [Architecture](docs/ARCHITECTURE.md)
