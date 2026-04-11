#!/usr/bin/env bash
# build-pkg.sh — Create a .pkg installer for Explorer
set -euo pipefail

APP_NAME="Explorer"
BUNDLE_ID="com.explorer.app"
VERSION="${1:-1.0.0}"
PKG_NAME="${APP_NAME}-${VERSION}.pkg"

echo "=== Building ${PKG_NAME} ==="

# Build the .app first
./build-app.sh "${VERSION}"

# Create a staging directory for the pkg
STAGING="pkg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING/Applications"
mkdir -p "$STAGING/usr/local/bin"

# Copy the .app bundle
cp -R "${APP_NAME}.app" "$STAGING/Applications/"

# Copy the CLI tool
cp installer-scripts/explore "$STAGING/usr/local/bin/explore"
chmod +x "$STAGING/usr/local/bin/explore"

# Copy the uninstaller
cp installer-scripts/uninstall.sh "$STAGING/usr/local/bin/uninstall-explorer"
chmod +x "$STAGING/usr/local/bin/uninstall-explorer"

# Build the component package
echo "• Creating component package..."
pkgbuild \
    --root "$STAGING" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --scripts installer-scripts \
    --install-location "/" \
    "${APP_NAME}-component.pkg"

# Build a product archive for a nicer installer UI
echo "• Creating product archive..."
productbuild \
    --package "${APP_NAME}-component.pkg" \
    "$PKG_NAME"

# Clean up intermediate files
rm -f "${APP_NAME}-component.pkg"
rm -rf "$STAGING"
rm -rf "${APP_NAME}.app"

echo "✅ Built ${PKG_NAME}"
echo ""
echo "Install with:"
echo "  sudo installer -pkg ${PKG_NAME} -target /"
echo "  # or double-click ${PKG_NAME} in Finder"
