# version-lib.sh — Shared version handling for build-pkg.sh and update-app.sh.
# Source this file; don't run it. The VERSION file at the repo root is the
# source of truth, and versions may only move forward.

VERSION_FILE="VERSION"
VERSION_PATTERN='^([0-9]+\.)*[0-9]+$'

version_usage() {
    cat >&2 << USAGE
Usage: $0 --increment | --noincrement | <version>

  --increment     Bump the last component of VERSION (1.0.0 -> 1.0.1)
  --noincrement   Rebuild using the current VERSION
  <version>       Use an explicit version newer than VERSION, e.g. 1.2.0
USAGE
    exit 1
}

# Succeeds if version $1 is greater than version $2 (compared numerically,
# component by component; missing components count as 0).
version_gt() {
    local IFS=.
    local -a a=($1) b=($2)
    local i len=$(( ${#a[@]} > ${#b[@]} ? ${#a[@]} : ${#b[@]} ))
    for (( i = 0; i < len; i++ )); do
        local x=$(( 10#${a[i]:-0} )) y=$(( 10#${b[i]:-0} ))
        (( x > y )) && return 0
        (( x < y )) && return 1
    done
    return 1
}

# Resolve the build version from the script's single argument.
# Sets CURRENT_VERSION (from the VERSION file) and VERSION (to build).
resolve_version() {
    [[ $# -eq 1 ]] || version_usage

    if [[ ! -f "$VERSION_FILE" ]]; then
        echo "Error: ${VERSION_FILE} file not found in $(pwd)" >&2
        exit 1
    fi
    CURRENT_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")
    if [[ ! "$CURRENT_VERSION" =~ $VERSION_PATTERN ]]; then
        echo "Error: ${VERSION_FILE} contains an invalid version '${CURRENT_VERSION}'" >&2
        exit 1
    fi

    case "$1" in
        --increment)
            local last="${CURRENT_VERSION##*.}"
            if [[ "$CURRENT_VERSION" == *.* ]]; then
                VERSION="${CURRENT_VERSION%.*}.$(( 10#$last + 1 ))"
            else
                VERSION="$(( 10#$last + 1 ))"
            fi
            ;;
        --noincrement)
            VERSION="$CURRENT_VERSION"
            ;;
        -*)
            version_usage
            ;;
        *)
            if [[ ! "$1" =~ $VERSION_PATTERN ]]; then
                echo "Error: Invalid version '$1' (expected e.g. 1.2.0)" >&2
                exit 1
            fi
            if ! version_gt "$1" "$CURRENT_VERSION"; then
                echo "Error: Version $1 must be newer than ${CURRENT_VERSION} (use --noincrement to rebuild ${CURRENT_VERSION})" >&2
                exit 1
            fi
            VERSION="$1"
            ;;
    esac
}

# Record the new version. Call only after the build/install succeeded.
save_version() {
    if [[ "$VERSION" != "$CURRENT_VERSION" ]]; then
        echo "$VERSION" > "$VERSION_FILE"
        echo "• Updated ${VERSION_FILE}: ${CURRENT_VERSION} -> ${VERSION} (remember to commit it)"
    fi
}
