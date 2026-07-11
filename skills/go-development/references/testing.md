# Go Testing Patterns

## Build Tags for Test Isolation

Three-tier convention: unit tests are untagged and run by default; integration
and e2e tests opt in via `//go:build`. The tag must be the first line of the
file, followed by a blank line before the package clause.

```go
// File: job_test.go — unit tests, no tag, run by default
package core
```

```go
// File: docker_integration_test.go — require real external deps (Docker, see references/docker.md)
//go:build integration

package core
```

```go
// File: workflow_e2e_test.go — complete system
//go:build e2e

package e2e
```

```bash
go test ./...                          # unit only (CI default)
go test -tags=integration ./...        # + integration
go test -tags="integration e2e" ./...  # full suite
```

## Time Control

Testing time-dependent code (schedulers, caches, rate limiters) with real
timers is slow and flaky. Don't hand-roll a `Clock`/`FakeClock` abstraction —
go-cron ships one; see `references/cron-scheduling.md` § Testing with
FakeClock.

## Resource Isolation: One Instance Per Test

Give each test its own instance of any **stateful** fixture (scheduler, server,
store, temp dir). Sharing a mutable instance across tests causes order-dependent
pollution and flaky failures that often only reproduce under `-shuffle=on` or in CI.

```go
// Bad — shared, stateful scheduler: one test's jobs leak into the next
var sharedScheduler *Scheduler // package-level

// Good — each test gets a fresh instance and cleans it up
func TestScheduler_AddJob(t *testing.T) {
    s := NewScheduler(context.Background())
    t.Cleanup(s.Stop)
    // ... assert against this isolated scheduler
}
```

Exception: a **read-only** fixture that no test mutates may be shared for
speed. The rule targets *mutable* state — if a test can change it, give each
test its own.

## Race Detection

```bash
# Run tests with race detector
go test -race ./...

# Build binary with race detection
go build -race ./cmd/app

# Run specific package
go test -race -v ./core/...
```

### Common Race Patterns and Fixes

**1. Unsynchronized map access:**

```go
// BAD: Race condition
type Cache struct {
    data map[string]string
}

func (c *Cache) Set(k, v string) { c.data[k] = v } // Race!
func (c *Cache) Get(k string) string { return c.data[k] } // Race!

// GOOD: Protected with mutex
type Cache struct {
    mu   sync.RWMutex
    data map[string]string
}

func (c *Cache) Set(k, v string) {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.data[k] = v
}

func (c *Cache) Get(k string) string {
    c.mu.RLock()
    defer c.mu.RUnlock()
    return c.data[k]
}
```

**2. Goroutine capturing loop variable:**

> **Note:** Go 1.22+ fixed loop variable capture. The `i := i` shadow is no longer needed.
> The examples below show the modern style.

```go
// Modern Go (1.22+): safe without shadow
for i := range 10 {
    go func() {
        fmt.Println(i) // Safe: each iteration gets its own copy
    }()
}
}
```

**3. Check-then-act pattern:**

```go
// BAD: Race between check and update
if cache.Get(key) == nil {
    cache.Set(key, compute()) // Another goroutine might have set it!
}

// GOOD: Atomic operation
value := cache.GetOrSet(key, func() string {
    return compute()
})
```

**4. RLock vs Lock - Know When to Upgrade:**

```go
// BAD: RLock used when writing to a field
func (c *Cache) Get(key string) ([]byte, bool) {
    c.mu.RLock()
    defer c.mu.RUnlock()

    entry, ok := c.entries[key]
    if ok {
        entry.accessedAt = time.Now()  // RACE! Writing under RLock
    }
    return entry.data, ok
}

// GOOD: Use Lock when any write occurs
func (c *Cache) Get(key string) ([]byte, bool) {
    c.mu.Lock()  // Full lock needed for accessedAt update
    defer c.mu.Unlock()

    entry, ok := c.entries[key]
    if ok {
        entry.accessedAt = time.Now()  // Safe
    }
    return entry.data, ok
}
```

**Rule**: RLock is ONLY safe when the entire operation is read-only. Any write (including updating timestamps, counters, or "metadata") requires a full Lock.

## Common Gotchas

### Integer to String Conversion

A common trap in Go: `string(rune(i))` does NOT convert an integer to its string representation:

```go
// BAD - Produces unicode codepoint, not numeric string!
for i := range 10 {
    key := "key" + string(rune(i))  // key + "\x00", "\x01", etc.
}

// GOOD - Correct integer to string conversion
for i := range 10 {
    key := "key" + strconv.Itoa(i)  // "key0", "key1", etc.
}

// Also acceptable
key := fmt.Sprintf("key%d", i)
```

**Why this happens**: `string(rune(i))` interprets `i` as a Unicode code point. `string(rune(65))` produces `"A"`, not `"65"`.

### Test Assertion Precision

Choose the right assertion for nil checks:

```go
// BAD - assert.Empty works but is less precise
assert.Empty(t, err)  // Passes for nil, "", 0, empty slices...

// GOOD - assert.Nil is explicit about intent
assert.Nil(t, err)    // Only passes for nil

// For error checking, even better:
assert.NoError(t, err)
require.NoError(t, err)  // Fails test immediately
```

### Unused Test Parameters

Always name `*testing.T` parameters to enable helper functions:

```go
// BAD - Cannot use require.NotPanics or t.Helper()
func TestSomething(_ *testing.T) {
    // ...
}

// GOOD - Full access to testing helpers
func TestSomething(t *testing.T) {
    require.NotPanics(t, func() {
        // test code
    })
}
```

### Fuzz Target Naming

Fuzz targets must match the `Fuzz*` pattern exactly:

```go
// BAD - Target name doesn't match function
//go:build ignore

func FuzzParser(f *testing.F) {
    f.Fuzz(func(t *testing.T, data []byte) {
        // ...
    })
}

// GOOD - Target exists and matches name in fuzz command
// go test -fuzz=FuzzParser
func FuzzParser(f *testing.F) {
    f.Fuzz(func(t *testing.T, data []byte) {
        // ...
    })
}
```

### Always Check app.Test() Errors

When testing Fiber/Echo handlers, always check the error:

```go
// BAD - Ignores potential test setup errors
resp, _ := app.Test(req)

// GOOD - Fails test if request setup fails
resp, err := app.Test(req)
require.NoError(t, err)
defer resp.Body.Close()
```

### Fiber v2 Testing Patterns

#### Full App Setup with Cleanup

Use `t.Cleanup()` to ensure goroutine teardown and prevent leaks:

```go
func setupFullTestApp(t *testing.T) *App {
    t.Helper()

    app := NewApp(testConfig)
    app.Setup()

    t.Cleanup(func() {
        _ = app.fiber.Shutdown()
    })

    return app
}
```

#### Auth Session Cookie Generation

For handlers requiring authentication, create session cookies with a separate mini Fiber app:

```go
func createAuthCookie(t *testing.T, sessionStore *session.Store) *http.Cookie {
    t.Helper()

    miniApp := fiber.New()
    var cookie *http.Cookie

    miniApp.Get("/set-session", func(c *fiber.Ctx) error {
        sess, err := sessionStore.Get(c)
        if err != nil {
            return err
        }
        sess.Set("username", "testuser")
        sess.Set("dn", "cn=testuser,dc=example,dc=com")

        return sess.Save()
    })

    req := httptest.NewRequest(http.MethodGet, "/set-session", nil)
    resp, err := miniApp.Test(req)
    require.NoError(t, err)
    defer resp.Body.Close()

    for _, c := range resp.Cookies() {
        if c.Name == "session_id" {
            cookie = c
            break
        }
    }
    require.NotNil(t, cookie)

    return cookie
}
```

#### Using Auth Cookies in Tests

```go
func TestProtectedHandler(t *testing.T) {
    app := setupFullTestApp(t)
    cookie := createAuthCookie(t, app.sessionStore)

    req := httptest.NewRequest(http.MethodGet, "/api/users", nil)
    req.AddCookie(cookie)

    resp, err := app.fiber.Test(req)
    require.NoError(t, err)
    defer resp.Body.Close()

    assert.Equal(t, http.StatusOK, resp.StatusCode)
}
```

### Prefer assert.ErrorAs Over errors.As in Tests

Use `assert.ErrorAs` from testify for better failure messages:

```go
// BAD - Manual errors.As with less informative failures
var target *MyError
if !errors.As(err, &target) {
    t.Errorf("expected *MyError, got %T", err)
}

// GOOD - testify provides clear diff output on failure
var target *MyError
assert.ErrorAs(t, err, &target)
```

### Always Use t.Helper() in Test Helpers

Mark all test helper functions with `t.Helper()` so failure messages
point to the calling test, not the helper:

```go
func assertUserExists(t *testing.T, store UserStore, username string) {
    t.Helper() // Failure will report caller's line, not this function

    user, err := store.Get(username)
    require.NoError(t, err)
    assert.NotNil(t, user)
}
```

## Related

- `references/fuzz-testing.md` — fuzz testing patterns, security-focused seeds
- `references/mutation-testing.md` — mutation testing, test-quality measurement
- `references/makefile.md` — standard Makefile test targets
- `references/cron-scheduling.md` — go-cron FakeClock testing patterns
