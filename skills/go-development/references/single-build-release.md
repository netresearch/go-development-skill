# Single-Build Release Pipeline for Go Apps

Cross-compile every target once, publish the binaries as GitHub Release assets, then re-use those same binaries to assemble the container image. One `go build` per platform serves both release-page downloads AND the image push — no second compile in a Dockerfile, no drift between the tarball and the image.

This is the fleet convention for every go-app repo (ofelia, raybeam, ldap-manager, ldap-selfservice-password-changer). The template for it lives in [`netresearch/.github/templates/go-app`](https://github.com/netresearch/.github/tree/main/templates/go-app) and consumers sync from it; this doc explains the moving parts so you can debug a specific repo or introduce a new one.

## Quick index

| Piece | Where |
|---|---|
| Matrix cross-compile + release upload | [binaries job](#binaries-job) |
| Assemble image from matrix output | [container job](#container-job) |
| Binary-selector Dockerfile | [Dockerfile](#dockerfile) |
| Version metadata convention | [ldflag convention](#ldflag-convention) |
| Package entrypoint detection | [main-package: auto](#main-package-auto) |
| Reliable build timestamp | [auto-build-timestamp](#auto-build-timestamp) |

## Why (in one sentence)

If you publish binaries AND images, the naive setup compiles Go twice per platform per release — once in a matrix job, again inside the Dockerfile. That's wasted CI time, two slightly-different artifacts for the same tag, and a second place for ldflags/build-tags to drift.

## Pipeline shape

```
push tag v*
  └── create-release.yml      → creates the release shell + outputs tag/sha
       └── binaries matrix    → build-go-attest.yml × 8 targets
       │                        (linux-{386,amd64,arm64,armv6,armv7},
       │                         darwin-{amd64,arm64}, windows-amd64)
       │                        uploads every binary as a release asset
       └── container job      → build-container.yml (5 linux platforms)
            │                    with pre-build-command that runs
            │                    `gh release download --pattern <name>-linux-*`
            │                    to populate bin/ in the build context
            └── finalize      → checksums + cosign + verification notes
```

Binaries for `linux/386` etc. land in `bin/<name>-linux-386`. The Dockerfile's binary-selector stage picks the right one per `TARGETARCH`/`TARGETVARIANT`.

## binaries job

Calls `netresearch/.github/.github/workflows/build-go-attest.yml@main` from a matrix. Key inputs:

```yaml
strategy:
  fail-fast: false
  matrix:
    include:
      - { target: linux-386,     goos: linux,   goarch: "386" }
      - { target: linux-amd64,   goos: linux,   goarch: amd64 }
      - { target: linux-arm64,   goos: linux,   goarch: arm64 }
      - { target: linux-armv6,   goos: linux,   goarch: arm,   goarm: "6" }
      - { target: linux-armv7,   goos: linux,   goarch: arm,   goarm: "7" }
      - { target: darwin-amd64,  goos: darwin,  goarch: amd64 }
      - { target: darwin-arm64,  goos: darwin,  goarch: arm64 }
      - { target: windows-amd64, goos: windows, goarch: amd64 }
uses: netresearch/.github/.github/workflows/build-go-attest.yml@main
with:
  binary-name: ${{ github.event.repository.name }}-${{ matrix.target }}
  main-package: auto
  goos: ${{ matrix.goos }}
  goarch: ${{ matrix.goarch }}
  goarm: ${{ matrix.goarm || '' }}
  ldflags: >-
    -s -w
    -X main.version=${{ needs.create-release.outputs.tag }}
    -X main.build=${{ needs.create-release.outputs.sha }}
  ref: ${{ needs.create-release.outputs.tag }}
  release-tag: ${{ needs.create-release.outputs.tag }}
  sbom: true
  setup-bun: true
  pre-build-command: |
    if [ -f package.json ]; then
      bun install --frozen-lockfile
      bun run build:assets
    fi
  auto-build-timestamp: true
```

Every matrix entry produces one binary file and uploads it to the release. `sbom: true` adds a Syft SBOM alongside each binary.

## container job

Depends on `binaries` so the release has the assets ready:

```yaml
container:
  needs: [create-release, binaries]
  uses: netresearch/.github/.github/workflows/build-container.yml@main
  permissions:
    contents: read
    packages: write
    security-events: write   # required for trivy SARIF upload
    id-token: write
    attestations: write
  with:
    image-name: ${{ github.event.repository.name }}
    ref: ${{ needs.create-release.outputs.tag }}
    platforms: "linux/386,linux/amd64,linux/arm/v6,linux/arm/v7,linux/arm64"
    sign: true
    attest: true
    pre-build-command: |
      set -euo pipefail
      mkdir -p bin
      for suffix in linux-386 linux-amd64 linux-arm64 linux-armv6 linux-armv7; do
        gh release download "${{ needs.create-release.outputs.tag }}" \
          --pattern "${{ github.event.repository.name }}-${suffix}" --dir bin
        chmod +x "bin/${{ github.event.repository.name }}-${suffix}"
      done
```

The `pre-build-command` runs inside `build-container.yml` after checkout and before `docker buildx build`. It pulls the binaries the matrix just published and drops them into `bin/` where the Dockerfile expects them. `GH_TOKEN` is pre-populated by the reusable workflow.

**5 platforms by default.** If a platform is incompatible (e.g. Fiber v3 on `linux/arm` overflows int on 32-bit), narrow the matrix AND the `platforms:` string in the caller and record the reason in the repo's `.github/template.yaml` `intentional-drift:` list.

## Dockerfile

The binary-selector pattern: one stage copies all pre-built Linux binaries in, picks the right one by `TARGETARCH`/`TARGETVARIANT`, then a minimal runtime stage copies only the selected binary.

```dockerfile
# Binary-selector stage — picks the pre-built binary for the target
# platform. The release binaries matrix produces bin/<name>-linux-*;
# the container job's pre-build-command downloads them here before
# `docker buildx build`.
FROM alpine:3.23 AS binary-selector

ARG TARGETARCH
ARG TARGETVARIANT

COPY bin/<name>-linux-* /tmp/

RUN set -eux; \
    case "${TARGETARCH}" in \
        arm)              BINARY="<name>-linux-arm${TARGETVARIANT}" ;; \
        386|amd64|arm64)  BINARY="<name>-linux-${TARGETARCH}" ;; \
        *) echo "Unsupported: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    cp "/tmp/${BINARY}" /usr/bin/<name>; \
    chmod +x /usr/bin/<name>

# Runtime stage — pick the minimal base that fits your runtime needs.
# `scratch` / `distroless/static:nonroot` / `alpine:3.23` are common.
FROM alpine:3.23
COPY --from=binary-selector /usr/bin/<name> /usr/bin/<name>
ENTRYPOINT ["/usr/bin/<name>"]
```

**Notes:**

- `TARGETARCH` is `386|amd64|arm64|arm` on buildx's standard platforms; `TARGETVARIANT` is `v6|v7` only when `TARGETARCH=arm`.
- `FROM scratch` works when the Go binary is fully static. Use `distroless/static-debian12:nonroot` for a cleaner nonroot + CA bundle combo. Use `alpine` only when you need a shell for ops.
- **Local `docker build` requires `bin/` to be populated first.** This is by design — the Dockerfile is a staging layer, not a compiler. Document this in the repo's README so contributors know to run `go build -o bin/<name>-linux-amd64` before `docker buildx build .`.

## ldflag convention

Every go-app main package declares the same three string variables:

```go
package main

// Populated by release.yml's ldflags + build-go-attest's
// auto-build-timestamp step.
var (
    version   = ""
    build     = ""
    buildTime = ""
)
```

The template ldflags are fixed across the fleet:

```
-X main.version=<release-tag>
-X main.build=<commit-sha>
-X main.buildTime=<ISO-8601 commit timestamp>  # via auto-build-timestamp
```

Consumers decide what to do with the values. Three live patterns:

### Pattern 1: consume directly (ofelia)

main package just uses the vars:

```go
slog.Info("starting server",
  "version", version,
  "build", build,
  "build_time", buildTime,  // slog key in snake_case, not camelCase
)
```

### Pattern 2: forward into `internal/version` (ldap-manager)

main package declares matching vars then forwards at init() time:

```go
import internalversion "github.com/<org>/<repo>/internal/version"

var (
    version, build, buildTime = "", "", ""
)

// forwardBuildMetadata is extracted so it's unit-testable (can be
// called with test inputs and then the test asserts on
// internalversion.* under a sync.Mutex snapshot/restore).
func forwardBuildMetadata(v, b, t string) {
    if v != "" { internalversion.Version = v }
    if b != "" { internalversion.CommitHash = b }
    if t != "" { internalversion.BuildTimestamp = t }
}

func init() {
    forwardBuildMetadata(version, build, buildTime)
}
```

Empty-string check preserves local-dev defaults ("dev", "n/a") when not injected.

### Pattern 3: forward into a package that already computed `vcs.revision` (raybeam)

The internal/build package had a VCS-derived fallback. Keep it; just layer main.* on top in init():

```go
// internal/build/build.go — fallback works for non-ldflag builds.
var vcsRevision = func() string {
    if info, ok := debug.ReadBuildInfo(); ok {
        for _, s := range info.Settings {
            if s.Key == "vcs.revision" { return s.Value }
        }
    }
    return ""
}()
var Version    = func() string { if vcsRevision != "" { return vcsRevision }; return "unknown" }()
var CommitHash = vcsRevision

// main.go — alias the internal package to avoid shadowing 'build'.
import buildpkg "github.com/<org>/<repo>/internal/build"

var (version, build, buildTime = "", "", "")

func init() {
    if version != "" { buildpkg.Version = version }
    if build   != "" { buildpkg.CommitHash = build }
    _ = buildTime  // reserved receiver, not surfaced yet
}
```

### Gotcha: package init order catches you if you're using cobra

If `cmd.rootCmd` is declared with `Version: build.Version`, cobra captures the VALUE at package-init time. `cmd` is imported by `main`, so Go initializes `cmd` first — BEFORE main's init() runs and updates `build.Version`. Cobra's --version then reports the pre-forward value.

**Fix:** defer the assignment to `Execute()`, which runs after all inits:

```go
var rootCmd = &cobra.Command{ Use: "raybeam" /* no Version here */ }

func Execute() {
    rootCmd.Version = formatVersion(build.Version, build.CommitHash)
    rootCmd.Execute()
}
```

### About `-X main.X` for undeclared vars

Go 1.21+ linkers **silently ignore** `-X` targets for vars that don't exist in the linked package — the build succeeds and the flag is a no-op. Older toolchains can reject with "symbol not found". The template ships all three of `main.version`, `main.build`, `main.buildTime` unconditionally; consumers MUST declare matching vars so:

1. The ldflag actually lands (modern Go).
2. Older-toolchain edge cases don't break the build (belt-and-braces).

## main-package: auto

`build-go-attest.yml` accepts `main-package: auto`, which resolves after checkout by scanning for a `package main` declaration:

1. Any non-test `./*.go` declares `package main` → use `.` (handles `ofelia.go`, `cmd.go`, `main.go`).
2. Else `./cmd/<repo-name>/*.go` declares `package main` → use `./cmd/<repo-name>` (handles ldap-manager's layout).
3. Else fail hard.

Repo name comes from `${GITHUB_REPOSITORY##*/}` (always populated), not `github.event.repository.name` (empty on some triggers).

This is why the release.yml template stays byte-identical across consumers regardless of whether they put main at root or under `cmd/`.

## auto-build-timestamp

`build-go-attest.yml` accepts `auto-build-timestamp: true`, which resolves the HEAD commit timestamp from git after checkout (not from `github.event.head_commit.timestamp`, which is empty on `workflow_dispatch` backfills):

```bash
# Inside build-go-attest.yml, after checkout:
if ! BUILD_TS=$(git show -s --format=%cI HEAD); then
  echo "::error::git show failed. Check actions/checkout."
  exit 1
fi
if [[ -z "$BUILD_TS" ]]; then
  echo "::error::git show returned empty."
  exit 1
fi
LDFLAGS="${LDFLAGS} -X main.buildTime=${BUILD_TS}"
```

**Do not** pipe stderr into `BUILD_TS` via `2>&1` — a harmless warning (e.g., CRLF normalization) would end up inside the ldflag value. See [workflow-bash-patterns.md](https://github.com/netresearch/github-project-skill/blob/main/skills/github-project/references/workflow-bash-patterns.md) in the github-project skill for details.

Works for both tag push and workflow_dispatch "rebuild tag" backfills, so `main.buildTime` is never empty when the feature is opted in.

## Related

- [reusable-workflows.md](./reusable-workflows.md) — how caller/reusable permission propagation works
- [docker.md](./docker.md) — Docker client patterns in Go code (not Dockerfile)
- github-project-skill [workflow-bash-patterns.md](https://github.com/netresearch/github-project-skill/blob/main/skills/github-project/references/workflow-bash-patterns.md) — bash inside `run:` gotchas
