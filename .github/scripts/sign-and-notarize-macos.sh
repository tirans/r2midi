#!/bin/bash
set -euo pipefail

# Sign and notarize macOS applications following Apple's requirements
# Usage: sign-and-notarize-macos.sh <version> <build_type> <apple_id> <apple_id_password> <team_id>

VERSION="${1:-1.0.0}"
BUILD_TYPE="${2:-production}"
APPLE_ID="${3}"
APPLE_ID_PASSWORD="${4}"
TEAM_ID="${5}"

echo "🍎 Starting macOS signing and notarization process..."
echo "Version: $VERSION"
echo "Build Type: $BUILD_TYPE"
echo "Team ID: $TEAM_ID"

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
    echo "Required: APPLE_ID, APPLE_ID_PASSWORD, TEAM_ID"
    exit 1
fi

# Validate signing identity
if [ -z "${APPLICATION_SIGNING_IDENTITY:-}" ]; then
    echo "❌ Error: No application signing identity found"
    exit 1
fi

echo "📋 Using application signing identity: $APPLICATION_SIGNING_IDENTITY"
if [ -n "${INSTALLER_SIGNING_IDENTITY:-}" ]; then
    echo "📋 Using installer signing identity: $INSTALLER_SIGNING_IDENTITY"
fi

# Find entitlements file
ENTITLEMENTS_FILE=""
if [ -f "entitlements.plist" ]; then
    ENTITLEMENTS_FILE="entitlements.plist"
elif [ -f "build/r2midi-client/macos/app/Entitlements.plist" ]; then
    ENTITLEMENTS_FILE="build/r2midi-client/macos/app/Entitlements.plist"
else
    echo "⚠️ Warning: No entitlements file found, signing without entitlements"
fi

if [ -n "$ENTITLEMENTS_FILE" ]; then
    echo "📋 Using entitlements file: $ENTITLEMENTS_FILE"
fi

# Function to get bundle ID from Info.plist
get_bundle_id() {
    local app_path="$1"
    local info_plist="$app_path/Contents/Info.plist"
    
    if [ -f "$info_plist" ]; then
        /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$info_plist" 2>/dev/null || echo "com.r2midi.app"
    else
        echo "com.r2midi.app"
    fi
}

# Function to sign an application bundle using inside-out approach
sign_app_bundle() {
    local app_path="$1"
    local app_name=$(basename "$app_path")
    
    echo "🔐 Signing $app_name using inside-out approach..."
    
    if [ ! -d "$app_path" ]; then
        echo "❌ Error: App bundle not found: $app_path"
        return 1
    fi
    
    local bundle_id=$(get_bundle_id "$app_path")
    echo "📋 Bundle ID: $bundle_id"
    
    # Step 1: Remove any existing signatures
    echo "🧹 Removing existing signatures..."
    find "$app_path" -name "_CodeSignature" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Step 2: Sign all dynamic libraries and frameworks (inside-out)
    echo "📦 Signing embedded libraries and frameworks..."
    
    # Sign .dylib and .so files
    find "$app_path" -type f \( -name "*.dylib" -o -name "*.so" \) | while read lib; do
        if [ -f "$lib" ]; then
            echo "🔗 Signing library: $(basename "$lib")"
            codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp "$lib" || echo "⚠️ Warning: Failed to sign $(basename "$lib")"
        fi
    done
    
    # Sign frameworks (deepest first)
    find "$app_path" -name "*.framework" -type d | sort -r | while read framework; do
        if [ -d "$framework" ]; then
            echo "🔗 Signing framework: $(basename "$framework")"
            codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp "$framework" || echo "⚠️ Warning: Failed to sign $(basename "$framework")"
        fi
    done
    
    # Step 3: Sign nested applications
    find "$app_path" -name "*.app" -not -path "$app_path" | while read nested_app; do
        if [ -d "$nested_app" ]; then
            echo "📱 Signing nested app: $(basename "$nested_app")"
            if [ -n "$ENTITLEMENTS_FILE" ]; then
                codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp --entitlements "$ENTITLEMENTS_FILE" "$nested_app" || echo "⚠️ Warning: Failed to sign $(basename "$nested_app")"
            else
                codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp "$nested_app" || echo "⚠️ Warning: Failed to sign $(basename "$nested_app")"
            fi
        fi
    done
    
    # Step 4: Sign executables in Contents/MacOS
    if [ -d "$app_path/Contents/MacOS" ]; then
        find "$app_path/Contents/MacOS" -type f -perm +111 | while read executable; do
            if [ -f "$executable" ] && file "$executable" | grep -q "Mach-O"; then
                echo "⚡ Signing executable: $(basename "$executable")"
                codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp "$executable" || echo "⚠️ Warning: Failed to sign $(basename "$executable")"
            fi
        done
    fi
    
    # Step 5: Sign the main app bundle (outermost layer)
    echo "🎯 Signing main app bundle: $app_name"
    if [ -n "$ENTITLEMENTS_FILE" ]; then
        codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp --entitlements "$ENTITLEMENTS_FILE" "$app_path"
    else
        codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp "$app_path"
    fi
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to sign app bundle: $app_name"
        return 1
    fi
    
    # Step 6: Verify the signature
    echo "✅ Verifying signature for $app_name..."
    codesign --verify --deep --strict --verbose=2 "$app_path"
    if [ $? -ne 0 ]; then
        echo "❌ Signature verification failed for $app_name"
        return 1
    fi
    
    # Check Gatekeeper compatibility
    echo "🔍 Checking Gatekeeper compatibility..."
    spctl --assess --type exec --verbose "$app_path" || echo "⚠️ Warning: Gatekeeper assessment failed (may pass after notarization)"
    
    echo "✅ Successfully signed $app_name"
    return 0
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
    
    # Add README if it exists
    if [ -f "README.md" ]; then
        cp README.md "$dmg_contents/README.txt"
    fi
    
    # Create the DMG using hdiutil (more reliable than create-dmg)
    echo "📦 Creating disk image..."
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
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to sign DMG"
        return 1
    fi
    
    echo "✅ Created and signed DMG: $dmg_name"
    return 0
}

# Function to create a PKG installer
create_pkg() {
    local app_path="$1"
    local app_name=$(basename "$app_path" .app)
    local pkg_name="$app_name-$VERSION.pkg"
    
    if [ -z "${INSTALLER_SIGNING_IDENTITY:-}" ]; then
        echo "⚠️ Warning: No installer signing identity available, skipping PKG creation"
        return 1
    fi
    
    echo "📦 Creating PKG installer for $app_name..."
    
    # Create temporary directory for PKG contents
    local temp_pkg_dir=$(mktemp -d)
    local pkg_root="$temp_pkg_dir/pkg_root/Applications"
    mkdir -p "$pkg_root"
    
    # Copy app to PKG root
    cp -R "$app_path" "$pkg_root/"
    
    # Get bundle ID for package identifier
    local bundle_id=$(get_bundle_id "$app_path")
    local pkg_identifier="${bundle_id}.pkg"
    
    # Create the PKG
    pkgbuild --root "$temp_pkg_dir/pkg_root" \
             --install-location "/" \
             --sign "$INSTALLER_SIGNING_IDENTITY" \
             --identifier "$pkg_identifier" \
             --version "$VERSION" \
             "$pkg_name"
    
    local result=$?
    
    # Clean up temporary directory
    rm -rf "$temp_pkg_dir"
    
    if [ $result -ne 0 ]; then
        echo "❌ Failed to create PKG"
        return 1
    fi
    
    echo "✅ Created signed PKG: $pkg_name"
    return 0
}

# Function to notarize a file
notarize_file() {
    local file_path="$1"
    local file_name=$(basename "$file_path")
    
    echo "📤 Submitting $file_name for notarization..."
    
    # Submit for notarization using notarytool
    local submit_output
    submit_output=$(xcrun notarytool submit "$file_path" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_ID_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait \
        --timeout 30m \
        2>&1)
    
    local exit_code=$?
    echo "Notarization output:"
    echo "$submit_output"
    
    # Check if notarization was successful
    if [ $exit_code -eq 0 ] && echo "$submit_output" | grep -q "status: Accepted"; then
        echo "✅ Notarization successful for $file_name"
        
        # Staple the notarization ticket
        echo "📎 Stapling notarization ticket..."
        xcrun stapler staple "$file_path"
        
        if [ $? -eq 0 ]; then
            echo "✅ Successfully stapled $file_name"
            
            # Verify stapling
            echo "🔍 Verifying stapled ticket..."
            xcrun stapler validate "$file_path"
            
            # Final Gatekeeper check
            echo "🔍 Final Gatekeeper assessment..."
            spctl --assess --type install "$file_path" && echo "✅ Gatekeeper accepts $file_name"
            
        else
            echo "⚠️ Warning: Failed to staple $file_name, but notarization succeeded"
        fi
        
        return 0
    else
        echo "❌ Notarization failed for $file_name"
        
        # Try to extract submission ID for detailed log
        local submission_id
        submission_id=$(echo "$submit_output" | grep -o 'id: [a-f0-9-]*' | cut -d' ' -f2 | head -1)
        
        if [ -n "$submission_id" ]; then
            echo "📋 Getting detailed notarization log for submission: $submission_id"
            xcrun notarytool log "$submission_id" \
                --apple-id "$APPLE_ID" \
                --password "$APPLE_ID_PASSWORD" \
                --team-id "$TEAM_ID"
        fi
        
        return 1
    fi
}

# Main signing and notarization workflow
echo "🔍 Looking for built applications..."

# Ensure artifacts directory exists
mkdir -p artifacts

# Track successful and failed operations
declare -a successful_dmgs=()
declare -a successful_pkgs=()
declare -a failed_items=()

# Process each application type
for app_type in "server" "r2midi-client"; do
    app_dir="dist/$app_type"
    
    if [ -d "$app_dir" ]; then
        echo "📁 Processing app type: $app_type"
        
        # Find the .app bundle
        app_bundle=$(find "$app_dir" -name "*.app" -type d | head -1)
        
        if [ -n "$app_bundle" ] && [ -d "$app_bundle" ]; then
            echo "📱 Found app bundle: $app_bundle"
            
            # Step 1: Sign the app bundle
            if sign_app_bundle "$app_bundle"; then
                echo "✅ Successfully signed: $app_bundle"
                
                # Step 2: Create and sign DMG
                if create_dmg "$app_bundle"; then
                    dmg_file="$(basename "$app_bundle" .app)-$VERSION.dmg"
                    
                    # Step 3: Notarize the DMG
                    if notarize_file "$dmg_file"; then
                        # Move to artifacts
                        mv "$dmg_file" artifacts/
                        successful_dmgs+=("$dmg_file")
                        echo "✅ DMG ready: artifacts/$dmg_file"
                    else
                        failed_items+=("DMG for $app_type")
                        echo "❌ Failed to notarize DMG for $app_type"
                    fi
                else
                    failed_items+=("DMG creation for $app_type")
                    echo "❌ Failed to create DMG for $app_type"
                fi
                
                # Step 4: Create PKG installer (for production builds)
                if [ "$BUILD_TYPE" = "production" ] && [ -n "${INSTALLER_SIGNING_IDENTITY:-}" ]; then
                    if create_pkg "$app_bundle"; then
                        pkg_file="$(basename "$app_bundle" .app)-$VERSION.pkg"
                        
                        # Notarize the PKG
                        if notarize_file "$pkg_file"; then
                            # Move to artifacts
                            mv "$pkg_file" artifacts/
                            successful_pkgs+=("$pkg_file")
                            echo "✅ PKG ready: artifacts/$pkg_file"
                        else
                            failed_items+=("PKG for $app_type")
                            echo "❌ Failed to notarize PKG for $app_type"
                        fi
                    else
                        failed_items+=("PKG creation for $app_type")
                        echo "❌ Failed to create PKG for $app_type"
                    fi
                fi
                
            else
                failed_items+=("Signing for $app_type")
                echo "❌ Failed to sign: $app_bundle"
            fi
            
        else
            echo "⚠️ Warning: No .app bundle found for $app_type in $app_dir"
            failed_items+=("No app bundle for $app_type")
        fi
    else
        echo "⚠️ Warning: No dist directory found for $app_type"
        failed_items+=("No dist directory for $app_type")
    fi
done

# Create comprehensive signing report
cat > artifacts/SIGNING_REPORT.txt << EOF
macOS Signing and Notarization Report
====================================

Build Information:
- Version: $VERSION
- Build Type: $BUILD_TYPE
- Application Signing Identity: $APPLICATION_SIGNING_IDENTITY
$([ -n "${INSTALLER_SIGNING_IDENTITY:-}" ] && echo "- Installer Signing Identity: $INSTALLER_SIGNING_IDENTITY" || echo "- Installer Signing Identity: Not available")
- Team ID: $TEAM_ID
- Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

Signing Configuration:
- Method: Apple Developer ID (inside-out signing)
- Runtime: Hardened Runtime enabled
- Entitlements: $([ -n "$ENTITLEMENTS_FILE" ] && echo "$ENTITLEMENTS_FILE" || echo "None")
- Notarization: Apple Notary Service with stapling
- Tool: xcrun notarytool

Successfully Created:
EOF

# Add successful items to report
if [ ${#successful_dmgs[@]} -gt 0 ]; then
    echo "DMG Files:" >> artifacts/SIGNING_REPORT.txt
    for dmg in "${successful_dmgs[@]}"; do
        if [ -f "artifacts/$dmg" ]; then
            size=$(du -h "artifacts/$dmg" | cut -f1)
            echo "  ✅ $dmg ($size)" >> artifacts/SIGNING_REPORT.txt
        fi
    done
fi

if [ ${#successful_pkgs[@]} -gt 0 ]; then
    echo "PKG Files:" >> artifacts/SIGNING_REPORT.txt
    for pkg in "${successful_pkgs[@]}"; do
        if [ -f "artifacts/$pkg" ]; then
            size=$(du -h "artifacts/$pkg" | cut -f1)
            echo "  ✅ $pkg ($size)" >> artifacts/SIGNING_REPORT.txt
        fi
    done
fi

# Add failed items to report
if [ ${#failed_items[@]} -gt 0 ]; then
    echo "" >> artifacts/SIGNING_REPORT.txt
    echo "Failed Operations:" >> artifacts/SIGNING_REPORT.txt
    for item in "${failed_items[@]}"; do
        echo "  ❌ $item" >> artifacts/SIGNING_REPORT.txt
    done
fi

# Add verification commands
cat >> artifacts/SIGNING_REPORT.txt << EOF

Verification Commands:
- Signature check: codesign --verify --deep --strict --verbose=2 <app>
- Gatekeeper check: spctl --assess --type exec --verbose <app>
- Notarization check: spctl --assess --type install --verbose <dmg/pkg>
- Stapling check: xcrun stapler validate <dmg/pkg>
EOF

echo ""
echo "✅ macOS signing and notarization process complete!"
echo "📋 Summary:"
echo "  - Successful DMGs: ${#successful_dmgs[@]}"
echo "  - Successful PKGs: ${#successful_pkgs[@]}"
echo "  - Failed operations: ${#failed_items[@]}"
echo ""
echo "📋 Full report available at: artifacts/SIGNING_REPORT.txt"

# Exit with error if any critical operations failed
if [ ${#failed_items[@]} -gt 0 ]; then
    echo "⚠️ Some operations failed. Check the report for details."
    exit 1
fi
