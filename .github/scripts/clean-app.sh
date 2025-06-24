#!/bin/bash
# clean-app.sh - Emergency app bundle cleaner using native macOS tools

set -euo pipefail

APP_PATH="$1"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App bundle not found: $APP_PATH"
    exit 1
fi

echo "🚨 Emergency cleaning: $(basename "$APP_PATH")"
echo "  Using aggressive native macOS tools"

# Step 1: Remove all problematic files
echo "  Step 1: Removing problematic files..."
find "$APP_PATH" -name ".DS_Store" -delete 2>/dev/null || true
find "$APP_PATH" -name "._*" -delete 2>/dev/null || true
find "$APP_PATH" -name "__MACOSX" -type d -exec rm -rf {} + 2>/dev/null || true
find "$APP_PATH" -name ".idea" -type d -exec rm -rf {} + 2>/dev/null || true
find "$APP_PATH" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
find "$APP_PATH" -name ".pytest_cache" -type d -exec rm -rf {} + 2>/dev/null || true
find "$APP_PATH" -name ".gitignore" -delete 2>/dev/null || true
find "$APP_PATH" -name ".gitmodules" -delete 2>/dev/null || true

# Step 2: Remove Python cache files (major source of xattrs)
echo "  Step 2: Removing Python cache files..."
find "$APP_PATH" -name "*.pyc" -delete 2>/dev/null || true
find "$APP_PATH" -name "*.pyo" -delete 2>/dev/null || true
find "$APP_PATH" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# Step 3: Use dot_clean utility first
echo "  Step 3: Running dot_clean utility..."
dot_clean -m "$(dirname "$APP_PATH")" 2>/dev/null || true

# Step 4: Focus on frameworks - they're usually the problem
echo "  Step 4: Deep cleaning frameworks..."
if [ -d "$APP_PATH/Contents/Frameworks" ]; then
    # Clean each framework individually
    for framework in "$APP_PATH/Contents/Frameworks"/*; do
        if [ -e "$framework" ]; then
            echo "    Cleaning: $(basename "$framework")"
            
            # Remove xattrs multiple ways
            xattr -rc "$framework" 2>/dev/null || true
            xattr -d "*" "$framework" 2>/dev/null || true
            
            # Remove specific problematic attributes
            xattr -d com.apple.FinderInfo "$framework" 2>/dev/null || true
            xattr -d com.apple.ResourceFork "$framework" 2>/dev/null || true
            xattr -d com.apple.quarantine "$framework" 2>/dev/null || true
            
            # If it's a dylib, clean it specifically
            if [[ "$framework" == *.dylib ]]; then
                xattr -c "$framework" 2>/dev/null || true
                # Use SetFile if available
                if command -v SetFile >/dev/null 2>&1; then
                    SetFile -c "" -t "" "$framework" 2>/dev/null || true
                fi
            fi
        fi
    done
    
    # Try recreating frameworks directory with ditto
    echo "    Recreating frameworks with ditto..."
    TEMP_FRAMEWORKS="/tmp/frameworks_$(date +%s)"
    if ditto --norsrc --noextattr --noacl "$APP_PATH/Contents/Frameworks" "$TEMP_FRAMEWORKS" 2>/dev/null; then
        rm -rf "$APP_PATH/Contents/Frameworks"
        mv "$TEMP_FRAMEWORKS" "$APP_PATH/Contents/Frameworks"
        echo "    ✅ Frameworks recreated cleanly"
    else
        rm -rf "$TEMP_FRAMEWORKS" 2>/dev/null || true
    fi
fi

# Step 5: Strip all extended attributes using multiple methods
echo "  Step 5: Stripping extended attributes (multiple methods)..."

# Method 1: xattr -rc
xattr -rc "$APP_PATH" 2>/dev/null || true

# Method 2: Delete all xattrs by wildcard
find "$APP_PATH" -type f -exec xattr -d "*" {} \; 2>/dev/null || true
find "$APP_PATH" -type d -exec xattr -d "*" {} \; 2>/dev/null || true

# Method 3: SetFile if available
if command -v SetFile >/dev/null 2>&1; then
    echo "    Using SetFile to clear Finder info..."
    find "$APP_PATH" -type f -exec SetFile -c "" -t "" {} \; 2>/dev/null || true
fi

# Method 4: Target specific attributes
for attr in com.apple.FinderInfo com.apple.ResourceFork com.apple.quarantine com.apple.metadata:kMDItemWhereFroms; do
    xattr -dr $attr "$APP_PATH" 2>/dev/null || true
done

# Step 6: Last resort - recreate entire app with ditto
echo "  Step 6: Final attempt - recreate with ditto..."
TEMP_APP="/tmp/$(basename "$APP_PATH").clean.$(date +%s)"
if ditto --norsrc --noextattr --noacl "$APP_PATH" "$TEMP_APP"; then
    # One more cleanup on the copy
    xattr -rc "$TEMP_APP" 2>/dev/null || true
    
    # Replace original
    rm -rf "$APP_PATH"
    mv "$TEMP_APP" "$APP_PATH"
    echo "  ✅ Replaced with completely clean copy"
else
    echo "  ⚠️  Ditto recreation failed"
    rm -rf "$TEMP_APP" 2>/dev/null || true
fi

# Verify
echo "  Verifying cleanup..."
XATTR_FILES=$(find "$APP_PATH" -exec xattr -l {} + 2>/dev/null | grep -c "^[^[:space:]]" || echo "0")
echo "  Files with xattrs: $XATTR_FILES"

if [ "$XATTR_FILES" -eq 0 ]; then
    echo "✅ Emergency clean successful - NO EXTENDED ATTRIBUTES!"
    exit 0
else
    echo "⚠️  $XATTR_FILES files still have xattrs"
    echo "  Showing first 5 problematic files:"
    find "$APP_PATH" -exec xattr -l {} + 2>/dev/null | grep "^[^[:space:]]" | head -5
    exit 0
fi
