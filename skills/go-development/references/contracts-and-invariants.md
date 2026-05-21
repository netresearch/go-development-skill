# Contracts & Invariants

Encode preconditions, postconditions, and invariants as runtime checks in the code path. Treat them as the bridge between a spec sentence and the tests that verify it.

## When to Use

Use contracts where invariants are crystalline and a violation is a bug, not user error:

- State machines (workflows, consensus, session lifecycle, leases)
- Protocols (Paxos/Raft, two-phase commit, request/response correlation)
- Concurrency primitives (locks, queues, pools, supervised goroutines)
- Money, quantities, identifiers (never-negative, monotonic, bounded ranges)
- Data migrations (row count preserved, no orphaned references)
- Authorization boundaries (see security-audit-skill cross-link)

## When NOT to Use

- Plain CRUD glue, HTTP handler plumbing, config parsing — use input validation, not contracts
- Anything driven by external input — that is validation (return error), not an invariant (panic)
- Frontend/template code, doc generation, scripts

A useful test: would a violation indicate the program is in an impossible state? Yes → contract. No → validation.

## Contract Types

| Kind | Where | If violated |
|------|-------|-------------|
| Precondition | First lines of a function | Caller bug — panic |
| Postcondition | Just before `return` | Implementation bug — panic |
| Invariant | At every public entry/exit of a stateful type | Either — panic |

External-input checks are separate: return a typed error, do not panic.

## Go Idioms

### Doc convention

Document contracts inline so reviewers (and AI) see intent next to code:

```go
// Withdraw debits amount from the account.
//
// Contract:
//   pre:  amount > 0
//   pre:  amount <= balance
//   post: balance == old(balance) - amount
//   inv:  balance >= 0
func (a *Account) Withdraw(amount Money) error {
    assertf(amount > 0, "precondition: amount > 0, got %v", amount)
    if amount > a.balance {
        return ErrInsufficientFunds  // validation, not a contract
    }
    before := a.balance
    a.balance -= amount
    assertf(a.balance == before-amount, "postcondition violated")
    assertf(a.balance >= 0, "invariant: balance >= 0")
    return nil
}
```

### Assertion helper

Keep one helper. Do not scatter ad-hoc `panic`s:

```go
// Package internal/invariant
package invariant

import "fmt"

// Assert panics with msg when cond is false.
// Use only for impossible states. Use returned errors for user input.
func Assert(cond bool, msg string) {
    if !cond {
        panic("invariant: " + msg)
    }
}

func Assertf(cond bool, format string, args ...any) {
    if !cond {
        panic("invariant: " + fmt.Sprintf(format, args...))
    }
}
```

### Strip in release (optional)

For hot paths where the check itself is expensive, gate with a build tag:

```go
//go:build assertions

package invariant

func Assert(cond bool, msg string)        { if !cond { panic("invariant: " + msg) } }
func Assertf(cond bool, f string, a ...any) { if !cond { panic("invariant: " + fmt.Sprintf(f, a...)) } }
```

```go
//go:build !assertions

package invariant

func Assert(cond bool, msg string)            {}
func Assertf(cond bool, f string, a ...any)   {}
```

Run tests and staging with `-tags=assertions`; ship release builds without. Most code should keep checks always-on — only strip when profiling proves cost.

### Constructors fail fast

Establish invariants at construction so methods can rely on them:

```go
func NewAccount(initial Money) (*Account, error) {
    if initial < 0 {
        return nil, fmt.Errorf("initial balance: %w", ErrNegative)
    }
    return &Account{balance: initial}, nil
}
```

Validation at the boundary → typed error. Invariant inside → panic.

## Property Tests from Contracts

A postcondition is a property. A property test asserts the postcondition holds for many inputs.

### stdlib `testing/quick` (lightweight)

```go
func TestWithdraw_PreservesNonNegativeBalance(t *testing.T) {
    f := func(initial, amount uint32) bool {
        a, _ := NewAccount(Money(initial))
        _ = a.Withdraw(Money(amount))
        return a.balance >= 0
    }
    if err := quick.Check(f, &quick.Config{MaxCount: 1000}); err != nil {
        t.Fatal(err)
    }
}
```

### `pgregory.net/rapid` (state machines, recommended for protocols)

```go
import "pgregory.net/rapid"

func TestAccount_Properties(t *testing.T) {
    rapid.Check(t, func(t *rapid.T) {
        initial := rapid.Uint32Range(0, 1_000_000).Draw(t, "initial")
        a, _ := NewAccount(Money(initial))

        ops := rapid.SliceOf(rapid.Uint32Range(0, 10_000)).Draw(t, "ops")
        for _, op := range ops {
            _ = a.Withdraw(Money(op))
            // Invariant always holds — no need to repeat per op
            if a.balance < 0 {
                t.Fatalf("balance went negative: %v", a.balance)
            }
        }
    })
}
```

For protocols, model the state machine and let `rapid` drive transitions. The contract panics inside the implementation will surface any reachable invariant violation.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Panicking on user input | Return a typed error; reserve panic for impossible states |
| Sprinkling `assert` decoratively in glue code | Gate by domain — state machines, protocols, money, authz |
| Postcondition that re-implements the function | Postcondition states the *property*, not the steps |
| Asserting against external systems mid-RPC | Network failure ≠ invariant violation; handle as error |
| Catching panics from contracts to "keep serving" | Don't. An invariant violation means state is corrupt — let it crash, restart cleanly |

## Cross-References

- `references/testing.md` — table-driven tests, build tags
- `references/fuzz-testing.md` — input-driven discovery (complementary to property tests)
- `references/resilience.md` — panic recovery boundaries (only at goroutine roots, never around contracts)
- security-audit-skill `references/authentication-patterns.md` — authorization invariants
