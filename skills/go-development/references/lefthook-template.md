# Lefthook Template for Go Projects

Install: `go install github.com/evilmartians/lefthook@latest && lefthook install`
Or add to Makefile: `make setup`

## lefthook.yml

```yaml
# Go project git hooks - powered by lefthook
# https://github.com/evilmartians/lefthook

pre-commit:
  parallel: true
  commands:
    go-mod-tidy:
      run: go mod tidy -diff 2>/dev/null || (echo "Run: go mod tidy" && exit 1)
    go-vet:
      glob: "*.go"
      run: go vet ./...
    gofmt:
      glob: "*.go"
      run: |
        unformatted=$(gofmt -l $(git ls-files '*.go'))
        [ -z "$unformatted" ] || (echo "Unformatted: $unformatted" && exit 1)

commit-msg:
  commands:
    conventional-commits:
      run: |
        msg=$(cat {1})
        echo "$msg" | grep -qE "^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert)(\(.+\))?: .+" || \
          echo "Warning: not conventional commits format"
    signoff:
      run: |
        grep -qE "^Signed-off-by: .+ <.+>" {1} || \
          (echo "Missing --signoff" && exit 1)

pre-push:
  parallel: true
  commands:
    lint:
      glob: "*.go"
      run: golangci-lint run --timeout=3m
    test:
      # -short only keeps this fast if slow/integration tests skip via
      # `if testing.Short() { t.Skip(...) }`. Size -timeout to your slowest
      # *unguarded* package, or the push fails on every push.
      run: go test -short -timeout=60s ./...
```

Customize per project: add security scanning (gosec), mutation testing, etc.

**Pre-push timeout pitfall.** The `-short -timeout=60s` smoke-test stays fast
*only if* slow/integration tests honour `-short` with a
`if testing.Short() { t.Skip(...) }` guard. A package that ignores `-short`
(real-Docker integration tests are the classic case) runs in full, blows the
fixed timeout, and fails the hook on **every** push — which reads like a real
regression but is not. Diagnose before reaching for `--no-verify`:

```bash
go list -deps ./slow/pkg | grep your/changed/pkg   # import-independent of your change?
go test -short -timeout=300s ./slow/pkg             # what does it actually take?
```

If the slow package is unrelated to your diff and pre-existing, `git push
--no-verify` is justified — then fix the root cause separately by guarding those
tests with `testing.Short()` (preferred, keeps the smoke-test fast) or raising
`-timeout` to cover the slowest unguarded package.
