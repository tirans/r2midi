#!/bin/bash
# app-cleaner.sh - App bundle cleaner

set -euo pipefail

APP_PATH="$1"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ App bundle not found: $APP_PATH"
    exit 1
fi

echo "🧹 Cleaning app bundle: $(basename "$APP_PATH")"

# Step 1: Remove obvious problematic files
echo "  📁 Removing metadata files..."
find "$APP_PATH" -name ".DS_Store" -delete 2>/dev/null || true
find "$APP_PATH" -name "._*" -delete 2>/dev/null || true
find "$APP_PATH" -name "__MACOSX" -type d -exec rm -rf {} + 2>/dev/null || true

# Step 2: Remove Python cache (major source of issues)
echo "  🐍 Removing Python cache files..."
find "$APP_PATH" -name "*.pyc" -delete 2>/dev/null || true
find "$APP_PATH" -name "*.pyo" -delete 2>/dev/null || true
find "$APP_PATH" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# Step 3: Remove extended attributes - multiple approaches
echo "  🏷️  Removing extended attributes..."

# Method 1: Bulk removal
xattr -rc "$APP_PATH" 2>/dev/null || true

# Method 2: Target specific problematic attributes
find "$APP_PATH" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$APP_PATH" -exec xattr -d com.apple.ResourceFork {} \; 2>/dev/null || true
find "$APP_PATH" -exec xattr -d com.apple.quarantine {} \; 2>/dev/null || true

# Method 3: Handle the stubborn com.apple.provenance
echo "  🔧 Handling com.apple.provenance attributes..."
find "$APP_PATH" -exec xattr -d com.apple.provenance {} \; 2>/dev/null || true

# Step 4: Use dot_clean utility
echo "  🧽 Running dot_clean utility..."
dot_clean -m "$APP_PATH" 2>/dev/null || true

# Step 5: Create a clean copy using ditto (strips resource forks)
echo "  📋 Creating clean copy with ditto..."
TEMP_APP="/tmp/$(basename "$APP_PATH").clean.$$"
rm -rf "$TEMP_APP" 2>/dev/null || true

if ditto --norsrc --noextattr --noacl "$APP_PATH" "$TEMP_APP"; then
    # Verify the copy is cleaner
    ORIGINAL_ATTRS=$(find "$APP_PATH" -exec xattr -l {} + 2>/dev/null | wc -l)
    COPY_ATTRS=$(find "$TEMP_APP" -exec xattr -l {} + 2>/dev/null | wc -l)
    
    if [ "$COPY_ATTRS" -lt "$ORIGINAL_ATTRS" ]; then
        echo "  ✅ Ditto copy is cleaner ($COPY_ATTRS vs $ORIGINAL_ATTRS attributes)"
        rm -rf "$APP_PATH"
        mv "$TEMP_APP" "$APP_PATH"
    else
        echo "  ℹ️  Ditto copy not significantly cleaner, keeping original"
        rm -rf "$TEMP_APP"
    fi
else
    echo "  ⚠️  Ditto copy failed, keeping original"
    rm -rf "$TEMP_APP" 2>/dev/null || true
fi

# Final verification
FINAL_ATTRS=$(find "$APP_PATH" -exec xattr -l {} + 2>/dev/null | wc -l)
echo "  📊 Final result: $FINAL_ATTRS total extended attributes"

if [ "$FINAL_ATTRS" -eq 0 ]; then
    echo "🎉 Perfect! No extended attributes remaining"
elif [ "$FINAL_ATTRS" -lt 100 ]; then
    echo "✅ Good! Only $FINAL_ATTRS extended attributes remaining"
else
    echo "⚠️  Warning: $FINAL_ATTRS extended attributes remaining"
    echo "  🔍 First few problematic files:"
    find "$APP_PATH" -exec xattr -l {} + 2>/dev/null | head -5
fi

echo "✅ App bundle cleaning completed"
exit 0
