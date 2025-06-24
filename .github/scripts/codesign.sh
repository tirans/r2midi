#!/bin/bash
# codesign.sh - Code signing script

set -euo pipefail

APP_PATH="$1"
CERT_IDENTITY="$2"
ENTITLEMENTS_FILE="$3"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ App bundle not found: $APP_PATH"
    exit 1
fi

if [ ! -f "$ENTITLEMENTS_FILE" ]; then
    echo "❌ Entitlements file not found: $ENTITLEMENTS_FILE"
    exit 1
fi

echo "🔐 Code signing: $(basename "$APP_PATH")"
echo "  📋 Certificate: $CERT_IDENTITY"
echo "  📄 Entitlements: $(basename "$ENTITLEMENTS_FILE")"

# Step 1: Sign all dynamic libraries first
echo "  📚 Signing dynamic libraries..."
DYLIB_COUNT=0
while IFS= read -r -d '' dylib; do
    echo "    🔗 $(basename "$dylib")"
    if codesign --force --sign "$CERT_IDENTITY" --timestamp --options runtime "$dylib" 2>/dev/null; then
        DYLIB_COUNT=$((DYLIB_COUNT + 1))
    else
        echo "    ⚠️  Failed to sign $(basename "$dylib")"
    fi
done < <(find "$APP_PATH" -name "*.dylib" -type f -print0 2>/dev/null)

echo "  ✅ Signed $DYLIB_COUNT dynamic libraries"

# Step 2: Sign all Python extensions
echo "  🐍 Signing Python extensions..."
SO_COUNT=0
while IFS= read -r -d '' so_file; do
    echo "    🔗 $(basename "$so_file")"
    if codesign --force --sign "$CERT_IDENTITY" --timestamp --options runtime "$so_file" 2>/dev/null; then
        SO_COUNT=$((SO_COUNT + 1))
    else
        echo "    ⚠️  Failed to sign $(basename "$so_file")"
    fi
done < <(find "$APP_PATH" -name "*.so" -type f -print0 2>/dev/null)

echo "  ✅ Signed $SO_COUNT Python extensions"

# Step 3: Sign frameworks
echo "  🏗️  Signing frameworks..."
FRAMEWORK_COUNT=0
if [ -d "$APP_PATH/Contents/Frameworks" ]; then
    while IFS= read -r -d '' framework; do
        echo "    📦 $(basename "$framework")"
        if codesign --force --sign "$CERT_IDENTITY" --timestamp --options runtime "$framework" 2>/dev/null; then
            FRAMEWORK_COUNT=$((FRAMEWORK_COUNT + 1))
        else
            echo "    ⚠️  Failed to sign $(basename "$framework")"
        fi
    done < <(find "$APP_PATH/Contents/Frameworks" -name "*.framework" -type d -print0 2>/dev/null)
fi

echo "  ✅ Signed $FRAMEWORK_COUNT frameworks"

# Step 4: Sign the main executable
echo "  ⚙️  Signing main executable..."
MAIN_EXECUTABLE=""

# Find the main executable - try app name first
APP_NAME=$(basename "$APP_PATH" .app)
if [ -f "$APP_PATH/Contents/MacOS/$APP_NAME" ] && [ -x "$APP_PATH/Contents/MacOS/$APP_NAME" ]; then
    MAIN_EXECUTABLE="$APP_PATH/Contents/MacOS/$APP_NAME"
    echo "    📱 Found app-specific executable: $APP_NAME"
else
    # Find any executable
    EXECUTABLES=($(find "$APP_PATH/Contents/MacOS" -type f -perm +111 2>/dev/null))
    if [ ${#EXECUTABLES[@]} -gt 0 ]; then
        MAIN_EXECUTABLE="${EXECUTABLES[0]}"
        echo "    📱 Found executable: $(basename "$MAIN_EXECUTABLE")"
    fi
fi

if [ -n "$MAIN_EXECUTABLE" ]; then
    echo "    🔐 Signing main executable..."
    if codesign --force --sign "$CERT_IDENTITY" --timestamp --options runtime --entitlements "$ENTITLEMENTS_FILE" "$MAIN_EXECUTABLE"; then
        echo "    ✅ Main executable signed successfully"
    else
        echo "    ❌ Failed to sign main executable"
        exit 1
    fi
else
    echo "    ⚠️  No main executable found"
fi

# Step 5: Sign the entire app bundle
echo "  📦 Signing entire app bundle..."
if codesign --force --sign "$CERT_IDENTITY" --timestamp --options runtime --entitlements "$ENTITLEMENTS_FILE" --deep "$APP_PATH"; then
    echo "  ✅ App bundle signed successfully"
else
    echo "  ❌ Failed to sign app bundle"
    exit 1
fi

# Step 6: Verify the signature
echo "  🔍 Verifying signature..."
if codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null 2>&1; then
    echo "  ✅ Signature verification passed"
else
    echo "  ❌ Signature verification failed"
    echo "  🔍 Verification details:"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 | head -5
    exit 1
fi

echo "🎉 Code signing completed successfully!"
exit 0
