#!/bin/bash
# emergency-clean-app.sh - Emergency app bundle cleaner when Python script is not available

set -euo pipefail

APP_PATH="$1"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App bundle not found: $APP_PATH"
    exit 1
fi

echo "🚨 Emergency cleaning: $(basename "$APP_PATH")"

# Step 1: Remove all problematic files
echo "  Removing problematic files..."
find "$APP_PATH" -name ".DS_Store" -delete 2>/dev/null || true
find "$APP_PATH" -name "._*" -delete 2>/dev/null || true
find "$APP_PATH" -name "__MACOSX" -type d -exec rm -rf {} + 2>/dev/null || true
find "$APP_PATH" -name ".idea" -type d -exec rm -rf {} + 2>/dev/null || true
find "$APP_PATH" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
find "$APP_PATH" -name ".pytest_cache" -type d -exec rm -rf {} + 2>/dev/null || true
find "$APP_PATH" -name ".gitignore" -delete 2>/dev/null || true

# Step 2: Remove Python cache files (major source of xattrs)
echo "  Removing Python cache files..."
find "$APP_PATH" -name "*.pyc" -delete 2>/dev/null || true
find "$APP_PATH" -name "*.pyo" -delete 2>/dev/null || true
find "$APP_PATH" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# Step 3: Use ditto to create clean copy
echo "  Creating clean copy with ditto..."
TEMP_APP="/tmp/$(basename "$APP_PATH").clean.$(date +%s)"
if ditto --norsrc --noextattr --noacl "$APP_PATH" "$TEMP_APP"; then
    # Remove original and replace with clean copy
    rm -rf "$APP_PATH"
    mv "$TEMP_APP" "$APP_PATH"
    echo "  ✅ Replaced with clean copy"
else
    echo "  ⚠️  Ditto failed, continuing with in-place cleanup"
    rm -rf "$TEMP_APP" 2>/dev/null || true
fi

# Step 4: Strip all extended attributes
echo "  Stripping extended attributes..."
xattr -rc "$APP_PATH" 2>/dev/null || true

# Step 5: Per-file xattr removal (belt and suspenders)
echo "  Per-file xattr removal..."
find "$APP_PATH" -type f -exec xattr -c {} \; 2>/dev/null || true
find "$APP_PATH" -type d -exec xattr -c {} \; 2>/dev/null || true

# Verify
XATTR_COUNT=$(find "$APP_PATH" -exec xattr -l {} \; 2>/dev/null | wc -l)
echo "  Remaining xattrs: $XATTR_COUNT"

if [ "$XATTR_COUNT" -eq 0 ]; then
    echo "✅ Emergency clean successful!"
    exit 0
else
    echo "⚠️  Some xattrs remain, but should be reduced"
    exit 0
fi
