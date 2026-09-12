# Go Modernization Patterns

## go fix — Automated Code Modernization

Go 1.26 ships a rewritten `go fix` with 22 built-in modernizers. Run it on any codebase to apply idiomatic Go patterns automatically.

### Running go fix

```bash
# Apply all applicable modernizers
go fix ./...

# Preview changes without applying (dry run)
go fix -diff ./...

# Apply specific modernizer only
go fix -fix=any ./...
```

### Modernizer Reference

| Modernizer | What it does | Example |
|------------|-------------|---------|
| `any` | `interface{}` → `any` | `func Foo(x interface{})` → `func Foo(x any)` |
| `rangeint` | C-style loops → range | `for i := 0; i < n; i++` → `for i := range n` |
| `slicescontains` | Manual contains loops → `slices.Contains()` | Loop+compare → `slices.Contains(s, v)` |
| `mapsloop` | Manual map copy → `maps.Copy()` | for+assign → `maps.Copy(dst, src)` |
| `minmax` | if/else capping → `min()`/`max()` builtins | if/else block → `min(a, b)` |
| `stringscutprefix` | `HasPrefix`+`TrimPrefix` → `CutPrefix` | Two calls → `strings.CutPrefix(s, p)` |
| `stringsseq` | `range strings.Split()` → `SplitSeq()` | Avoids allocating intermediate slice |
| `waitgroup` | `wg.Add(1)/go/defer wg.Done()` → `wg.Go()` | Three lines → `wg.Go(func() { ... })` |
| `testingcontext` | `context.WithCancel(context.Background())` → `t.Context()` | In tests only |
| `reflecttypefor` | `reflect.TypeOf((*T)(nil)).Elem()` → `reflect.TypeFor[T]()` | Cleaner generic form |
| `stringsbuilder` | `output += s` → `strings.Builder` | Better performance for string concatenation |

### Proving a construct needs the new language version

`go fix` only applies modernizers your `go.mod` allows, so after a directive
raise some rewrites are not style choices — they are constructs the previous
language version rejected. Do not assert that from the release notes. Build the
same file under both directives and let the compiler say so:

```bash
mkdir -p /tmp/langprobe && cd /tmp/langprobe
cat > p.go <<'EOF'
package p

type Inner struct{ A string }
type Outer struct {
	Inner
	B string
}

var _ = Outer{A: "x", B: "y"}
EOF
for v in 1.26.0 1.27.0; do
  printf 'module langprobe

go %s
' "$v" > go.mod
  printf "go %s: " "$v"; go build ./... 2>&1 | tail -1 || echo compiles
done
```

```
go 1.26.0: ./p.go:9:15: use of promoted field Inner.A in struct literal of type
           Outer requires go1.27 or later (-lang was set to go1.26; check go.mod)
go 1.27.0: compiles
```

The diagnostic names the version, which turns "this is a 1.27 feature" from a
claim into evidence — worth putting in the pull request, because a review bot
whose model predates the toolchain will report exactly these lines as a compile
error and propose undoing them.

**Go 1.27: promoted fields in composite literals.** `Outer{A: "x"}` for a field
promoted from an embedded struct is the rewrite most visible after raising the
directive to 1.27, and `go fix` produces it. An embedded field whose promoted
name equals its own type name cannot be flattened — `Unicode: Unicode{Unicode:
"yes"}` stays wrapped, because `Unicode:` in that literal is the embedded field,
not the promoted string. A mixed result is correct, not an inconsistency.

Confirm a flattened literal still builds the same value before trusting it: a
`reflect.DeepEqual` comparison against the wrapped form costs one throwaway test
and rules out the promoted name resolving to a different field.

### go fix Best Practices

1. **Run after upgrading Go** — `go fix` detects your `go.mod` version and only applies applicable modernizers
2. **Review the diff** — Use `go fix -diff ./...` first to understand what changes will be made
3. **Run linters after** — `go fix` may leave behind unused imports, redundant variables, or gofumpt issues
4. **Commit separately** — Keep `go fix` changes in their own commit for clean history

### Common Post-fix Cleanup

After `go fix`, watch for:

```go
// go fix may leave redundant loop variable copies (Go 1.22+)
for field := range t.Fields() {
    field := field  // ← delete this (copyloopvar lint)
    // ...
}

// go fix may inline helpers and leave them unused
//go:fix inline
func stringPtr(s string) *string {  // ← delete if unused
    return new(s)
}
```

## errors.AsType[T] (Go 1.26)

Go 1.26 adds `errors.AsType[T]` — a type-safe generic replacement for `errors.As` that eliminates pre-declared target variables.

### Before (errors.As)

```go
var flagErr *flags.Error
if errors.As(err, &flagErr) {
    if flagErr.Type == flags.ErrHelp {
        return
    }
}
```

### After (errors.AsType)

```go
if flagErr, ok := errors.AsType[*flags.Error](err); ok {
    if flagErr.Type == flags.ErrHelp {
        return
    }
}
```

### Common Conversion Patterns

**Positive check with value use:**
```go
// Before
var exitErr NonZeroExitError
if errors.As(err, &exitErr) {
    log.Printf("exit code: %d", exitErr.ExitCode)
}

// After
if exitErr, ok := errors.AsType[NonZeroExitError](err); ok {
    log.Printf("exit code: %d", exitErr.ExitCode)
}
```

**Negative check (guard clause):**
```go
// Before
var validationErrors validator.ValidationErrors
if !errors.As(err, &validationErrors) {
    return fmt.Errorf("unexpected error: %w", err)
}

// After
validationErrors, ok := errors.AsType[validator.ValidationErrors](err)
if !ok {
    return fmt.Errorf("unexpected error: %w", err)
}
```

**Bool-only check (discard value):**
```go
// Before
func IsNonZeroExitError(err error) bool {
    var exitErr NonZeroExitError
    return errors.As(err, &exitErr)
}

// After
func IsNonZeroExitError(err error) bool {
    _, ok := errors.AsType[NonZeroExitError](err)
    return ok
}
```

### Why errors.AsType is Better

| `errors.As` | `errors.AsType[T]` |
|---|---|
| Requires pre-declared target variable | No variable declaration needed |
| Type safety checked at runtime | Type checked at compile time |
| `errors.As(err, &target)` — pointer indirection | `errors.AsType[T](err)` — direct generic |
| Target variable leaks into outer scope | Scoped to `if` block with `:=` |

### Migration

`go fix` does NOT automatically convert `errors.As` → `errors.AsType`. This is a manual migration. Search for all occurrences:

```bash
grep -rn 'errors\.As(' --include='*.go' .
```

## sync.WaitGroup.Go (Go 1.25)

`sync.WaitGroup` gained a `Go` method that combines `Add(1)`, goroutine launch, and `defer Done()`:

```go
// Before
var wg sync.WaitGroup
for range 20 {
    wg.Add(1)
    go func() {
        defer wg.Done()
        doWork()
    }()
}
wg.Wait()

// After
var wg sync.WaitGroup
for range 20 {
    wg.Go(func() {
        doWork()
    })
}
wg.Wait()
```

`go fix` handles this conversion automatically via the `waitgroup` modernizer.

## new(expr) — Pointer to Value (Go 1.26)

Go 1.26 extends `new()` to accept expressions (not just types), returning a pointer to a copy:

```go
// Before — temporary variable needed
func stringPtr(s string) *string {
    return &s
}

// After — direct construction
p := new("hello")  // *string pointing to "hello"
n := new(42)       // *int pointing to 42
```

`go fix` can inline helper functions annotated with `//go:fix inline` that follow this pattern.

## for range n (Go 1.22)

Integer range loops replace C-style counting:

```go
// Before
for i := 0; i < 10; i++ {
    fmt.Println(i)
}

// After
for i := range 10 {
    fmt.Println(i)
}

// When index is unused
for range 10 {
    doSomething()
}
```

## Loop Variable Capture Fix (Go 1.22)

Go 1.22 fixed loop variable capture — the `tt := tt` shadow is no longer needed:

```go
// Before (Go < 1.22) — required to prevent capture bug
for _, tt := range tests {
    tt := tt  // ← was needed
    t.Run(tt.name, func(t *testing.T) {
        t.Parallel()
        // ...
    })
}

// After (Go 1.22+) — safe without shadow
for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) {
        t.Parallel()
        // ...
    })
}
```

The `copyloopvar` linter flags unnecessary copies.

## t.Context() (Go 1.24)

Tests can use `t.Context()` instead of manually creating background contexts:

```go
// Before
func TestSomething(t *testing.T) {
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()
    // use ctx...
}

// After
func TestSomething(t *testing.T) {
    ctx := t.Context()  // cancelled automatically when test ends
    // use ctx...
}
```

`go fix` handles this via the `testingcontext` modernizer.

## Version-Gated Features Summary

| Feature | Minimum Go | go fix? |
|---------|-----------|---------|
| `any` keyword | 1.18 | Yes |
| Generics | 1.18 | N/A |
| `for range n` | 1.22 | Yes |
| Loop variable fix | 1.22 | N/A |
| `min()`/`max()` builtins | 1.21 | Yes |
| `slices.Contains()` | 1.21 | Yes |
| `maps.Copy()` | 1.21 | Yes |
| `strings.CutPrefix()` | 1.20 | Yes |
| `t.Context()` | 1.24 | Yes |
| `sync.WaitGroup.Go()` | 1.25 | Yes |
| `strings.SplitSeq()` | 1.25 | Yes |
| `errors.AsType[T]()` | 1.26 | No (manual) |
| `new(expr)` | 1.26 | Yes |
| `reflect.TypeFor[T]()` | 1.22 | Yes |
