#!/bin/bash
# simple-sign-and-notarize.sh - Main orchestrator script

set -euo pipefail

# Default values
VERSION=""
BUILD_TYPE="production"
SKIP_NOTARIZATION=false
TARGET_PATH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --dev)
            BUILD_TYPE="dev"
            SKIP_NOTARIZATION=true  # Dev builds skip notarization
            shift
            ;;
        --skip-notarize)
            SKIP_NOTARIZATION=true
            shift
            ;;
        --target)
            TARGET_PATH="$2"
            shift 2
            ;;
        --help)
            cat << EOF
Simple Sign and Notarize Script

Usage: $0 [options]

Options:
  --version VERSION     Specify version (required)
  --dev                Development build (skips notarization)
  --skip-notarize      Skip notarization step
  --target PATH        Specific target to sign (optional)
  --help               Show this help

Examples:
  $0 --version 1.0.0
  $0 --version 1.0.0 --dev
  $0 --version 1.0.0 --target "dist/MyApp.app"
EOF
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$VERSION" ]; then
    echo "❌ Version is required. Use --version VERSION"
    exit 1
fi

echo "🚀 Simple Sign and Notarize"
echo "  📋 Version: $VERSION"
echo "  🛠️  Build Type: $BUILD_TYPE"
echo "  📝 Skip Notarization: $SKIP_NOTARIZATION"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for required scripts
REQUIRED_SCRIPTS=("simple-app-cleaner.sh" "simple-codesign.sh")
if [ "$SKIP_NOTARIZATION" = false ]; then
    REQUIRED_SCRIPTS+=("simple-notarize.sh")
fi

echo "🔍 Checking required scripts..."
for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ -f "$SCRIPT_DIR/$script" ]; then
        chmod +x "$SCRIPT_DIR/$script"
        echo "  ✅ $script"
    else
        echo "  ❌ $script not found"
        exit 1
    fi
done

# Find certificate
echo "🔍 Finding signing certificate..."
CERT_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*) "\(.*\)"/\1/')

if [ -z "$CERT_IDENTITY" ]; then
    echo "❌ No Developer ID Application certificate found"
    echo "Available certificates:"
    security find-identity -v -p codesigning
    exit 1
fi

echo "  ✅ Found certificate: $CERT_IDENTITY"

# Create entitlements file
ENTITLEMENTS_FILE="/tmp/simple-entitlements-$$.plist"
cat > "$ENTITLEMENTS_FILE" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
EOF

echo "✅ Created entitlements file: $(basename "$ENTITLEMENTS_FILE")"

# Find targets to process
TARGETS=()

if [ -n "$TARGET_PATH" ]; then
    if [ -e "$TARGET_PATH" ]; then
        TARGETS=("$TARGET_PATH")
        echo "🎯 Using specified target: $TARGET_PATH"
    else
        echo "❌ Specified target not found: $TARGET_PATH"
        exit 1
    fi
else
    echo "🔍 Finding targets to sign..."
    
    # Find .app bundles
    while IFS= read -r -d '' app; do
        TARGETS+=("$app")
        echo "  📱 Found app: $app"
    done < <(find . -name "*.app" -type d -print0 2>/dev/null)
    
    # Find .pkg files
    while IFS= read -r -d '' pkg; do
        TARGETS+=("$pkg")
        echo "  📦 Found package: $pkg"
    done < <(find . -name "*.pkg" -type f -print0 2>/dev/null)
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
    echo "❌ No targets found to sign"
    exit 1
fi

echo "📊 Found ${#TARGETS[@]} target(s) to process"

# Process each target
SUCCESS_COUNT=0
FAILURE_COUNT=0

for target in "${TARGETS[@]}"; do
    echo ""
    echo "🎯 Processing: $(basename "$target")"
    
    TARGET_SUCCESS=true
    
    # Step 1: Clean (for .app bundles only)
    if [[ "$target" == *.app ]]; then
        echo "  🧹 Cleaning app bundle..."
        if "$SCRIPT_DIR/simple-app-cleaner.sh" "$target"; then
            echo "  ✅ Cleaning completed"
        else
            echo "  ⚠️  Cleaning had issues, continuing anyway"
        fi
    fi
    
    # Step 2: Code sign
    echo "  🔐 Code signing..."
    if [[ "$target" == *.app ]]; then
        if "$SCRIPT_DIR/simple-codesign.sh" "$target" "$CERT_IDENTITY" "$ENTITLEMENTS_FILE"; then
            echo "  ✅ Code signing completed"
        else
            echo "  ❌ Code signing failed"
            TARGET_SUCCESS=false
        fi
    elif [[ "$target" == *.pkg ]]; then
        echo "  📦 Package signing..."
        # Simple package signing
        INSTALLER_CERT=$(security find-identity -v -p codesigning | grep "Developer ID Installer" | head -1 | sed 's/.*) "\(.*\)"/\1/' || echo "")
        if [ -n "$INSTALLER_CERT" ]; then
            SIGNED_PKG="${target%.pkg}-signed.pkg"
            if productsign --sign "$INSTALLER_CERT" "$target" "$SIGNED_PKG"; then
                mv "$SIGNED_PKG" "$target"
                echo "  ✅ Package signed successfully"
            else
                echo "  ❌ Package signing failed"
                TARGET_SUCCESS=false
            fi
        else
            echo "  ⚠️  No Developer ID Installer certificate found, skipping package signing"
        fi
    fi
    
    # Step 3: Notarize (if not skipped and signing succeeded)
    if [ "$TARGET_SUCCESS" = true ] && [ "$SKIP_NOTARIZATION" = false ]; then
        echo "  📤 Notarizing..."
        if "$SCRIPT_DIR/simple-notarize.sh" "$target"; then
            echo "  ✅ Notarization completed"
        else
            echo "  ❌ Notarization failed"
            if [ "$BUILD_TYPE" != "dev" ]; then
                TARGET_SUCCESS=false
            else
                echo "  ℹ️  Continuing anyway (dev build)"
            fi
        fi
    elif [ "$SKIP_NOTARIZATION" = true ]; then
        echo "  ⏭️  Skipping notarization"
    fi
    
    # Update counters
    if [ "$TARGET_SUCCESS" = true ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        echo "  🎉 $(basename "$target") processed successfully!"
    else
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        echo "  💥 $(basename "$target") processing failed!"
    fi
done

# Cleanup
rm -f "$ENTITLEMENTS_FILE"

# Final summary
echo ""
echo "📊 Final Summary"
echo "  ✅ Successful: $SUCCESS_COUNT"
echo "  ❌ Failed: $FAILURE_COUNT"
echo "  📁 Total: ${#TARGETS[@]}"

if [ $FAILURE_COUNT -eq 0 ]; then
    echo "🎉 All targets processed successfully!"
    exit 0
else
    echo "💥 Some targets failed processing"
    exit 1
fi
