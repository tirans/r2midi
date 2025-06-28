#!/bin/bash
# notarize.sh - Notarization script

set -euo pipefail

TARGET="$1"
APPLE_ID="${2:-${APPLE_ID:-}}"
APPLE_PASSWORD="${3:-${APPLE_ID_PASSWORD:-}}"
TEAM_ID="${4:-${APPLE_TEAM_ID:-}}"

if [ ! -e "$TARGET" ]; then
    echo "❌ Target not found: $TARGET"
    exit 1
fi

if [ -z "$APPLE_ID" ] || [ -z "$APPLE_PASSWORD" ]; then
    echo "⚠️  Skipping notarization - Apple ID credentials not available"
    echo "  Set APPLE_ID and APPLE_ID_PASSWORD environment variables for notarization"
    exit 0
fi

echo "📤 Notarizing: $(basename "$TARGET")"

# Prepare the file for notarization
NOTARIZE_FILE="$TARGET"
TEMP_ZIP=""

if [[ "$TARGET" == *.app ]]; then
    # App bundles need to be zipped
    TEMP_ZIP="/tmp/$(basename "$TARGET" .app)-$(date +%s).zip"
    echo "  📁 Creating zip for notarization: $(basename "$TEMP_ZIP")"
    
    if ditto -c -k --keepParent "$TARGET" "$TEMP_ZIP"; then
        NOTARIZE_FILE="$TEMP_ZIP"
        echo "  ✅ Zip created successfully"
    else
        echo "  ❌ Failed to create zip"
        exit 1
    fi
fi

# Create bundle ID
BUNDLE_ID="com.r2midi.$(basename "$TARGET" | sed 's/\.[^.]*$//' | tr '[:upper:]' '[:lower:]' | tr ' ' '.')"
echo "  🏷️  Bundle ID: $BUNDLE_ID"

# Submit for notarization using notarytool (modern approach)
echo "  📤 Submitting for notarization..."

if command -v xcrun >/dev/null 2>&1 && xcrun notarytool --help >/dev/null 2>&1; then
    echo "  🔧 Using notarytool (recommended)"
    
    # Create temporary keychain profile
    PROFILE_NAME="r2midi-notarize-$(date +%s)"
    
    echo "  🔑 Creating keychain profile..."
    if xcrun notarytool store-credentials "$PROFILE_NAME" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        ${TEAM_ID:+--team-id "$TEAM_ID"} >/dev/null 2>&1; then
        
        echo "  ✅ Keychain profile created"
        
        echo "  ⏳ Submitting and waiting for notarization..."
        if xcrun notarytool submit "$NOTARIZE_FILE" \
            --keychain-profile "$PROFILE_NAME" \
            --wait 2>&1; then
            
            echo "  ✅ Notarization completed successfully"
            NOTARIZATION_SUCCESS=true
        else
            echo "  ❌ Notarization failed"
            NOTARIZATION_SUCCESS=false
        fi
        
        # Clean up keychain profile
        xcrun notarytool delete-credentials "$PROFILE_NAME" 2>/dev/null || true
    else
        echo "  ❌ Failed to create keychain profile"
        NOTARIZATION_SUCCESS=false
    fi
else
    echo "  ⚠️  notarytool not available, trying altool (legacy)"
    
    # Fallback to altool
    echo "  📤 Submitting with altool..."
    ALTOOL_OUTPUT=$(xcrun altool --notarize-app \
        --file "$NOTARIZE_FILE" \
        --primary-bundle-id "$BUNDLE_ID" \
        --username "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        ${TEAM_ID:+--asc-provider "$TEAM_ID"} 2>&1)
    
    if echo "$ALTOOL_OUTPUT" | grep -q "RequestUUID"; then
        REQUEST_UUID=$(echo "$ALTOOL_OUTPUT" | grep "RequestUUID" | awk '{print $NF}')
        echo "  📋 Submission ID: $REQUEST_UUID"
        echo "  ⏳ Waiting for notarization (this can take several minutes)..."
        
        # Wait for completion (simplified - just wait 5 minutes)
        sleep 300
        
        # Check status
        STATUS_OUTPUT=$(xcrun altool --notarization-info "$REQUEST_UUID" \
            --username "$APPLE_ID" \
            --password "$APPLE_PASSWORD" 2>&1)
        
        if echo "$STATUS_OUTPUT" | grep -q "Status: success"; then
            echo "  ✅ Notarization completed successfully"
            NOTARIZATION_SUCCESS=true
        else
            echo "  ❌ Notarization failed or still in progress"
            echo "  📋 Status: $STATUS_OUTPUT"
            NOTARIZATION_SUCCESS=false
        fi
    else
        echo "  ❌ Failed to submit for notarization"
        echo "  📋 Output: $ALTOOL_OUTPUT"
        NOTARIZATION_SUCCESS=false
    fi
fi

# Staple the notarization ticket if successful
if [ "$NOTARIZATION_SUCCESS" = true ]; then
    echo "  📎 Stapling notarization ticket..."
    if xcrun stapler staple "$TARGET" 2>/dev/null; then
        echo "  ✅ Notarization ticket stapled successfully"
    else
        echo "  ⚠️  Failed to staple ticket (app will still work)"
    fi
fi

# Clean up temporary zip
if [ -n "$TEMP_ZIP" ]; then
    rm -f "$TEMP_ZIP"
fi

if [ "$NOTARIZATION_SUCCESS" = true ]; then
    echo "🎉 Notarization completed successfully!"
    exit 0
else
    echo "❌ Notarization failed"
    exit 1
fi
