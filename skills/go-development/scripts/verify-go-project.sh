#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: Netresearch DTT GmbH
# Go Project Verification Script
# Validates Go project structure and quality

set -e

PROJECT_DIR="${1:-.}"
ERRORS=0
WARNINGS=0

echo "=== Go Project Verification ==="
echo "Directory: $PROJECT_DIR"
echo ""

# Check go.mod exists
if [[ -f "$PROJECT_DIR/go.mod" ]]; then
    echo "✅ go.mod found"
    MODULE=$(grep "^module" "$PROJECT_DIR/go.mod" | awk '{print $2}')
    echo "   Module: $MODULE"
else
    echo "❌ go.mod not found"
    ERRORS=$((ERRORS + 1))
fi

# Check go.sum exists
if [[ -f "$PROJECT_DIR/go.sum" ]]; then
    echo "✅ go.sum found"
else
    echo "⚠️  go.sum not found (run 'go mod tidy')"
    WARNINGS=$((WARNINGS + 1))
fi

# Check standard directories
echo ""
echo "=== Directory Structure ==="
for dir in cmd core internal pkg; do
    if [[ -d "$PROJECT_DIR/$dir" ]]; then
        echo "✅ $dir/ exists"
    fi
done

# Check for main.go
MAIN_FILES=$(find "$PROJECT_DIR" -name "main.go" 2>/dev/null | head -5)
if [[ -n "$MAIN_FILES" ]]; then
    echo "✅ Entry points found:"
    echo "$MAIN_FILES" | while read -r f; do echo "   - $f"; done
else
    echo "⚠️  No main.go found"
    WARNINGS=$((WARNINGS + 1))
fi

# Run go vet
echo ""
echo "=== Static Analysis ==="
if command -v go &> /dev/null; then
    # Subshell: the checks below resolve paths against $PROJECT_DIR, so the
    # script's own working directory must not change.
    if (cd "$PROJECT_DIR" && go vet ./... 2>&1); then
        echo "✅ go vet passed"
    else
        echo "❌ go vet found issues"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "⚠️  Go not installed, skipping vet"
    WARNINGS=$((WARNINGS + 1))
fi

# Check for tests
echo ""
echo "=== Test Coverage ==="
TEST_FILES=$(find "$PROJECT_DIR" -name "*_test.go" 2>/dev/null | wc -l)
if [[ "$TEST_FILES" -gt 0 ]]; then
    echo "✅ Found $TEST_FILES test files"
else
    echo "⚠️  No test files found"
    WARNINGS=$((WARNINGS + 1))
fi

# Check for Dockerfile
echo ""
echo "=== Deployment ==="
if [[ -f "$PROJECT_DIR/Dockerfile" ]]; then
    echo "✅ Dockerfile found"
else
    echo "⚠️  No Dockerfile found"
    WARNINGS=$((WARNINGS + 1))
fi

# Check for Makefile
if [[ -f "$PROJECT_DIR/Makefile" ]]; then
    echo "✅ Makefile found"
else
    echo "⚠️  No Makefile found"
    WARNINGS=$((WARNINGS + 1))
fi

# Summary
echo ""
echo "=== Summary ==="
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"

if [[ $ERRORS -gt 0 ]]; then
    echo "❌ Verification FAILED"
    exit 1
else
    echo "✅ Verification PASSED"
    exit 0
fi
