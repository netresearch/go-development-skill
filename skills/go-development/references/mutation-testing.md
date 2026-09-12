# Go Mutation Testing

Mutation testing measures test quality by introducing small code changes (mutations) and verifying tests detect them. Higher scores indicate more effective tests.

## Tool: Gremlins

[go-gremlins](https://github.com/go-gremlins/gremlins) is the recommended mutation testing tool for Go.

```bash
# Install
go install github.com/go-gremlins/gremlins/cmd/gremlins@v0.6.0

# Run
gremlins unleash --config=.gremlins.yaml
```

## Configuration

Create `.gremlins.yaml` in project root:

```yaml
# Packages to test
test-packages:
  - .
  - ./cmd/...
  - ./internal/...

# Mutator types to enable
mutators:
  - CONDITIONALS_BOUNDARY    # Change < to <=, > to >=
  - CONDITIONALS_NEGATION    # Negate conditions (== to !=)
  - INCREMENT_DECREMENT      # Change ++ to --
  - INVERT_LOGICAL           # Invert && to ||
  - INVERT_NEGATIVES         # Remove negation operators
  - INVERT_LOOPCTRL          # Change break to continue

# Files/patterns to exclude
exclude:
  - "**/*_test.go"           # Test files
  - "**/test/**"             # Test helpers
  - "**/mock/**"             # Mock implementations
  - "**/generated/**"        # Generated code

# Only mutate code covered by tests
coverage: true

# Minimum acceptable mutation score (%)
threshold: 60

# Timeout multiplier for test runs
timeout-coefficient: 5

# Output reports
output:
  json: mutation-report.json
  html: mutation-report.html

# Test timeout
test-timeout: 120s
```

## Understanding Results

| Metric | Meaning |
|--------|---------|
| **Killed** | Tests detected the mutation (good!) |
| **Survived** | Tests missed the mutation (needs improvement) |
| **Timed Out** | Tests hung on mutation (usually killed) |
| **Skipped** | Excluded from analysis |

**Test Efficacy** = (Killed + Timed Out) / Total Mutations

Target: **60%+ for production code**

## CI Integration

### GitHub Actions Workflow

```yaml
name: Mutation Testing

on:
  push:
    branches: [main]
  pull_request:
    paths:
      - '**.go'
      - '.gremlins.yaml'

jobs:
  mutation:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod

      - name: Install gremlins
        run: go install github.com/go-gremlins/gremlins/cmd/gremlins@v0.6.0

      - name: Run mutation tests
        run: |
          gremlins unleash --config=.gremlins.yaml 2>&1 | tee output.txt
          SCORE=$(grep -oP 'Test efficacy: \K[\d.]+' output.txt || echo "0")
          echo "Mutation Score: ${SCORE}%"
          if (( $(echo "$SCORE < 60" | bc -l) )); then
            echo "::warning::Mutation score below 60%"
          fi

      # The `|| echo "0"` above is load-bearing in a way that hides failure:
      # gremlins compiles the packages it mutates, and one it cannot build is
      # reported as "[build failed]" — after which it stops without printing
      # "Test efficacy" at all. The fallback then makes the job publish 0% and
      # pass, which reads as a measured result rather than a run that never
      # happened. Check for it explicitly.
      - name: Fail on packages gremlins could not build
        if: always()
        run: |
          [ -f output.txt ] || exit 0
          grep -q '\[build failed\]' output.txt || exit 0
          echo "::error::gremlins could not build these packages:"
          grep '\[build failed\]' output.txt
          exit 1

      - name: Upload reports
        uses: actions/upload-artifact@v4
        with:
          name: mutation-reports
          path: |
            mutation-report.json
            mutation-report.html
```

### Diff-Based Testing (PRs only)

For efficiency, only test mutations in changed files on PRs:

```yaml
- name: Run mutation tests (diff only)
  if: github.event_name == 'pull_request'
  run: |
    BASE_REF="${{ github.event.pull_request.base.sha }}"
    gremlins unleash --config=.gremlins.yaml --diff "$BASE_REF"
```

## A Score of 0% Means "Nothing Ran"

gremlins does not partially degrade. If any package it mutates fails to
compile, it prints `[build failed]` for that package and stops — no efficacy
line is emitted at all. Every score-extraction idiom in the wild falls back to
`0` when the line is missing, so the job publishes **0%** and passes.

This is easy to ship and hard to notice, because a low score looks like a
test-quality problem rather than a run that never happened.

Two things cause it in practice:

- **Generated sources that are not committed.** templ, sqlc, mockgen and
  friends produce `*.go` files that CI must generate before gremlins runs.
  A repo where `go test` works locally (generated files present) fails here.
  Pass the codegen command in a pre-build step.
- **Build tags.** A package that only compiles under `integration` or `e2e`
  fails the default build.

Put the `[build failed]` check in its **own step**. The run step usually
carries `continue-on-error: true` so a low score does not fail the workflow —
and that would swallow the build check too. A missing score is a threshold
question; a package that does not compile is not.

## Makefile Integration

```makefile
.PHONY: mutation
mutation:
	@echo "Running mutation tests..."
	@gremlins unleash --config=.gremlins.yaml

.PHONY: mutation-report
mutation-report: mutation
	@echo "Opening mutation report..."
	@open mutation-report.html 2>/dev/null || xdg-open mutation-report.html
```

## Improving Mutation Score

### Common Surviving Mutations

1. **Boundary conditions** - Add tests for `<` vs `<=`, `>` vs `>=`
2. **Error paths** - Test both success and failure cases
3. **Loop controls** - Verify break/continue behavior
4. **Negation** - Test both true and false conditions
5. **Increment/Decrement** - Check exact values, not just "changed"

### Example: Fixing a Survivor

```go
// Original code
func IsValid(x int) bool {
    return x > 0  // Mutation: x >= 0 survives
}

// Original test (insufficient)
func TestIsValid(t *testing.T) {
    assert.True(t, IsValid(1))   // x > 0 and x >= 0 both pass
    assert.False(t, IsValid(-1)) // x > 0 and x >= 0 both fail
}

// Fixed test (kills the mutation)
func TestIsValid(t *testing.T) {
    assert.True(t, IsValid(1))
    assert.False(t, IsValid(-1))
    assert.False(t, IsValid(0))  // Boundary case kills x >= 0
}
```

## Hand-rolled mutations: a build failure is not a caught defect

Gremlins is the tool, but a targeted question — "does anything actually pin this
one line?" — is usually answered faster by injecting the defect yourself. That
loop has a failure mode the tool does not have, and it reports the wrong answer
in the reassuring direction.

Removing a call often orphans its import. `go test ./...` then exits non-zero on
`"slices" imported and not used`, the loop sees a non-zero exit, and prints
CAUGHT for a mutation no assertion ever saw. The run measured the compiler.

Two rules follow:

- **Every mutation must build clean before its result counts.** Check for a
  compiler diagnostic (`# package` lines, `[build failed]`), not just the exit
  code. Where a mutation would orphan a symbol, keep it referenced —
  `_ = slices.Clone(x)`, `_ = uuid.New()` — so the defect is the only change.
- **Restore from a copy, never `git checkout -- <file>`.** That restores the last
  *committed* state, discarding the guard you just wrote and have not committed.
  `cp file /tmp/x.bak` first, `cp` back after each mutation, and run the full
  suite at the end to prove the tree is the one you think it is.

```bash
cp pkg/thing.go /tmp/thing.bak
# ... inject, then:
if ! out=$(go vet ./... 2>&1); then
  echo "DOES NOT BUILD — not evidence:"; echo "$out"
else
  go test ./...; echo "exit=$?"
fi
cp /tmp/thing.bak pkg/thing.go
```

The guard has to come first and it has to stop. `go build ... || echo warning`
prints the warning and then runs the suite anyway, so the compile failure still
reaches the exit code the loop reads — the sample would demonstrate the defect it
exists to prevent. Keep the diagnostic rather than discarding it to
`/dev/null`: "which mutation failed to build" is the thing you need next.

`go vet` is the gate rather than `go build`, because `go test` runs vet too. A
mutation that builds and only trips vet — a `%d` verb given a string, say —
passes a `go build` guard and then produces the identical
`FAIL [build failed]` the section is about.

A mutation that survives is the finding. Before writing the test that catches it,
check the assertion will reach the mutated code at all: a test that rebuilds the
production expression in its own body holds whatever production does, so it stays
green through every mutation of the real thing. Extract the expression into a
named function and have production call it.

Then have the test call it for the **actual** value only. The expected value must
come from somewhere the mutation cannot move: a literal, or an invariant of the
result. Calling the extracted function on both sides reproduces the original
defect one level up — a mutation shifts both sides together and the test stays
green. "The id splits into two parts on the underscore, the first is this literal
GUID, the second parses as a GUID, and two calls differ" are invariants; "equals
`membershipID(group)`" is not an assertion at all.

## Best Practices

1. **Start with 60% threshold** - Increase as tests mature
2. **Exclude generated code** - Focus on hand-written logic
3. **Use coverage mode** - Only mutate tested code
4. **Run on CI** - Catch regressions early
5. **Diff mode for PRs** - Full runs on main branch only

## Related

- `references/testing.md` - General testing patterns
- `references/fuzz-testing.md` - Complementary input validation testing
- [go-gremlins documentation](https://github.com/go-gremlins/gremlins)
