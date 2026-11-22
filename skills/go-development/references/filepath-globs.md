# Config Paths, Globs and Fail-Closed Checks

Read this before code decides something from whether a configured path
exists or matches: a security default, a fallback, a "no config file, use
flags" branch. One `path/filepath` behaviour makes such a decision fail
open, a second one makes it misread every Windows path, and the existence
check itself has a choice that matters.

## `filepath.Glob` drops directory read errors

From `go doc path/filepath.Glob`:

```text
Glob ignores file system errors such as I/O errors reading directories. The
only possible returned error is ErrBadPattern, when pattern is malformed.
```

So a glob over a directory the process cannot list returns no match and a
nil error, the same result as a directory without a matching file. Code
that reads "no match" as "no config" then takes the no-config branch while a
config exists. When a load through a glob pattern failed, treat the config
as possibly existing.

## `\` is an escape character except on Windows

From `go doc path/filepath.Match`:

```text
On Windows, escaping is disabled. Instead, '\\' is treated as path
separator.
```

A check "does this path hold glob syntax" therefore needs a different set of
characters per platform: `*?[\` outside Windows, `*?[` on Windows. One
constant `*?[\` makes every Windows path look like a glob. Use build-tagged
constants:

```go
// config_glob_meta_other.go
//go:build !windows

package cli

const globMeta = `*?[\`
```

```go
// config_glob_meta_windows.go
//go:build windows

package cli

const globMeta = "*?["
```

Check the Windows file compiles with `GOOS=windows go vet ./...`.

## Existence check: `os.Lstat`, and decide each result

```go
func configMayExist(pattern string) bool {
	if strings.ContainsAny(pattern, globMeta) {
		return true // a failed glob load may hide files it could not list
	}
	info, err := os.Lstat(pattern)
	if err == nil {
		return !info.IsDir()
	}
	return !errors.Is(err, fs.ErrNotExist) // permission denied: may exist
}
```

- `os.Lstat`, not `os.Stat`: a mounted Kubernetes ConfigMap is a symlink
  that can briefly dangle while it is updated. `os.Stat` then reports "does
  not exist", and the no-config branch runs.
- A directory at the path counts as no config: a container runtime creates
  a directory when a bind mount's source file is missing.
- Any other error, such as permission denied, counts as "may exist".

Each branch needs a test that fails when the branch is forced the other way.
Origin: netresearch/ofelia#981.
