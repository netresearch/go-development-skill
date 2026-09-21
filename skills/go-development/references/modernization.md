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

**A plain `go fix ./...` does not see a file behind a build tag, and reports
nothing about it.** `//go:build integration` hides a file from the run, so a
repository whose whole test tier sits behind tags comes back clean while every
one of those files is untouched. Measured 2026-09-21 on two libraries: `go fix
./...` reported **0** findings in each, and `-tags=integration` then produced 38
and 24. Run it once per tag set the repository uses and take the union — a file
behind `!integration` is only visible to the run *without* the tag, so neither
run alone is enough:

```bash
go fix ./...                          # files with no tag, and !tag files
go fix -tags=integration,e2e ./...    # files behind those tags
```

The same applies to the reporting form. To see which analyzer produced each
finding rather than a diff, run the fix tool through `go vet`:

```bash
go vet -vettool=$(go tool -n fix) -json -tags=integration ./...
```

Two more things stop `go fix` from seeing a package at all, and both look like
"nothing to modernize": a failing `//go:embed` pattern (build the frontend
assets first) and generated code that is not committed (run `templ generate`,
`mockgen` and friends first). `go fix` exits non-zero and prints the load error,
so check the exit status rather than the empty diff.

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
  { echo "module langprobe"; echo; echo "go $v"; } > go.mod
  out=$(go build ./... 2>&1); rc=$?
  if [ $rc -eq 0 ]; then printf 'go %s: compiles\n' "$v"
  else printf 'go %s: %s\n' "$v" "$out"; fi
done
```

Capture the status; do not pipe it. `go build ./... | tail -1` reports `tail`'s
exit status, so a failed build looks like a success and the branch printing the
success marker never runs — which is how a plausible transcript ends up in a
document without ever having been produced by the script above it.

```
go 1.26.0: # langprobe
./p.go:9:15: use of promoted field Inner.A in struct literal of type Outer requires go1.27 or later (-lang was set to go1.26; check go.mod)
go 1.27.0: compiles
```

The diagnostic names the version, which turns "this is a 1.27 feature" from a
claim into evidence — worth putting in the pull request, because a review bot
whose model predates the toolchain will report exactly these lines as a compile
error and propose undoing them.

**Go 1.27: promoted fields in composite literals.** `Outer{A: "x"}` for a field
promoted from an embedded struct is the rewrite most visible after raising the
directive to 1.27. The modernizer is `embedlit`; on the same tree with `go
1.26.0` in `go.mod` it produces no diff at all, which is the gating in action.
An embedded field whose promoted
name equals its own type name cannot be flattened — `Unicode: Unicode{Unicode:
"yes"}` stays wrapped, because `Unicode:` in that literal is the embedded field,
not the promoted string. A mixed result is correct, not an inconsistency.

Confirm a flattened literal still builds the same value before trusting it: a
`reflect.DeepEqual` comparison against the wrapped form costs one throwaway test
and rules out the promoted name resolving to a different field. Give that test a
control case comparing deliberately different values — a comparison that cannot
fail proves nothing.

**`embedlit` reaches further than composite literals suggest.** It also changes
what reflection sees, because a field whose type it rewrites is walked
differently. Where a struct's identity is derived by reflection — a config hash,
a cache key, a change detector — compare that derived value before and after on
the same input rather than reasoning about it. On ofelia, `atomictypes` turned a
job's `running int32` into `atomic.Int32`, and the job hash walked that struct
field-by-field, recursing into any field of kind Struct *before* checking its
tag; the hash happened to stay byte-identical, but nothing in the diff said so.

### go fix Best Practices

1. **Run after upgrading Go** — `go fix` detects your `go.mod` version and only applies applicable modernizers
2. **Run it once per build-tag set** — see above; a plain run reports nothing about tagged files
3. **Review the diff** — Use `go fix -diff ./...` first to understand what changes will be made
4. **Run the repo's own formatter after, not plain `gofmt`** — `go fix` may leave behind unused imports, redundant variables, or gofumpt issues. The `embedlit` rewrite in particular produces literals gofumpt rejects, which plain `gofmt` accepts. Use `golangci-lint fmt` or whatever the repository's lint job checks.
5. **Commit separately** — Keep `go fix` changes in their own commit for clean history

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

Go 1.27's `go fix` ships an `errorsastype` analyzer that performs this rewrite,
so it is no longer purely manual — but it does not catch every shape. Run the
tool first, then grep for what it left:

```bash
go fix ./...; echo "untagged: $?"
go fix -tags=integration,e2e ./...; echo "tagged: $?"
grep -rn 'errors\.As(' --include='*.go' .
```

The two runs are separate statements on purpose. `go fix` exits non-zero on a
package-load error, so chaining them with `&&` lets one failing run silently skip
the other and leaves the union incomplete — which is the very gap this section
exists to close. Read both exit statuses.

Measured 2026-09-21 across seven repositories: the analyzer offered one rewrite
and the grep found seven further call sites it had not touched, all of them in
`if !errors.As(...)` guards and `return errors.As(...)` bodies. Treat a clean
`go fix` as a partial pass and finish the remainder by hand.

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

## testing.B.Loop (Go 1.24) — and the three benchmarks that must keep b.N

`b.Loop` manages the benchmark timer itself, keeps the loop body's values alive
so the compiler cannot delete the measured work, and runs the benchmark function
once per measurement instead of re-running it with a growing `N`. `go fix` does
**not** perform this rewrite, so it survives a clean modernizer pass:

```go
// Before
b.ResetTimer()
for i := 0; i < b.N; i++ {
    doWork()
}

// After — the ResetTimer is now redundant, b.Loop resets on its first call
for b.Loop() {
    doWork()
}
```

Where the body reads the index, declare the counter outside:

```go
i := 0
for b.Loop() {
    doWork(i % 10)
    i++
}
```

**Three shapes must keep `b.N`.** Converting them is not a style regression, it
is a defect — the first two were found by running the benchmarks, not by reading
the code:

1. **The timer is stopped when `b.Loop()` is called.** b.Loop requires a running
   timer at each call and aborts otherwise with
   `benchmark.go:417: B.Loop called with timer stopped`. Manual timer control is
   *not* itself forbidden: `b.StopTimer()` / `b.StartTimer()` **balanced inside**
   the body, so that the timer runs again before the next `b.Loop()`, is fine and
   measures 185 ns/op. What fails is the older shape that stops the timer before
   the loop and again as the body's last statement:

   ```go
   b.StopTimer()                 // ← aborts: timer stopped at the first b.Loop()
   for b.Loop() {
       setup()
       b.StartTimer()
       work()
       b.StopTimer()             // ← and stopped again at every later one
   }
   ```

2. **More than one `b.N` loop in one benchmark scope.** There is only one loop
   that measures; another sizes its setup by `b.N` (pre-populate exactly `b.N`
   cache entries, then delete one per iteration). b.Loop cannot express that: its
   iteration count is decided as it runs, and `b.N` is only meaningful *after* it
   returns false.
3. **A body with `continue` or `goto`,** where a trailing `i++` would be skipped.

Verify a conversion by executing every benchmark once, not by the unit suite — a
broken conversion shows up as a benchmark that no longer runs:

```bash
go test -run='^$' -bench=. -benchtime=1x ./...
go test -run='^$' -bench=. -benchtime=1x -tags=integration,e2e ./...
```

**`for i := 0; b.Loop(); i++` also keeps the body alive**, so it is a legitimate
way to carry an index without a separate counter. The documentation's wording
("the loop condition must be written exactly as `b.Loop()`") reads as if only
`for b.Loop() { … }` qualified, and three benchmarks built to separate the two
spellings could not tell them apart. The compiler settles it:
`cmd/compile/internal/bloop.isTestingBLoop` accepts any `ir.OFOR` whose `Cond` is
a call to `testing.(*B).Loop`, and inspects neither the loop's `Init` nor its
`Post`. A three-clause loop is an `OFOR`, so it gets the same
`runtime.KeepAlive` wrapping. Pick whichever of the two reads better; do not
pick on a belief about keep-alive.

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
| `errors.AsType[T]()` | 1.26 | Partly (`errorsastype`, Go 1.27; finish by hand) |
| `testing.B.Loop()` | 1.24 | No (manual) |
| `new(expr)` | 1.26 | Yes |
| `reflect.TypeFor[T]()` | 1.22 | Yes |
