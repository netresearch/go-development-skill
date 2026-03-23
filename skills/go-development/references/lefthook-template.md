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
      run: go test -short -timeout=60s ./...
```

Customize per project: add security scanning (gosec), mutation testing, etc.
