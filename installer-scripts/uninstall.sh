#!/bin/bash
# uninstall.sh: Remove Explorer and restore Finder as the default file manager
#
# Usage: sudo uninstall-explorer

set -e

BUNDLE_ID="com.explorer.app"
BACKUP_DIR="/Library/Application Support/Explorer/backup"
PLIST_PATH="$HOME/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
PLISTBUDDY="/usr/libexec/PlistBuddy"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "=== Explorer Uninstaller ==="
echo ""

# 1. Restore NSFileViewer
if [[ -f "$BACKUP_DIR/nsfileviewer.bak" ]]; then
    ORIGINAL_VIEWER=$(cat "$BACKUP_DIR/nsfileviewer.bak")
    if [[ "$ORIGINAL_VIEWER" == "com.apple.finder" ]]; then
        defaults delete -g NSFileViewer 2>/dev/null || true
        echo "✓ Restored NSFileViewer to Finder (default)"
    else
        defaults write -g NSFileViewer -string "$ORIGINAL_VIEWER"
        echo "✓ Restored NSFileViewer to $ORIGINAL_VIEWER"
    fi
else
    defaults delete -g NSFileViewer 2>/dev/null || true
    echo "✓ Reset NSFileViewer to Finder (no backup found)"
fi

# 2. Restore LaunchServices plist
if [[ -f "$BACKUP_DIR/launchservices.plist.bak" ]]; then
    cp "$BACKUP_DIR/launchservices.plist.bak" "$PLIST_PATH"
    echo "✓ Restored LaunchServices handlers from backup"
else
    # Manually remove Explorer entries
    if [[ -f "$PLIST_PATH" ]]; then
        count=0
        while "$PLISTBUDDY" -c "Print :LSHandlers:$count" "$PLIST_PATH" &>/dev/null; do
            handler=$("$PLISTBUDDY" -c "Print :LSHandlers:$count:LSHandlerRoleAll" "$PLIST_PATH" 2>/dev/null) || true
            if [[ "$handler" == "$BUNDLE_ID" ]]; then
                "$PLISTBUDDY" -c "Delete :LSHandlers:$count" "$PLIST_PATH"
            else
                count=$((count + 1))
            fi
        done
        echo "✓ Removed Explorer handler entries"
    fi
fi

# 3. Refresh LaunchServices
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -lint -seed 2>/dev/null || true
    echo "✓ Refreshed LaunchServices database"
fi

# 4. Remove application
if [[ -d "/Applications/Explorer.app" ]]; then
    rm -rf "/Applications/Explorer.app"
    echo "✓ Removed /Applications/Explorer.app"
fi

# 5. Remove CLI tool
if [[ -f "/usr/local/bin/explore" ]]; then
    rm -f "/usr/local/bin/explore"
    echo "✓ Removed explore CLI command"
fi

# 6. Remove uninstaller
SELF_PATH="/usr/local/bin/uninstall-explorer"
if [[ -f "$SELF_PATH" ]]; then
    rm -f "$SELF_PATH"
    echo "✓ Removed uninstaller"
fi

# 7. Clean up backup directory
rm -rf "$BACKUP_DIR"
# Remove parent dir if empty
rmdir "/Library/Application Support/Explorer" 2>/dev/null || true
echo "✓ Cleaned up backup files"

# 8. Forget the package receipt
pkgutil --forget "$BUNDLE_ID" 2>/dev/null || true
echo "✓ Removed package receipt"

echo ""
echo "✅ Explorer has been uninstalled and Finder has been restored."
echo "   Please log out and back in (or restart) for changes to take full effect."
