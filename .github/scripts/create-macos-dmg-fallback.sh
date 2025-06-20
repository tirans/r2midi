#!/bin/bash
set -euo pipefail

# Create signed and notarized macOS .dmg files (fallback when PKG creation isn't possible)
# Usage: create-macos-dmg-fallback.sh <version> <build_type> <apple_id> <apple_id_password> <team_id>

VERSION="${1:-1.0.0}"
BUILD_TYPE="${2:-production}"
APPLE_ID="${3}"
APPLE_ID_PASSWORD="${4}"
TEAM_ID="${5}"

echo "💽 Creating signed and notarized macOS .dmg files (PKG fallback)..."
echo "Version: $VERSION"
echo "Build Type: $BUILD_TYPE"
echo "Team ID: $TEAM_ID"
echo "Note: This is a fallback when Developer ID Installer certificate is not available"

# Load signing identities from certificate setup
if [ -f "/tmp/signing_identities.sh" ]; then
    source /tmp/signing_identities.sh
    echo "📋 Loaded signing identities from certificate setup"
else
    echo "❌ Error: Certificate setup not found. Run setup-certificates.sh first"
    exit 1
fi

# Validate required environment
if [ -z "$APPLE_ID" ] || [ -z "$APPLE_ID_PASSWORD" ] || [ -z "$TEAM_ID" ]; then
    echo "❌ Error: Missing required Apple credentials"
    exit 1
fi

if [ -z "${APPLICATION_SIGNING_IDENTITY:-}" ]; then
    echo "❌ Error: No application signing identity found"
    exit 1
fi

echo "📋 Application signing identity: $APPLICATION_SIGNING_IDENTITY"
echo "ℹ️ PKG creation skipped (no installer certificate)"

# Find entitlements file
ENTITLEMENTS_FILE=""
if [ -f "entitlements.plist" ]; then
    ENTITLEMENTS_FILE="entitlements.plist"
elif [ -f "build/r2midi-client/macos/app/Entitlements.plist" ]; then
    ENTITLEMENTS_FILE="build/r2midi-client/macos/app/Entitlements.plist"
fi

# Function to sign an application bundle
sign_app_bundle() {
    local app_path="$1"
    local app_name=$(basename "$app_path")
    
    echo "🔐 Signing $app_name..."
    
    if [ ! -d "$app_path" ]; then
        echo "❌ Error: App bundle not found: $app_path"
        return 1
    fi
    
    # Sign with entitlements if available
    if [ -n "$ENTITLEMENTS_FILE" ]; then
        codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp --entitlements "$ENTITLEMENTS_FILE" "$app_path"
    else
        codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp "$app_path"
    fi
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully signed $app_name"
        return 0
    else
        echo "❌ Failed to sign $app_name"
        return 1
    fi
}

# Function to create a DMG
create_dmg() {
    local app_path="$1"
    local app_name=$(basename "$app_path" .app)
    local dmg_name="$app_name-$VERSION.dmg"
    
    echo "💽 Creating DMG for $app_name..."
    
    # Create temporary directory for DMG contents
    local temp_dmg_dir=$(mktemp -d)
    local dmg_contents="$temp_dmg_dir/dmg_contents"
    mkdir -p "$dmg_contents"
    
    # Copy app to DMG contents
    cp -R "$app_path" "$dmg_contents/"
    
    # Create Applications symlink
    ln -s /Applications "$dmg_contents/Applications"
    
    # Add installation instructions
    cat > "$dmg_contents/INSTALL_INSTRUCTIONS.txt" << EOF
Installation Instructions
========================

1. Drag the application to the Applications folder
2. Launch from Applications folder
3. Right-click and select "Open" if you see security warnings

Note: This app is signed but distributed via DMG instead of PKG installer.
EOF
    
    # Create the DMG
    hdiutil create -format UDZO -srcfolder "$dmg_contents" -volname "$app_name $VERSION" "$dmg_name"
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to create DMG"
        rm -rf "$temp_dmg_dir"
        return 1
    fi
    
    # Clean up temporary directory
    rm -rf "$temp_dmg_dir"
    
    # Sign the DMG
    echo "🔐 Signing DMG: $dmg_name"
    codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --timestamp "$dmg_name"
    
    if [ $? -eq 0 ]; then
        echo "✅ Created and signed DMG: $dmg_name"
        return 0
    else
        echo "❌ Failed to sign DMG"
        return 1
    fi
}

# Function to notarize a file
notarize_file() {
    local file_path="$1"
    local file_name=$(basename "$file_path")
    
    echo "📤 Submitting $file_name for notarization..."
    
    # Submit for notarization
    local submit_output
    submit_output=$(xcrun notarytool submit "$file_path" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_ID_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait \
        --timeout 30m \
        2>&1)
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] && echo "$submit_output" | grep -q "status: Accepted"; then
        echo "✅ Notarization successful for $file_name"
        
        # Staple the ticket
        xcrun stapler staple "$file_path"
        echo "✅ Successfully stapled $file_name"
        return 0
    else
        echo "❌ Notarization failed for $file_name"
        return 1
    fi
}

# Main workflow
echo "🔍 Looking for built applications..."
mkdir -p artifacts

declare -a successful_dmgs=()
declare -a failed_items=()

# Find all .app bundles wherever they are (same logic as PKG script)
echo "🔍 Searching for .app bundles in any location..."
app_bundles=()
while IFS= read -r -d '' app; do
    app_bundles+=("$app")
done < <(find . -name "*.app" -type d -print0 2>/dev/null)

if [ ${#app_bundles[@]} -eq 0 ]; then
    echo "❌ Error: No .app bundles found anywhere"
    echo "Briefcase may have failed to build the applications"
    failed_items+=("No .app bundles found")
else
    echo "✅ Found ${#app_bundles[@]} .app bundle(s):"
    for app in "${app_bundles[@]}"; do
        echo "  - $app"
    done
    echo ""
fi

# Process each found .app bundle
for app_bundle in "${app_bundles[@]}"; do
    if [ -d "$app_bundle" ]; then
        app_name=$(basename "$app_bundle" .app)
        echo "📱 Processing app bundle: $app_name ($app_bundle)"
        
        # Sign and create DMG
        if sign_app_bundle "$app_bundle"; then
            if create_dmg "$app_bundle"; then
                dmg_file="$app_name-$VERSION.dmg"
                
                if notarize_file "$dmg_file"; then
                    mv "$dmg_file" artifacts/
                    successful_dmgs+=("$dmg_file")
                    echo "✅ DMG ready: artifacts/$dmg_file"
                else
                    failed_items+=("DMG notarization for $app_name")
                fi
            else
                failed_items+=("DMG creation for $app_name")
            fi
        else
            failed_items+=("Signing for $app_name")
        fi
    fi
done

# Create report
cat > artifacts/DMG_FALLBACK_REPORT.txt << EOF
macOS DMG Fallback Report
========================

Version: $VERSION
Build Type: $BUILD_TYPE
Distribution Method: DMG files (PKG fallback)
Reason: No Developer ID Installer certificate available
Application Signing: $APPLICATION_SIGNING_IDENTITY
Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

Successfully Created DMG Files:
EOF

if [ ${#successful_dmgs[@]:-0} -gt 0 ]; then
    for dmg in "${successful_dmgs[@]}"; do
        if [ -f "artifacts/$dmg" ]; then
            size=$(du -h "artifacts/$dmg" | cut -f1)
            echo "  ✅ $dmg ($size) - Signed and notarized" >> artifacts/DMG_FALLBACK_REPORT.txt
        fi
    done
else
    echo "  ❌ No DMG files created successfully" >> artifacts/DMG_FALLBACK_REPORT.txt
fi

if [ ${#failed_items[@]:-0} -gt 0 ]; then
    echo "" >> artifacts/DMG_FALLBACK_REPORT.txt
    echo "Failed Operations:" >> artifacts/DMG_FALLBACK_REPORT.txt
    for item in "${failed_items[@]}"; do
        echo "  ❌ $item" >> artifacts/DMG_FALLBACK_REPORT.txt
    done
fi

cat >> artifacts/DMG_FALLBACK_REPORT.txt << EOF

Installation Instructions for Users:
===================================

DMG Installation:
1. Download the .dmg file
2. Double-click to mount the disk image
3. Drag application to Applications folder
4. Eject the disk image
5. Launch from Applications folder

Note: These are signed and notarized DMG files, but PKG installers
would provide a better user experience if you have a Developer ID
Installer certificate.

To Upgrade to PKG Distribution:
1. Obtain Developer ID Installer certificate from Apple
2. Add it to your GitHub secrets as APPLE_DEVELOPER_ID_INSTALLER_CERT
3. Use create-macos-pkg.sh instead of this fallback script
EOF

echo ""
echo "✅ macOS DMG fallback creation complete!"
echo "📋 Summary:"
echo "  - DMG Files: ${#successful_dmgs[@]:-0}"
echo "  - Failed operations: ${#failed_items[@]:-0}"
echo ""
echo "📁 Available DMG files:"
if [ ${#successful_dmgs[@]:-0} -gt 0 ]; then
    for dmg in "${successful_dmgs[@]}"; do
        if [ -f "artifacts/$dmg" ]; then
            size=$(du -h "artifacts/$dmg" | cut -f1)
            echo "  💽 $dmg ($size)"
        fi
    done
else
    echo "  No DMG files were created"
fi
echo ""
echo "📋 Report: artifacts/DMG_FALLBACK_REPORT.txt"

# Exit with error if any operations failed
if [ ${#failed_items[@]:-0} -gt 0 ]; then
    echo "❌ Some operations failed."
    exit 1
fi
