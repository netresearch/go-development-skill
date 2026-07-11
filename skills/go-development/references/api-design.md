# Go API Design Patterns

Functional options, builders, bitmask flags, and interface-segregation are
standard Go idioms with no Netresearch-specific variant — see
`references/cron-scheduling.md` § Custom Parser Construction (Bitmask
Options) for the org's one concrete instance (go-cron's `ParseOption`).

## Enum & Status Type Safety

Defensive handling for enum / status types so invalid values cannot be silently mishandled:

- Add a `Valid()` method that returns `false` for unknown values.
- Always include a `default` case in `switch` statements over the type.
- Write tests for unknown/zero values, not just the known ones.

```go
type Policy int

const (
    PolicyUnknown Policy = iota // zero value — explicitly invalid, so an
    PolicyRetry                 // uninitialized Policy is rejected by Valid()
    PolicySkip
    PolicyFail
)

// Valid reports whether p is a known policy. Values from deserialized data,
// API input, or a future enum addition that isn't handled here return false.
func (p Policy) Valid() bool {
    switch p {
    case PolicyRetry, PolicySkip, PolicyFail:
        return true
    default:
        return false
    }
}

func (p Policy) String() string {
    switch p {
    case PolicyUnknown:
        return "unknown"
    case PolicyRetry:
        return "retry"
    case PolicySkip:
        return "skip"
    case PolicyFail:
        return "fail"
    default:
        return fmt.Sprintf("Policy(%d)", int(p)) // never panic on unknown
    }
}
```

Why: the zero value of an int-backed enum is always a valid `int` but may be a
meaningless policy. A `Valid()` guard at trust boundaries (config load, API
input, DB read) turns a silent wrong-branch bug into an explicitly rejected value.

```go
func TestPolicy_Valid_RejectsUnknown(t *testing.T) {
    if Policy(0).Valid() { // the zero value must be rejected
        t.Error("zero-value Policy(0) should be invalid")
    }
    if Policy(99).Valid() {
        t.Error("Policy(99) should be invalid")
    }
}
```
