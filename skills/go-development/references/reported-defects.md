# Fixing a Reported Defect

A report names one defect. The change a reviewer can accept is the fix, the test
that guards it, and nothing else.

## A guard that runs everywhere

Write the regression test at unit level, against a fake or an injected
dependency, so the default `go test ./...` runs it. A test that exists only
behind `-tags=integration`, or that calls `t.Skip` under `testing.Short()`
because it needs a container, guards nothing in the run most people make.

Pin what the fix changes: the error returned (`errors.Is`), the calls made to
the dependency, the branch taken. Do not measure wall-clock time. On a loaded
machine a timing assertion is noise, and it proves nothing about the fix.

## Watch it fail

Run the new test against the unfixed code once and see it fail for the reason
the report gives. Then apply the fix, run the test, then `go test ./...`.

## Keep the diff to the fix

- **Formatting:** `gofmt -w <the files you edited>`. `gofmt -w .` or an editor
  on save rewrites lines in files the report never mentioned.
- **Modules:** leave `go.mod` and `go.sum` alone unless the fix needs a
  dependency. `go build` and `go test` can add `go.sum` lines for modules that
  were only missing a hash. Before finishing, run `git status`; if `go.sum`
  changed and no dependency did, `git checkout -- go.sum`.
- **Everything else you noticed** goes into the answer as a separate finding,
  not into the change.
