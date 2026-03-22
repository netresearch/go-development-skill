# Architecture

## Overview

The go-development-skill is an Agent Skill package that provides production-grade Go development patterns to AI coding agents. It follows the [Agent Skills specification](https://agentskills.io) for cross-platform compatibility.

## Skill Structure

The skill uses a layered content architecture:

1. **SKILL.md** (`skills/go-development/SKILL.md`) -- Entry point loaded by the agent runtime. Contains metadata (name, version, triggers, allowed tools), core principles (type safety, consistency, conventions), and a reference table mapping topics to files.

2. **References** (`skills/go-development/references/`) -- Detailed procedural knowledge split by domain: architecture, cron scheduling, resilience, Docker, LDAP, testing, linting, API design, fuzz testing, mutation testing, Makefile patterns, modernization, and logging. Loaded on-demand to keep context window usage efficient.

3. **Scripts** (`skills/go-development/scripts/`) -- Executable verification scripts that validate a Go project's structure and tooling setup.

## Content Flow

```
Agent receives Go task
  → SKILL.md loaded (always)
  → Content trigger matched (e.g., "Docker integration")
  → Relevant reference loaded (e.g., docker.md)
  → Agent applies patterns from reference
  → Related skills invoked for comprehensive review
```

## Key Design Decisions

- **Reference-per-domain**: Each Go ecosystem concern gets its own reference file to minimize context window consumption.
- **Cross-skill invocation**: SKILL.md mandates invoking security-audit, enterprise-readiness, and github-project skills for comprehensive reviews.
- **Build tags for test isolation**: Integration and e2e tests use build tags to allow selective execution.

## Distribution

The skill is distributed via multiple channels:
- GitHub releases (`.tar.gz` archives)
- Composer package (`netresearch/go-development-skill`)
- Direct git clone
- npx skills CLI
