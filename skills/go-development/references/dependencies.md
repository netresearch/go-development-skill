# Dependency Upgrades

Upgrading Go dependencies has three traps: the obvious command does less than it
looks, majors are invisible to it, and "everything is updated" is almost never a
claim you can make honestly.

## `go get -u ./...` is not a full update

`go get -u ./...` upgrades only what is needed to **build the packages matched by
the pattern**. Modules elsewhere in the graph are untouched. `go get -u all`
covers the whole module graph.

```bash
go get -u ./...   # build path only
go get -u all     # whole module graph
go mod tidy
```

**Real case:** after `go get -u ./...` reported ~26 upgrades and the tree built
green, `go list -m -u all` still listed **44 modules with newer versions**,
including `terraform-json` 0.27.2 → 0.28.0 and `terraform-exec` 0.25.1 → 0.25.2 —
both in the build. Only `go get -u all` moved them. The claim "all dependencies
upgraded" was wrong until challenged.

Always confirm with the tool, not the transcript:

```bash
go list -m -u all | grep '\['   # any module with an available update prints [newer]
```

## `-u` never crosses a major version

Major versions are distinct module paths (`/v2`, `/v3`), so `-u` cannot reach
them — a v2 release is invisible to a v1 module. Check explicitly before claiming
a dependency is current:

```bash
for m in $(go list -m -f '{{if not .Indirect}}{{.Path}}{{end}}' all); do
  if [[ "$m" =~ /v([0-9]+)$ ]]; then cur="${BASH_REMATCH[1]}"; base="${m%/v*}"; else cur=1; base="$m"; fi
  go list -m "$base/v$((cur + 1))@latest" >/dev/null 2>&1 && echo "MAJOR AVAILABLE: $m -> $base/v$((cur + 1))"
done
```

A major bump is an import rewrite, not a version bump — scope it as its own change.

## Scope the claim to what is actually in the build

After `go get -u all`, `go list -m -u all` will often *still* list modules with
newer versions. That is usually correct and not a gap: their versions are selected
by MVS from your dependencies' own requirements, and many are test-deps-of-deps
that never link into your binary. Forcing them means spurious `require` entries
for code you do not ship.

Separate "outdated" from "outdated **and in the build**" before reporting:

```bash
# outdated AND linked into the binary — the real list
comm -12 \
  <(go list -deps -f '{{with .Module}}{{.Path}}{{end}}' ./... | grep -v '^$' | sort -u) \
  <(go list -m -u all | grep '\[' | awk '{print $1}' | sort)
```

Empty output means every module you actually ship is current; the remainder is
graph noise. That is a defensible claim. "All dependencies are latest" usually is
not.

## Verify the final tree, not an intermediate one

`go get -u` raises the `go` directive when an upgraded dependency demands it
(observed: 1.24.0 → 1.25.8). If a workflow pins Go from `.go-version`, that file
and `go.mod` can silently disagree.

```bash
go build ./... && go vet ./...
go mod verify
go mod tidy && git diff --exit-code -- go.mod go.sum   # tidy drift == CI failure
```

A `depscheck`-style target runs `go mod tidy` then `git diff --exit-code` — it
fails on **uncommitted** go.mod/go.sum, so run it after committing, or its red is
your own working tree rather than real drift.

## Dependency changes need the test job to actually run

A CI `paths:` filter listing only source globs (`'**.go'`) does not match `go.mod`,
so **every dependency PR skips the test job** — including Dependabot's. Include the
manifest:

```yaml
paths:
  - '**.go'
  - 'go.mod'
  - 'go.sum'
  - '.go-version'
```

## Replacing an archived dependency: prove the swap, do not assume it

An archived module is a reason to move, but the replacement is a behaviour change
until measured. Two things to establish before the commit message claims a
drop-in.

**Enumerate every symbol and every struct tag you use**, not just the one call
you remember. A fork can keep a signature and change how it reads a tag. The
cheap evidence is a differential probe: a throwaway module importing both
libraries, feeding the same inputs through each, comparing results *and*
whether an error was returned. Copy the real structs with their real tags —
reconstructed fixtures test the reconstruction. Control-test the probe by
injecting one difference and checking it reports it; a probe that cannot fail
is not evidence.

**Read the advisory rather than a summary.** The advisory in this area may be
against the module you are migrating *to*: `go-viper/mapstructure/v2` carries
CVE-2025-11065 for `<= 2.3.0`, while the archived `mitchellh/mapstructure` has
no advisory at all. Take the package, the range and the first patched version
from `gh api /advisories?cve_id=<CVE>` or the OSV record.

Error *text* is part of the contract when it reaches a user. The same
mapstructure change stops quoting the offending value back in a decode error, so
any message a provider or CLI surfaces changes wording without changing
behaviour. Grep for tests asserting on it, and put it in the release notes.

"No advisory" is not "unaffected". The archived module leaks the same value into
the same message; it has no advisory because nobody is filing them for it. Read
an absent advisory as an absent maintainer.

## Moving to a standard-library replacement: check the acceptance set

Go 1.27 ships `uuid`, which makes `github.com/hashicorp/go-uuid` and friends
removable. The generation side is a clean swap; the parsing side is not.

`hashicorp/go-uuid`'s `ParseUUID` accepts exactly the canonical 36-character
hyphenated form. `uuid.Parse` also accepts the URN form
(`urn:uuid:...`), the unhyphenated 32-character form, and the brace-wrapped
form. Swapping it into a validator therefore *widens* what that validator
accepts, silently — and for a value that is echoed back canonicalised by the
system it addresses, a widened validator trades an error at validation time for
a diff that never settles.

Keep the old acceptance set explicitly:

```go
func parseGUID(s string) error {
	if len(s) != 36 {
		return fmt.Errorf("uuid string is wrong length")
	}
	_, err := uuid.Parse(s)
	return err
}
```

The length check is what makes it strict; the three wider spellings are 45, 32
and 38 bytes. Pin it with a table test that lists those three as rejected, and
confirm the test fails when the length check is removed — otherwise the guard is
asserting nothing.

Two more things the swap changes:

- **Rejection wording.** `go-uuid` returned one of four messages depending on
  which check failed — `uuid string is wrong length`, `uuid is improperly
  formatted` for a misplaced separator, a raw `encoding/hex` error, or `decoded
  hex is the wrong length`. The standard library returns `invalid uuid` for all
  of them. Anywhere that interpolates the parse error into a user-facing message
  now reads differently, and a test matching on one of the four stops matching.
- **The generated value's shape.** `go-uuid`'s `GenerateUUID` formatted sixteen
  random bytes *without* setting the version and variant bits, so it did not
  produce a v4 by construction — about one output in 64 was a valid v4 by
  chance, which is why "never" is the wrong word and a sampling check is the
  wrong test. `uuid.New()` sets both. If the value is stored, say so.

One thing that is *not* a hazard here, because it is easy to assume it is:
`uuid.UUID` is a `[16]byte`, but `String` has a **value** receiver, so a `%s`
verb reaches it for both a value and a pointer. There is no plain `%s` spelling
that prints raw bytes. Getting them requires deliberately leaving the type —
`u[:]`, `[16]byte(u)`, `%x` — which is not something a refactor does by accident.

Assert the rendering only where production code adds formatting of its own, such
as composing the value into a larger identifier. Assert it by calling that code,
never by rebuilding its expression in the test.

## The `go` directive is not only a floor — it selects runtime behaviour

`go.mod` carries two version lines and they do different jobs:

```
go 1.26            # language version AND compatibility baseline
toolchain go1.27.1 # which toolchain to fetch and build with
```

The `toolchain` line decides what compiles. The `go` line decides what the
result *behaves* like: Go compiles with that version's compatibility defaults
and bakes them into the binary. So a module built by go1.27.1 while declaring
`go 1.26` ships 1.26 semantics for everything 1.27 changed.

**Only the main module's directive counts** (or the workspace's `go.work`). A
dependency's `go` line does not reach the importing binary's defaults —
verified by building an app at `go 1.26` against a dependency at `go 1.24`,
then raising only the app: the dependency's version never showed up either way.

Read it back rather than reasoning about it:

```bash
go build -o /tmp/probe . && go version -m /tmp/probe | grep -E 'DefaultGODEBUG|^/'
# /tmp/probe: go1.27.1
#     build   DefaultGODEBUG=tracebacklabels=0,x509sslcertoverrideplatform=0

# Same answer without building, straight from the main package:
go list -f '{{.DefaultGODEBUG}}' .
# tracebacklabels=0,x509sslcertoverrideplatform=0
```

Both were measured on go1.27.1. `go version -m` reads the *binary*, `go list`
reads the *package* — neither reports the `go` directive itself, which is
`go mod edit -json | jq -r '.Go'` if that is what you want.

Those two settings are 1.27 behaviour changes, pinned back. Raise the main
module's `go` directive to 1.27 and the `DefaultGODEBUG` line disappears
entirely — same toolchain, same tree, only the directive differs. That
two-build diff is the way to show what a floor actually costs, and it takes
one minute.

One documented exception, from [go.dev/doc/godebug](https://go.dev/doc/godebug):
*"GODEBUGs introduced for security releases will have the new behavior apply to
all versions."* So a low floor pins back ordinary behaviour changes, not those.

### Deciding the floor

The floor is a promise to whoever compiles the module, so ask who that is
before keeping it low:

- **Library** — importers inherit it through MVS. Keep the floor low
  deliberately; raising it forces every consumer up. Check who they are:
  `https://pkg.go.dev/<module>?tab=importedby` says *"No known importers for
  this package!"* when there are none.
- **Application** — users consume binaries and images, not the module. If the
  Dockerfile packages a prebuilt binary rather than compiling, and CI resolves
  its toolchain from `go.mod` (`setup-go` with `go-version-file`), then the
  floor buys nothing and costs the pinned-back behaviour above.

A repository that inherited its floor from a sibling library without
inheriting the reason is the common case worth checking.

### Raising it

`go.mod` is not the only surface. Sweep **without an extension filter** — the
files that *enforce* the version are often dotfiles a `--include='*.md'` pattern
cannot match:

```bash
grep -rn '1\.26' . --exclude-dir=.git --exclude=CHANGELOG.md
# go.mod, docs/DEVELOPMENT.md, CONTRIBUTING.md … and .envrc's REQUIRED_VERSION
```

The README's `img.shields.io/github/go-mod/go-version` badge reads the `go`
directive, so it follows on its own — and reports the floor, not the toolchain,
which is why a repo building with 1.27 can advertise 1.26 and look wrong.
