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
