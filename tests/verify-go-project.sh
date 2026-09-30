#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: Netresearch DTT GmbH
#
# tests/verify-go-project.sh — behavioural tests for
# skills/go-development/scripts/verify-go-project.sh.
#
# Each case builds a throwaway project directory and runs the verifier against
# it with a controlled PATH: a stub `go` records where `go vet` ran and exits
# with the status the case asks for, or `go` is left off PATH entirely. No real
# Go toolchain is needed. Requires bash and coreutils, find, grep, sed and awk.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/skills/go-development/scripts/verify-go-project.sh"
BASH_BIN="$(command -v bash)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
count=0

# A PATH holding only the tools the verifier uses, so `command -v go` fails.
NOGO="$WORK/bin-nogo"
mkdir -p "$NOGO"
for tool in awk find grep head wc; do
    ln -s "$(command -v "$tool")" "$NOGO/$tool"
done

# A stub `go` in front of that PATH. It logs its working directory and
# arguments to $GO_LOG and exits with $GO_VET_RC (default 0).
STUB="$WORK/bin-stub"
mkdir -p "$STUB"
cat > "$STUB/go" <<'EOF'
#!/bin/sh
printf '%s %s\n' "$PWD" "$*" >> "$GO_LOG"
exit "${GO_VET_RC:-0}"
EOF
chmod +x "$STUB/go"
export GO_LOG="$WORK/go.log"

# project <name> [parts...] — creates $WORK/<name> with the given parts:
# mod, sum, main, test, dockerfile, makefile.
project() {
    local dir="$WORK/$1"
    shift
    mkdir -p "$dir"
    for part in "$@"; do
        case "$part" in
            mod) printf 'module example.com/demo\n\ngo 1.22\n' > "$dir/go.mod" ;;
            sum) : > "$dir/go.sum" ;;
            main) mkdir -p "$dir/cmd/demo" && printf 'package main\n\nfunc main() {}\n' > "$dir/cmd/demo/main.go" ;;
            test) mkdir -p "$dir/internal/x" && printf 'package x\n' > "$dir/internal/x/x_test.go" ;;
            dockerfile) : > "$dir/Dockerfile" ;;
            makefile) : > "$dir/Makefile" ;;
        esac
    done
}

OUT=""
RC=0
# run <cwd> <path-mode: stub|nogo> [argument] — runs the verifier, keeps
# output and exit code in OUT and RC.
run() {
    local cwd="$1" mode="$2" path
    shift 2
    if [ "$mode" = stub ]; then path="$STUB:$NOGO"; else path="$NOGO"; fi
    : > "$GO_LOG"
    OUT=$(cd "$cwd" && PATH="$path" "$BASH_BIN" "$SCRIPT" "$@" 2>&1)
    RC=$?
}

check() { # check <description> <command...> — passes when the command succeeds
    local desc="$1"
    shift
    count=$((count + 1))
    if "$@"; then
        echo "  ok   $desc"
    else
        echo "  FAIL $desc"
        printf '%s\n' "$OUT" | sed 's/^/         /'
        fail=1
    fi
}

exits() { [ "$RC" -eq "$1" ]; }
has() { grep -qF -- "$1" <<< "$OUT"; }
line() { grep -qFx -- "$1" <<< "$OUT"; }

echo "verify-go-project.sh"

project full mod sum main test dockerfile makefile
run "$WORK" stub full
check "complete project passes" exits 0
check "complete project has no warnings" line 'Warnings: 0'
check "test files are found for a relative project path" line '✅ Found 1 test files'
check "Dockerfile is found for a relative project path" line '✅ Dockerfile found'
check "go vet runs inside the project directory" grep -qFx "$WORK/full vet ./..." "$GO_LOG"

run "$WORK/full" stub
check "default directory is the working directory" exits 0
check "default directory finds every item" line 'Warnings: 0'

project empty
run "$WORK" stub empty
check "missing go.mod fails" exits 1
check "missing go.mod does not stop the run" has '=== Summary ==='
check "missing go.mod is the one error" line 'Errors: 1'
check "every other missing item is a warning" line 'Warnings: 5'

project modonly mod
run "$WORK" stub modonly
check "go.mod alone passes" exits 0
check "go.mod alone reports five warnings" line 'Warnings: 5'

GO_VET_RC=1 run "$WORK" stub full
check "go vet findings fail the run" exits 1
check "go vet findings are reported" has 'go vet found issues'
check "go vet findings do not stop the run" line '✅ Makefile found'

run "$WORK" nogo full
check "missing Go toolchain does not fail the run" exits 0
check "missing Go toolchain is reported as a warning" has 'Go not installed'
check "missing Go toolchain is the only warning" line 'Warnings: 1'

echo
if [ "$fail" -ne 0 ]; then
    echo "verify-go-project.sh: FAILED ($count checks)"
    exit 1
fi
echo "verify-go-project.sh: all $count checks passed"
