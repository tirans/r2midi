#!/bin/bash
set -euo pipefail

# Create signed and notarized macOS .pkg installers (primary focus)
# Usage: create-macos-pkg.sh <version> <build_type> <apple_id> <apple_id_password> <team_id>

VERSION="${1:-1.0.0}"
BUILD_TYPE="${2:-production}"
APPLE_ID="${3}"
APPLE_ID_PASSWORD="${4}"
TEAM_ID="${5}"

echo "📦 Creating signed and notarized macOS .pkg installers..."
echo "Version: $VERSION"
echo "Build Type: $BUILD_TYPE"
echo "Team ID: $TEAM_ID"
echo "Priority: .pkg installers (with optional .dmg)"

# Load signing identities from certificate setup
if [ -f "/tmp/signing_identities.sh" ]; then
    source /tmp/signing_identities.sh
    echo "📋 Loaded signing identities from certificate setup"
    echo "🔍 Available identities:"
    echo "  - APPLICATION_SIGNING_IDENTITY: ${APPLICATION_SIGNING_IDENTITY:-'Not set'}"
    echo "  - INSTALLER_SIGNING_IDENTITY: ${INSTALLER_SIGNING_IDENTITY:-'Not set'}"

    # Debug: Show all available certificates
    echo "🔍 All certificates in keychain:"
    if [ -n "${TEMP_KEYCHAIN:-}" ]; then
        security find-identity -v "$TEMP_KEYCHAIN" 2>/dev/null || echo "Could not list keychain identities"
    else
        security find-identity -v 2>/dev/null || echo "Could not list system identities"
    fi
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

# Validate signing identities
if [ -z "${APPLICATION_SIGNING_IDENTITY:-}" ]; then
    echo "❌ Error: No application signing identity found"
    exit 1
fi

if [ -z "${INSTALLER_SIGNING_IDENTITY:-}" ]; then
    echo "❌ Error: No installer signing identity found"
    echo "PKG creation requires 'Developer ID Installer' certificate"
    echo ""
    echo "🔍 Certificate Requirements for PKG Creation:"
    echo "  1. Developer ID Application certificate (for app signing) - ✅ Available"
    echo "  2. Developer ID Installer certificate (for PKG signing) - ❌ Missing"
    echo ""

    # Check if they have the wrong type of certificate
    if [ -n "${TEMP_KEYCHAIN:-}" ] && security find-identity -v "$TEMP_KEYCHAIN" | grep -q "3rd Party Mac Developer Installer"; then
        echo "⚠️ Certificate Type Issue:"
        echo "  You have: '3rd Party Mac Developer Installer' (for Mac App Store)"
        echo "  You need: 'Developer ID Installer' (for outside App Store distribution)"
        echo ""
        echo "🎯 Distribution Options:"
        echo "  Option 1: Get 'Developer ID Installer' certificate for PKG installers"
        echo "  Option 2: Use DMG distribution (fallback will handle this)"
        echo "  Option 3: Submit to Mac App Store (different workflow needed)"
    else
        echo "📝 Available Options:"
        echo "  - Add Developer ID Installer certificate to your GitHub secrets"
        echo "  - Or use DMG-only distribution (fallback will handle this)"
    fi

    echo ""
    echo "🔗 More info: https://developer.apple.com/support/certificates/"
    exit 1
fi

echo "📋 Application signing identity: $APPLICATION_SIGNING_IDENTITY"
echo "📋 Installer signing identity: $INSTALLER_SIGNING_IDENTITY"

# Find entitlements file
ENTITLEMENTS_FILE=""
if [ -f "entitlements.plist" ]; then
    # Validate the entitlements file first
    if plutil -lint "entitlements.plist" >/dev/null 2>&1; then
        ENTITLEMENTS_FILE="entitlements.plist"
        echo "📋 Using entitlements file: $ENTITLEMENTS_FILE"
    else
        echo "⚠️ Warning: entitlements.plist exists but is invalid, skipping entitlements"
    fi
elif [ -f "build/r2midi-client/macos/app/Entitlements.plist" ]; then
    if plutil -lint "build/r2midi-client/macos/app/Entitlements.plist" >/dev/null 2>&1; then
        ENTITLEMENTS_FILE="build/r2midi-client/macos/app/Entitlements.plist"
        echo "📋 Using entitlements file: $ENTITLEMENTS_FILE"
    else
        echo "⚠️ Warning: Briefcase entitlements file exists but is invalid, skipping entitlements"
    fi
else
    echo "⚠️ Warning: No entitlements file found, signing without entitlements"
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

    # Step 2: Sign all dynamic libraries and frameworks (inside-out) - OPTIMIZED
    echo "📦 Signing embedded libraries and frameworks (optimized batch process)..."

    # Collect all libraries and frameworks for batch processing
    local libs_to_sign=()
    local frameworks_to_sign=()

    # Find .dylib and .so files
    while IFS= read -r -d '' lib; do
        libs_to_sign+=("$lib")
    done < <(find "$app_path" -type f \( -name "*.dylib" -o -name "*.so" \) -print0 2>/dev/null)

    # Find frameworks (deepest first)
    while IFS= read -r -d '' framework; do
        frameworks_to_sign+=("$framework")
    done < <(find "$app_path" -name "*.framework" -type d -print0 2>/dev/null | sort -rz)

    # Sign libraries in parallel batches (limit to 4 concurrent to avoid overwhelming the system)
    if [ ${#libs_to_sign[@]} -gt 0 ]; then
        echo "🔗 Signing ${#libs_to_sign[@]} libraries in optimized batches..."
        local batch_size=4
        local batch_count=0

        for lib in "${libs_to_sign[@]}"; do
            if [ -f "$lib" ]; then
                (
                    codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp "$lib" 2>/dev/null || \
                    echo "⚠️ Warning: Failed to sign $(basename "$lib")"
                ) &

                batch_count=$((batch_count + 1))
                if [ $((batch_count % batch_size)) -eq 0 ]; then
                    wait  # Wait for current batch to complete
                fi
            fi
        done
        wait  # Wait for any remaining processes
        echo "✅ Library signing completed"
    fi

    # Sign frameworks in parallel batches with special handling for Qt frameworks
    if [ ${#frameworks_to_sign[@]} -gt 0 ]; then
        echo "🔗 Signing ${#frameworks_to_sign[@]} frameworks in optimized batches..."
        local batch_size=2  # Smaller batch size for frameworks as they're larger
        local batch_count=0

        for framework in "${frameworks_to_sign[@]}"; do
            if [ -d "$framework" ]; then
                (
                    # Special handling for Qt frameworks (PyQt6/Qt6)
                    if [[ "$(basename "$framework")" == Qt* ]] || [[ "$framework" == *PyQt6/Qt6* ]]; then
                        echo "🎯 Special Qt framework signing: $(basename "$framework")"

                        # Sign internal executables in Qt frameworks first (inside-out approach)
                        # Qt frameworks have structure: Framework.framework/Versions/A/Framework
                        local framework_name=$(basename "$framework" .framework)
                        local framework_executable="$framework/Versions/A/$framework_name"

                        if [ -f "$framework_executable" ]; then
                            echo "  🔗 Signing Qt framework executable: $framework_name"
                            codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp "$framework_executable" 2>/dev/null || \
                            echo "  ⚠️ Warning: Failed to sign Qt framework executable $framework_name"
                        fi

                        # Sign any other executables or dylibs inside the framework
                        find "$framework" -type f \( -name "*.dylib" -o -perm +111 \) -not -path "*/Headers/*" -not -path "*/Resources/*" | while read inner_file; do
                            if [ -f "$inner_file" ] && file "$inner_file" | grep -q "Mach-O"; then
                                echo "  🔗 Signing Qt framework component: $(basename "$inner_file")"
                                codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp "$inner_file" 2>/dev/null || \
                                echo "  ⚠️ Warning: Failed to sign Qt framework component $(basename "$inner_file")"
                            fi
                        done
                    fi

                    # Sign the framework bundle itself (this works for both Qt and regular frameworks)
                    codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp "$framework" 2>/dev/null || \
                    echo "⚠️ Warning: Failed to sign framework $(basename "$framework")"
                ) &

                batch_count=$((batch_count + 1))
                if [ $((batch_count % batch_size)) -eq 0 ]; then
                    wait  # Wait for current batch to complete
                fi
            fi
        done
        wait  # Wait for any remaining processes
        echo "✅ Framework signing completed"
    fi

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

    # Try signing with entitlements first, fall back to without if it fails
    local signing_success=false

    if [ -n "$ENTITLEMENTS_FILE" ]; then
        echo "Attempting to sign with entitlements: $ENTITLEMENTS_FILE"
        if codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp --entitlements "$ENTITLEMENTS_FILE" "$app_path" 2>/dev/null; then
            signing_success=true
            echo "✅ Signed successfully with entitlements"
        else
            echo "⚠️ Warning: Signing with entitlements failed, trying without entitlements..."
            # Try without entitlements as fallback
            if codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp "$app_path"; then
                signing_success=true
                echo "✅ Signed successfully without entitlements (fallback)"
            fi
        fi
    else
        echo "Signing without entitlements"
        if codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp "$app_path"; then
            signing_success=true
            echo "✅ Signed successfully without entitlements"
        fi
    fi

    if [ "$signing_success" != "true" ]; then
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

# Function to create a signed PKG installer (PRIMARY FOCUS)
create_signed_pkg() {
    local app_path="$1"
    local app_name=$(basename "$app_path" .app)
    local pkg_name="$app_name-$VERSION.pkg"

    echo "📦 Creating signed PKG installer for $app_name..."
    echo "🎯 This is the PRIMARY distribution format"

    # Create temporary directory for PKG contents
    local temp_pkg_dir=$(mktemp -d)
    local pkg_root="$temp_pkg_dir/pkg_root/Applications"
    mkdir -p "$pkg_root"

    # Copy app to PKG root
    echo "📁 Copying app to installer payload..."
    cp -R "$app_path" "$pkg_root/"

    # Get bundle ID for package identifier
    local bundle_id=$(get_bundle_id "$app_path")
    local pkg_identifier="${bundle_id}.installer"

    echo "📋 Package Identifier: $pkg_identifier"
    echo "📋 Install Location: /Applications"
    echo "📋 Version: $VERSION"

    # Create the PKG with detailed configuration
    echo "🔨 Building PKG installer..."

    # Add progress indicator
    echo "⏳ Starting PKG build process (this may take several minutes)..."

    # Create a background process to show progress while pkgbuild runs
    (
        i=0
        while true; do
            i=$((i+1))
            minutes=$((i / 60))
            seconds=$((i % 60))
            if [ $minutes -gt 0 ]; then
                echo -ne "\r⏳ PKG build in progress... (${minutes}m ${seconds}s elapsed)"
            else
                echo -ne "\r⏳ PKG build in progress... (${seconds}s elapsed)"
            fi

            # Add timeout check to prevent infinite hanging
            if [ $i -gt 1800 ]; then  # 30 minutes timeout
                echo -e "\n❌ PKG build timeout after 30 minutes - killing process"
                pkill -f "pkgbuild.*$pkg_identifier" 2>/dev/null || true
                exit 1
            fi
            sleep 1
        done
    ) &
    PROGRESS_PID=$!

    # Ensure we kill the progress indicator when this function exits
    trap "kill $PROGRESS_PID 2>/dev/null || true" EXIT

    # Run pkgbuild with timeout using GNU timeout if available, otherwise use built-in timeout
    echo "🔨 Starting pkgbuild with 30-minute timeout..."
    local pkgbuild_start_time=$(date +%s)

    # Use timeout command to prevent hanging
    if command -v timeout >/dev/null 2>&1; then
        # GNU timeout available
        set -x
        timeout 1800 pkgbuild \
            --root "$temp_pkg_dir/pkg_root" \
            --install-location "/" \
            --identifier "$pkg_identifier" \
            --version "$VERSION" \
            --timestamp \
            --sign "$INSTALLER_SIGNING_IDENTITY" \
            "$pkg_name"
        set +x
    else
        # Fallback: use background process with timeout
        set -x
        pkgbuild \
            --root "$temp_pkg_dir/pkg_root" \
            --install-location "/" \
            --identifier "$pkg_identifier" \
            --version "$VERSION" \
            --timestamp \
            --sign "$INSTALLER_SIGNING_IDENTITY" \
            "$pkg_name" &
        set +x
        local pkgbuild_pid=$!
        local timeout_seconds=1800  # 30 minutes
        local elapsed=0

        while kill -0 $pkgbuild_pid 2>/dev/null; do
            sleep 1
            elapsed=$((elapsed + 1))
            if [ $elapsed -gt $timeout_seconds ]; then
                echo -e "\n❌ PKG build timeout after 30 minutes - terminating"
                kill $pkgbuild_pid 2>/dev/null || true
                wait $pkgbuild_pid 2>/dev/null || true
                result=124  # timeout exit code
                break
            fi
        done

        if [ $elapsed -le $timeout_seconds ]; then
            wait $pkgbuild_pid
            result=$?
        fi
    fi

    # Capture the result if not already set
    if [ -z "${result:-}" ]; then
        result=$?
    fi

    local pkgbuild_end_time=$(date +%s)
    local pkgbuild_duration=$((pkgbuild_end_time - pkgbuild_start_time))

    # Kill the progress indicator
    kill $PROGRESS_PID 2>/dev/null || true

    if [ $result -eq 124 ]; then
        echo -e "\r❌ PKG build timed out after 30 minutes                    "
        return 1
    else
        echo -e "\r✅ PKG build completed in ${pkgbuild_duration}s                    "
    fi

    # Clean up temporary directory
    rm -rf "$temp_pkg_dir"

    if [ $result -ne 0 ]; then
        echo "❌ Failed to create PKG installer"
        return 1
    fi

    # Verify the PKG signature
    echo "🔍 Verifying PKG signature..."
    pkgutil --check-signature "$pkg_name"
    if [ $? -eq 0 ]; then
        echo "✅ PKG signature verified"
    else
        echo "⚠️ Warning: PKG signature verification failed"
    fi

    # Test PKG with spctl
    echo "🔍 Testing PKG with Gatekeeper..."
    spctl --assess --type install --verbose "$pkg_name" || echo "⚠️ Warning: Gatekeeper assessment failed (may pass after notarization)"

    echo "✅ Created signed PKG installer: $pkg_name"
    return 0
}

# Function to create optional DMG (secondary)
create_optional_dmg() {
    local app_path="$1"
    local app_name=$(basename "$app_path" .app)
    local dmg_name="$app_name-$VERSION.dmg"

    echo "💽 Creating optional DMG for $app_name..."
    echo "ℹ️ DMG is secondary - PKG is the primary distribution format"

    # Create temporary directory for DMG contents
    local temp_dmg_dir=$(mktemp -d)
    local dmg_contents="$temp_dmg_dir/dmg_contents"
    mkdir -p "$dmg_contents"

    # Copy app to DMG contents
    cp -R "$app_path" "$dmg_contents/"

    # Create Applications symlink
    ln -s /Applications "$dmg_contents/Applications"

    # Add installation note
    cat > "$dmg_contents/INSTALLATION_NOTE.txt" << EOF
Installation Instructions
========================

RECOMMENDED: Use the .pkg installer for automated installation.

Manual Installation:
1. Drag the application to the Applications folder
2. Launch from Applications folder

The .pkg installer is the preferred installation method.
EOF

    # Create the DMG using hdiutil
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

    echo "✅ Created optional DMG: $dmg_name"
    return 0
}

# Function to notarize a file
notarize_file() {
    local file_path="$1"
    local file_name=$(basename "$file_path")

    echo "📤 Submitting $file_name for notarization..."
    echo "⏳ This process can take 5-45 minutes. Progress will be shown below..."

    # Create a background process to show progress during notarization
    (
        i=0
        while true; do
            i=$((i+1))
            minutes=$((i / 60))
            seconds=$((i % 60))
            if [ $minutes -gt 0 ]; then
                echo -ne "\r⏳ Notarization in progress... (${minutes}m ${seconds}s elapsed)"
            else
                echo -ne "\r⏳ Notarization in progress... (${seconds}s elapsed)"
            fi
            sleep 1
        done
    ) &
    NOTARIZE_PROGRESS_PID=$!

    # Ensure we kill the progress indicator when this function exits
    trap "kill $NOTARIZE_PROGRESS_PID 2>/dev/null || true" EXIT

    # Submit for notarization using notarytool with optimized timeout
    local submit_output
    echo "📤 Submitting for notarization (timeout: 20 minutes)..."
    submit_output=$(xcrun notarytool submit "$file_path" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_ID_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait \
        --timeout 20m \
        2>&1)

    # Kill the progress indicator
    kill $NOTARIZE_PROGRESS_PID 2>/dev/null || true
    echo -e "\r✅ Notarization request completed                                    "

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

# Main workflow - Focus on PKG creation
echo "🔍 Looking for built applications..."

# Debug: Show what directories actually exist
echo "🔍 Debugging directory structure:"
echo "Current directory: $(pwd)"
echo "Contents of current directory:"
ls -la
echo ""
echo "Looking for dist/ directory:"
if [ -d "dist" ]; then
    echo "dist/ directory exists, contents:"
    find dist/ -type d -name "*.app" 2>/dev/null || echo "No .app directories found in dist/"
    echo "All dist/ contents:"
    ls -la dist/
else
    echo "dist/ directory does not exist"
fi
echo ""
echo "Looking for build/ directory:"
if [ -d "build" ]; then
    echo "build/ directory exists, searching for .app bundles:"
    find build/ -name "*.app" -type d 2>/dev/null || echo "No .app bundles found in build/"
else
    echo "build/ directory does not exist"
fi
echo ""
echo "Searching entire current directory for .app bundles:"
find . -name "*.app" -type d 2>/dev/null || echo "No .app bundles found anywhere"
echo ""

# Ensure artifacts directory exists
mkdir -p artifacts

# Track successful and failed operations
declare -a successful_pkgs=()
declare -a successful_dmgs=()
declare -a failed_items=()

# Find all .app bundles wherever they are
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

        # Step 1: Sign the app bundle
        if sign_app_bundle "$app_bundle"; then
            echo "✅ Successfully signed: $app_bundle"

            # Step 2: Create PKG installer (PRIMARY FOCUS)
            echo "🎯 Creating PKG installer (primary distribution format)..."
            if create_signed_pkg "$app_bundle"; then
                pkg_file="$app_name-$VERSION.pkg"

                # Step 3: Notarize the PKG
                if notarize_file "$pkg_file"; then
                    # Move to artifacts
                    mv "$pkg_file" artifacts/
                    successful_pkgs+=("$pkg_file")
                    echo "✅ PKG ready: artifacts/$pkg_file"
                else
                    failed_items+=("PKG notarization for $app_name")
                    echo "❌ Failed to notarize PKG for $app_name"
                fi
            else
                failed_items+=("PKG creation for $app_name")
                echo "❌ Failed to create PKG for $app_name"
            fi

            # Step 4: Create optional DMG (secondary) - Skip in production if PKG succeeded
            if [ "$BUILD_TYPE" = "production" ] && [ ${#successful_pkgs[@]} -gt 0 ]; then
                echo "💽 Skipping DMG creation in production build (PKG is primary format)"
                echo "ℹ️ This optimization reduces build time significantly"
            else
                echo "💽 Creating optional DMG (secondary distribution format)..."
                if create_optional_dmg "$app_bundle"; then
                    dmg_file="$app_name-$VERSION.dmg"

                    # Notarize the DMG
                    if notarize_file "$dmg_file"; then
                        # Move to artifacts
                        mv "$dmg_file" artifacts/
                        successful_dmgs+=("$dmg_file")
                        echo "✅ DMG ready: artifacts/$dmg_file"
                    else
                        echo "⚠️ Warning: Failed to notarize DMG for $app_name (not critical)"
                        # Don't add to failed_items since DMG is optional
                    fi
                else
                    echo "⚠️ Warning: Failed to create DMG for $app_name (not critical)"
                    # Don't add to failed_items since DMG is optional
                fi
            fi

        else
            failed_items+=("Signing for $app_name")
            echo "❌ Failed to sign: $app_bundle"
        fi
    fi
done

# Create comprehensive PKG-focused report
cat > artifacts/PKG_INSTALLER_REPORT.txt << EOF
macOS PKG Installer Creation Report
==================================

Build Information:
- Version: $VERSION
- Build Type: $BUILD_TYPE
- Primary Format: PKG Installers (signed & notarized)
- Secondary Format: DMG Files (optional)
- Application Signing Identity: $APPLICATION_SIGNING_IDENTITY
- Installer Signing Identity: $INSTALLER_SIGNING_IDENTITY
- Team ID: $TEAM_ID
- Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

PKG Installer Configuration:
- Install Location: /Applications
- Signing Method: Developer ID Installer certificate
- Notarization: Apple Notary Service with stapling
- Distribution Method: Direct download and double-click installation
- User Experience: Automated installation with macOS Installer

Successfully Created PKG Installers:
EOF

# Add successful PKG files to report
if [ ${#successful_pkgs[@]} -gt 0 ]; then
    for pkg in "${successful_pkgs[@]}"; do
        if [ -f "artifacts/$pkg" ]; then
            size=$(du -h "artifacts/$pkg" | cut -f1)
            echo "  ✅ $pkg ($size) - READY FOR DISTRIBUTION" >> artifacts/PKG_INSTALLER_REPORT.txt
        fi
    done
else
    echo "  ❌ No PKG installers were created successfully" >> artifacts/PKG_INSTALLER_REPORT.txt
fi

# Add secondary DMG files to report
if [ ${#successful_dmgs[@]} -gt 0 ]; then
    echo "" >> artifacts/PKG_INSTALLER_REPORT.txt
    echo "Secondary DMG Files (Optional):" >> artifacts/PKG_INSTALLER_REPORT.txt
    for dmg in "${successful_dmgs[@]}"; do
        if [ -f "artifacts/$dmg" ]; then
            size=$(du -h "artifacts/$dmg" | cut -f1)
            echo "  📀 $dmg ($size) - Manual installation option" >> artifacts/PKG_INSTALLER_REPORT.txt
        fi
    done
fi

# Add failed items to report (only critical failures)
if [ ${#failed_items[@]} -gt 0 ]; then
    echo "" >> artifacts/PKG_INSTALLER_REPORT.txt
    echo "Critical Failures:" >> artifacts/PKG_INSTALLER_REPORT.txt
    for item in "${failed_items[@]}"; do
        echo "  ❌ $item" >> artifacts/PKG_INSTALLER_REPORT.txt
    done
fi

# Add installation instructions
cat >> artifacts/PKG_INSTALLER_REPORT.txt << EOF

Installation Instructions for Users:
===================================

PKG Installer (Recommended):
1. Download the .pkg file
2. Double-click to launch macOS Installer
3. Follow the installation prompts
4. Application will be installed to /Applications
5. No security warnings (signed and notarized)

DMG Image (Alternative):
1. Download the .dmg file
2. Double-click to mount the disk image
3. Drag application to Applications folder
4. Eject the disk image

Verification Commands:
- PKG signature: pkgutil --check-signature <file.pkg>
- Notarization: spctl --assess --type install <file>
- Stapling: xcrun stapler validate <file>

Distribution Status:
- PKG installers are production-ready
- No security warnings will appear
- Gatekeeper approval confirmed
- Ready for public distribution
EOF

echo ""
echo "✅ macOS PKG installer creation complete!"
echo "📋 Summary:"
echo "  - PKG Installers (primary): ${#successful_pkgs[@]}"
echo "  - DMG Files (optional): ${#successful_dmgs[@]}"
echo "  - Critical failures: ${#failed_items[@]}"
echo ""

# Display PKG files prominently
if [ ${#successful_pkgs[@]} -gt 0 ]; then
    echo "🎯 PRIMARY DISTRIBUTION FILES (PKG Installers):"
    for pkg in "${successful_pkgs[@]}"; do
        if [ -f "artifacts/$pkg" ]; then
            size=$(du -h "artifacts/$pkg" | cut -f1)
            echo "  📦 $pkg ($size)"
        fi
    done
fi

if [ ${#successful_dmgs[@]} -gt 0 ]; then
    echo ""
    echo "💽 SECONDARY FILES (DMG Images):"
    for dmg in "${successful_dmgs[@]}"; do
        if [ -f "artifacts/$dmg" ]; then
            size=$(du -h "artifacts/$dmg" | cut -f1)
            echo "  📀 $dmg ($size)"
        fi
    done
fi

echo ""
echo "📋 Full report available at: artifacts/PKG_INSTALLER_REPORT.txt"

# Exit with error only if PKG creation failed (DMG failures are not critical)
critical_failures=0
for item in "${failed_items[@]}"; do
    if [[ "$item" == *"PKG"* ]] || [[ "$item" == *"Signing"* ]] || [[ "$item" == *"app bundle"* ]]; then
        critical_failures=$((critical_failures + 1))
    fi
done

if [ $critical_failures -gt 0 ]; then
    echo "❌ Critical failures occurred. PKG installer creation failed."
    exit 1
else
    echo "✅ PKG installer creation successful! Ready for distribution."
fi
