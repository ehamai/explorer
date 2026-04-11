#!/usr/bin/env bash
# build-app.sh — Build Explorer.app bundle from Swift Package Manager
set -euo pipefail

APP_NAME="Explorer"
BUNDLE_ID="com.explorer.app"
VERSION="${1:-1.0.0}"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

echo "=== Building ${APP_NAME} v${VERSION} ==="

# Build release binary
echo "• Building release binary..."
swift build -c release 2>&1 | tail -1

BINARY=".build/release/${APP_NAME}"
if [[ ! -f "$BINARY" ]]; then
    echo "Error: Binary not found at ${BINARY}" >&2
    exit 1
fi

# Create bundle structure
echo "• Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy binary
cp "${BINARY}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Copy entitlements
cp "Explorer/Resources/Explorer.entitlements" "${RESOURCES_DIR}/"

# Create Info.plist
cat > "${CONTENTS}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>

    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>

    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>

    <key>CFBundleVersion</key>
    <string>${VERSION}</string>

    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>

    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>

    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>

    <!-- Register as a folder handler -->
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Folder</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.folder</string>
            </array>
        </dict>
    </array>

    <!-- Register for file:// URL scheme -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>${BUNDLE_ID}.file</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>file</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Ad-hoc code sign
echo "• Code signing (ad-hoc)..."
codesign --sign - --deep --force --options runtime "${APP_BUNDLE}" 2>/dev/null || {
    echo "  Warning: Code signing failed (app will still work locally)"
}

echo "✅ Built ${APP_BUNDLE}"
