#!/usr/bin/env bash
# update-app.sh — Rebuild Explorer.app and replace an already-installed copy
# in /Applications. Does not touch the `explore` CLI or default file manager
# settings; use build-pkg.sh for a full (re)install.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Explorer"
INSTALLED_APP="/Applications/${APP_NAME}.app"
APP_BINARY="${INSTALLED_APP}/Contents/MacOS/${APP_NAME}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

source ./version-lib.sh
resolve_version "$@"

if [[ ! -d "$INSTALLED_APP" ]]; then
    echo "Error: ${INSTALLED_APP} not found. Install first with ./build-pkg.sh" >&2
    exit 1
fi

INSTALLED_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "${INSTALLED_APP}/Contents/Info.plist" 2>/dev/null || echo "0")

if version_gt "$INSTALLED_VERSION" "$VERSION"; then
    echo "Error: Installed v${INSTALLED_VERSION} is newer than v${VERSION}; refusing to downgrade" >&2
    exit 1
fi

echo "Installed: v${INSTALLED_VERSION} -> Updating to: v${VERSION}"

# Build before quitting so a failed build leaves the running app alone
./build-app.sh "${VERSION}"

# Ask for sudo up front (installed bundle is root-owned from the .pkg)
sudo -v

WAS_RUNNING=false
if pgrep -f "$APP_BINARY" >/dev/null; then
    WAS_RUNNING=true
    echo "• Quitting ${APP_NAME}..."
    osascript -e "quit app \"${APP_NAME}\"" >/dev/null 2>&1 || true
    for _ in {1..20}; do
        pgrep -f "$APP_BINARY" >/dev/null || break
        sleep 0.5
    done
    if pgrep -f "$APP_BINARY" >/dev/null; then
        echo "Error: ${APP_NAME} did not quit. Close it and re-run." >&2
        exit 1
    fi
fi

echo "• Replacing ${INSTALLED_APP}..."
sudo rm -rf "$INSTALLED_APP"
sudo ditto "${APP_NAME}.app" "$INSTALLED_APP"
rm -rf "${APP_NAME}.app"

# Refresh LaunchServices so it picks up the new bundle
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$INSTALLED_APP" 2>/dev/null || true
fi

save_version
echo "✅ Updated ${APP_NAME} to v${VERSION}"

if $WAS_RUNNING; then
    open "$INSTALLED_APP"
fi
