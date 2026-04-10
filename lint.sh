#!/usr/bin/env bash
# lint.sh — Architectural & SwiftUI best-practices linter for Explorer
# Enforces folder structure, MVVM patterns, and modern SwiftUI conventions.
# Run: ./lint.sh (from repo root)
# Exit code: 0 = pass, 1 = errors found (warnings don't block)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCES="$REPO_ROOT/Explorer/Sources"
VIEWS="$SOURCES/Views"
TESTS="$REPO_ROOT/Explorer/Tests"
ERROR_FILE=$(mktemp)
WARN_FILE=$(mktemp)
trap 'rm -f "$ERROR_FILE" "$WARN_FILE"' EXIT

fail() {
    echo "$1" >> "$ERROR_FILE"
}

warn() {
    echo "$1" >> "$WARN_FILE"
}

header() {
    echo ""
    echo "── $1 ──"
}

# Helper: strip repo root prefix for cleaner output
rel() {
    echo "${1#$REPO_ROOT/}"
}

# =============================================================================
# ERRORS — These block commits
# =============================================================================

# --- 1. Documentation: README.md in every source directory with .swift files ---

header "Documentation coverage"

while IFS= read -r dir; do
    swift_count=$(find "$dir" -maxdepth 1 -name "*.swift" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$swift_count" -gt 0 ]] && [[ ! -f "$dir/README.md" ]]; then
        fail "Missing README.md: $(rel "$dir")"
    fi
done < <(find "$SOURCES" -type d)

if [[ ! -f "$TESTS/README.md" ]]; then
    fail "Missing README.md: Explorer/Tests"
fi

# --- 2. Deprecated observability APIs ---

header "Observability patterns"

while IFS= read -r match; do
    [[ -n "$match" ]] && fail "Use @Observable instead of ObservableObject: $match"
done < <(grep -rn "ObservableObject" "$SOURCES" --include="*.swift" 2>/dev/null || true)

while IFS= read -r match; do
    [[ -n "$match" ]] && fail "Use @Environment instead of @StateObject: $match"
done < <(grep -rn "@StateObject" "$SOURCES" --include="*.swift" 2>/dev/null || true)

while IFS= read -r match; do
    [[ -n "$match" ]] && fail "Use @Environment instead of @ObservedObject: $match"
done < <(grep -rn "@ObservedObject" "$SOURCES" --include="*.swift" 2>/dev/null || true)

while IFS= read -r match; do
    [[ -n "$match" ]] && fail "@Published is not needed with @Observable: $match"
done < <(grep -rn "@Published" "$SOURCES" --include="*.swift" 2>/dev/null || true)

# --- 3. Safe deletion ---

header "Safe deletion (trashItem, not removeItem)"

while IFS= read -r match; do
    [[ -n "$match" ]] && fail "Use trashItem instead of removeItem in production code: $match"
done < <(grep -rn "\.removeItem(at" "$SOURCES" --include="*.swift" 2>/dev/null | grep -v "lint:allow" || true)

# --- 4. Naming conventions ---

header "Naming conventions"

for f in "$SOURCES"/ViewModels/*.swift; do
    [[ ! -f "$f" ]] && continue
    name=$(basename "$f" .swift)
    if [[ "$name" != *ViewModel ]]; then
        fail "ViewModel file doesn't follow *ViewModel naming: ViewModels/$name.swift"
    fi
done

for f in "$TESTS"/*.swift; do
    [[ ! -f "$f" ]] && continue
    name=$(basename "$f" .swift)
    if [[ "$name" != *Tests ]] && [[ "$name" != "TestHelpers" ]]; then
        fail "Test file doesn't follow *Tests naming: Tests/$name.swift"
    fi
done

# --- 5. ViewModel isolation ---

header "ViewModel isolation (no cross-references)"

VM_NAMES=()
for f in "$SOURCES"/ViewModels/*.swift; do
    [[ ! -f "$f" ]] && continue
    VM_NAMES+=("$(basename "$f" .swift)")
done

for f in "$SOURCES"/ViewModels/*.swift; do
    [[ ! -f "$f" ]] && continue
    current=$(basename "$f" .swift)
    for other in "${VM_NAMES[@]}"; do
        if [[ "$other" != "$current" ]]; then
            while IFS= read -r match; do
                [[ -n "$match" ]] && fail "ViewModel cross-reference ($current → $other): $(basename "$f"):$match"
            done < <(grep -n "$other" "$f" | grep -v "^[0-9]*:[[:space:]]*//" | grep -v "^[0-9]*:[[:space:]]*import" 2>/dev/null || true)
        fi
    done
done

# --- 6. Layer boundaries ---

header "Layer boundaries"

while IFS= read -r match; do
    [[ -n "$match" ]] && fail "ViewModel class defined in Views layer: $match"
done < <(grep -rn "class.*ViewModel" "$VIEWS" --include="*.swift" 2>/dev/null || true)

for layer in ViewModels Services; do
    while IFS= read -r match; do
        [[ -n "$match" ]] && fail "View struct defined in $layer layer: $match"
    done < <(grep -rn "struct.*:.*View" "$SOURCES/$layer" --include="*.swift" 2>/dev/null | grep -v "ViewModel" | grep -v "ViewMode" || true)
done

# --- 7. Test coverage ---

header "Test coverage"

for f in "$SOURCES"/Models/*.swift "$SOURCES"/Services/*.swift "$SOURCES"/ViewModels/*.swift; do
    [[ ! -f "$f" ]] && continue
    name=$(basename "$f" .swift)
    test_exists=$(find "$TESTS" -name "*${name}*Tests.swift" 2>/dev/null | head -1)
    if [[ -z "$test_exists" ]]; then
        layer=$(basename "$(dirname "$f")")
        fail "No test file found for $layer/$name.swift"
    fi
done

# --- 8. No AnyView type erasure (kills SwiftUI diffing performance) ---

header "SwiftUI type safety (no AnyView)"

while IFS= read -r match; do
    [[ -n "$match" ]] && fail "AnyView erases type info and hurts SwiftUI diffing performance: $match"
done < <(grep -rn "AnyView" "$SOURCES" --include="*.swift" 2>/dev/null || true)

# --- 9. No print() in production code ---

header "No debug output in production"

while IFS= read -r match; do
    [[ -n "$match" ]] && fail "Remove print() from production code: $match"
done < <(grep -rn "print(" "$SOURCES" --include="*.swift" 2>/dev/null | grep -v "^.*:[[:space:]]*//" || true)

# =============================================================================
# WARNINGS — Flagged but don't block commits (known tech debt / aspirational)
# =============================================================================

# --- W1. DispatchQueue.main in Views (prefer Task/async-await) ---

header "SwiftUI concurrency (prefer async/await over GCD)"

while IFS= read -r match; do
    [[ -n "$match" ]] && warn "Prefer Task {} or .task over DispatchQueue.main in views: $match"
done < <(grep -rn "DispatchQueue\.main" "$VIEWS" --include="*.swift" 2>/dev/null | grep -v "lint:allow" || true)

# --- W2. Direct FileManager access in Views (should delegate to services/VMs) ---

header "View layer purity (no direct I/O)"

while IFS= read -r match; do
    [[ -n "$match" ]] && warn "Views should delegate FileManager calls to Services/ViewModels: $match"
done < <(grep -rn "FileManager\.default\." "$VIEWS" --include="*.swift" 2>/dev/null | grep -v "homeDirectoryForCurrentUser" || true)

# --- W3. @State holding reference types (should be value types only) ---

header "@State value-type safety"

while IFS= read -r match; do
    [[ -n "$match" ]] && warn "@State should hold value types, not reference types: $match"
done < <(grep -rn "@State.*: Any\b\|@State.*DispatchWorkItem\|@State.*NSObject\|@State.*class " "$VIEWS" --include="*.swift" 2>/dev/null || true)

# --- W4. GeometryReader usage (often misused, causes layout issues) ---

header "GeometryReader usage"

while IFS= read -r match; do
    [[ -n "$match" ]] && warn "GeometryReader can cause layout performance issues — ensure this is necessary: $match"
done < <(grep -rn "GeometryReader" "$SOURCES" --include="*.swift" 2>/dev/null | grep -v "lint:allow" || true)

# =============================================================================
# Results
# =============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

has_errors=false
has_warnings=false

if [[ -s "$WARN_FILE" ]]; then
    has_warnings=true
    warn_count=$(wc -l < "$WARN_FILE" | tr -d ' ')
    echo "⚠️  $warn_count warning(s):"
    echo ""
    while IFS= read -r w; do
        echo "  ⚠ $w"
    done < "$WARN_FILE"
    echo ""
fi

if [[ -s "$ERROR_FILE" ]]; then
    has_errors=true
    error_count=$(wc -l < "$ERROR_FILE" | tr -d ' ')
    echo "❌ $error_count error(s):"
    echo ""
    while IFS= read -r err; do
        echo "  ✖ $err"
    done < "$ERROR_FILE"
    exit 1
fi

if [[ "$has_warnings" == true ]]; then
    echo "✅ No errors (warnings above are non-blocking)"
    exit 0
else
    echo "✅ All checks passed"
    exit 0
fi
