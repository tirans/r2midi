#!/bin/bash
# build-all-local.sh - Build complete R2MIDI suite with proper certificate handling
set -euo pipefail

echo "🚀 R2MIDI Build System with Certificate Management"

# Check if we're running in GitHub Actions
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "🔐 Running in GitHub Actions - setting up certificates from environment variables..."

    # Create temporary certificate directory
    mkdir -p /tmp/github_certs

    # Decode and save Developer ID certificates
    if [ -n "${APPLE_DEVELOPER_ID_APPLICATION_CERT:-}" ]; then
        echo "$APPLE_DEVELOPER_ID_APPLICATION_CERT" | base64 --decode > /tmp/github_certs/app_cert.p12
    else
        echo "❌ APPLE_DEVELOPER_ID_APPLICATION_CERT not found in environment"
        exit 1
    fi

    if [ -n "${APPLE_DEVELOPER_ID_INSTALLER_CERT:-}" ]; then
        echo "$APPLE_DEVELOPER_ID_INSTALLER_CERT" | base64 --decode > /tmp/github_certs/installer_cert.p12
    else
        echo "❌ APPLE_DEVELOPER_ID_INSTALLER_CERT not found in environment"
        exit 1
    fi

    # Decode and save App Store certificate if available
    if [ -n "${APPLE_APP_STORE_CERTIFICATE_P12:-}" ]; then
        echo "$APPLE_APP_STORE_CERTIFICATE_P12" | base64 --decode > /tmp/github_certs/app_store_cert.p12
        echo "✅ App Store certificate available"
        APP_STORE_CERT_AVAILABLE="true"
    else
        echo "⚠️ App Store certificate not available"
        APP_STORE_CERT_AVAILABLE="false"
    fi

    # Create a temporary app_config.json for GitHub Actions
    cat > /tmp/github_app_config.json << EOF
{
  "apple_developer": {
    "team_id": "${APPLE_TEAM_ID}",
    "p12_path": "/tmp/github_certs",
    "p12_password": "${APPLE_CERT_PASSWORD}",
    "app_store_p12_password": "${APPLE_APP_STORE_CERTIFICATE_PASSWORD:-${APPLE_CERT_PASSWORD}}",
    "app_specific_password": "${APPLE_ID_PASSWORD}",
    "apple_id": "${APPLE_ID}"
  },
  "build_options": {
    "enable_notarization": true
  }
}
EOF

    # Set up environment to use GitHub certificates
    export CONFIG_FILE="/tmp/github_app_config.json"

    # Run certificate setup with GitHub certificates
    if [ -f "./setup-local-certificates.sh" ]; then
        chmod +x ./setup-local-certificates.sh
        # Temporarily replace the config file path in the setup script
        sed "s|apple_credentials/config/app_config.json|$CONFIG_FILE|g" ./setup-local-certificates.sh > /tmp/setup-github-certificates.sh
        chmod +x /tmp/setup-github-certificates.sh
        /tmp/setup-github-certificates.sh
    else
        echo "❌ setup-local-certificates.sh not found"
        exit 1
    fi
else
    # Check if certificates have been imported for local builds
    if [ ! -f ".local_build_env" ]; then
        echo "⚠️ Certificates not imported. Running certificate setup first..."
        if [ -f "./setup-local-certificates.sh" ]; then
            chmod +x ./setup-local-certificates.sh
            ./setup-local-certificates.sh
        else
            echo "❌ setup-local-certificates.sh not found. Please run it first."
            exit 1
        fi
    fi
fi

# Source the environment variables from certificate setup
echo "🔐 Loading certificate environment..."
source .local_build_env

if [ "$CERTIFICATES_IMPORTED" != "true" ]; then
    echo "❌ Certificates not properly imported"
    exit 1
fi

echo "✅ Using keychain: $TEMP_KEYCHAIN"
echo "✅ App signing identity: $APP_SIGNING_IDENTITY"
echo "✅ Installer signing identity: $INSTALLER_SIGNING_IDENTITY"

# Unlock the keychain to ensure it's accessible
security unlock-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN" || {
    echo "❌ Failed to unlock keychain. Re-running certificate setup..."
    ./setup-local-certificates.sh
    source .local_build_env
    security unlock-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"
}

# Load Apple credentials - prioritize environment variables over config file
if [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_ID_PASSWORD:-}" ]; then
    echo "🔐 Using Apple credentials from environment variables"
    TEAM_ID="$APPLE_TEAM_ID"
    APPLE_ID="$APPLE_ID"
    APP_PASSWORD="$APPLE_ID_PASSWORD"
    ENABLE_NOTARIZATION="true"
elif [ -f "apple_credentials/config/app_config.json" ]; then
    echo "🔐 Using Apple credentials from config file"
    TEAM_ID=$(python3 -c "import json; print(json.load(open('apple_credentials/config/app_config.json'))['apple_developer']['team_id'])")
    APPLE_ID=$(python3 -c "import json; print(json.load(open('apple_credentials/config/app_config.json'))['apple_developer']['apple_id'])")
    APP_PASSWORD=$(python3 -c "import json; print(json.load(open('apple_credentials/config/app_config.json'))['apple_developer']['app_specific_password'])")
    ENABLE_NOTARIZATION=$(python3 -c "import json; result = json.load(open('apple_credentials/config/app_config.json'))['build_options']['enable_notarization']; print('true' if result else 'false')")
else
    echo "⚠️ Apple credentials not found, skipping notarization"
    TEAM_ID=""
    APPLE_ID=""
    APP_PASSWORD=""
    ENABLE_NOTARIZATION="false"
fi

# Function to create a fresh app bundle without extended attributes
create_fresh_bundle() {
    local original_path="$1"
    local app_name="$2"

    echo "   🆕 Creating fresh bundle for $app_name..."

    # Create a temporary fresh bundle path
    local fresh_bundle="${original_path}_fresh_$(date +%s)"
    local temp_dir="/tmp/r2midi_build_$(date +%s)"

    # Create clean temporary directory
    mkdir -p "$temp_dir"

    echo "   📋 Analyzing bundle structure..."

    # Use tar to create a clean copy without extended attributes
    echo "   📦 Creating attribute-free copy using tar..."
    # Note: macOS tar doesn't support --no-xattrs, so we use COPYFILE_DISABLE
    (cd "$(dirname "$original_path")" && COPYFILE_DISABLE=1 tar --exclude='._*' --exclude='.DS_Store' -cf - "$(basename "$original_path")") | (cd "$temp_dir" && tar -xf -)

    # Move the app from temp dir
    mv "$temp_dir/$(basename "$original_path")" "$fresh_bundle"
    rm -rf "$temp_dir"

    # Additional cleanup on the fresh bundle
    echo "   🧹 Performing deep clean on fresh bundle..."

    # Remove all extended attributes recursively
    find "$fresh_bundle" -print0 | while IFS= read -r -d '' file; do
        xattr -c "$file" 2>/dev/null || true
    done

    # Remove problematic files
    find "$fresh_bundle" -name ".DS_Store" -delete 2>/dev/null || true
    find "$fresh_bundle" -name "._*" -delete 2>/dev/null || true
    find "$fresh_bundle" -name "*.pyc" -delete 2>/dev/null || true
    find "$fresh_bundle" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

    # Verify the fresh bundle
    local xattr_count=$(find "$fresh_bundle" -exec xattr {} \; 2>/dev/null | wc -l | tr -d ' ')
    echo "   📊 Fresh bundle extended attributes: $xattr_count"

    if [ "$xattr_count" -eq 0 ]; then
        echo "   ✅ Fresh bundle created successfully with no extended attributes"

        # Replace original with fresh bundle
        rm -rf "$original_path"
        mv "$fresh_bundle" "$original_path"

        return 0
    else
        echo "   ⚠️ Fresh bundle still has $xattr_count attributes, trying alternative method..."

        # Alternative: manually reconstruct the bundle
        local manual_bundle="${original_path}_manual_$(date +%s)"
        echo "   🏗️ Manually reconstructing bundle structure..."

        # Create the basic structure
        mkdir -p "$manual_bundle/Contents/MacOS"
        mkdir -p "$manual_bundle/Contents/Resources"
        mkdir -p "$manual_bundle/Contents/Frameworks"

        # Copy files without extended attributes
        echo "   📂 Copying bundle contents without attributes..."

        # Copy Info.plist
        if [ -f "$fresh_bundle/Contents/Info.plist" ]; then
            cat "$fresh_bundle/Contents/Info.plist" > "$manual_bundle/Contents/Info.plist"
        fi

        # Copy executable
        if [ -d "$fresh_bundle/Contents/MacOS" ]; then
            find "$fresh_bundle/Contents/MacOS" -type f -print0 | while IFS= read -r -d '' file; do
                local relative_path="${file#$fresh_bundle/Contents/MacOS/}"
                local dest_dir="$(dirname "$manual_bundle/Contents/MacOS/$relative_path")"
                mkdir -p "$dest_dir"
                cat "$file" > "$manual_bundle/Contents/MacOS/$relative_path"
                chmod +x "$manual_bundle/Contents/MacOS/$relative_path"
            done
        fi

        # Copy Resources
        if [ -d "$fresh_bundle/Contents/Resources" ]; then
            cd "$fresh_bundle/Contents/Resources"
            find . -type f -print0 | while IFS= read -r -d '' file; do
                local dest_dir="$(dirname "$manual_bundle/Contents/Resources/$file")"
                mkdir -p "$dest_dir"
                cat "$file" > "$manual_bundle/Contents/Resources/$file"
            done
            cd - > /dev/null
        fi

        # Copy Frameworks if exists
        if [ -d "$fresh_bundle/Contents/Frameworks" ]; then
            cd "$fresh_bundle/Contents/Frameworks"
            find . -type f -print0 | while IFS= read -r -d '' file; do
                local dest_dir="$(dirname "$manual_bundle/Contents/Frameworks/$file")"
                mkdir -p "$dest_dir"
                cat "$file" > "$manual_bundle/Contents/Frameworks/$file"
            done
            cd - > /dev/null
        fi

        # Copy any other top-level items in Contents
        find "$fresh_bundle/Contents" -maxdepth 1 -type f -print0 | while IFS= read -r -d '' file; do
            local basename="$(basename "$file")"
            if [ "$basename" != "Info.plist" ]; then
                cat "$file" > "$manual_bundle/Contents/$basename"
            fi
        done

        # Remove the fresh bundle attempt
        rm -rf "$fresh_bundle"

        # Final verification
        local manual_xattr_count=$(find "$manual_bundle" -exec xattr {} \; 2>/dev/null | wc -l | tr -d ' ')
        echo "   📊 Manually rebuilt bundle extended attributes: $manual_xattr_count"

        # Replace original with manual bundle
        rm -rf "$original_path"
        mv "$manual_bundle" "$original_path"

        if [ "$manual_xattr_count" -eq 0 ]; then
            echo "   ✅ Bundle manually reconstructed with no extended attributes"
            return 0
        else
            echo "   ⚠️ Manual reconstruction still has $manual_xattr_count attributes"
            return 1
        fi
    fi
}

# Function to sign application using imported certificates
sign_app() {
    local app_path="$1"
    local app_name="$2"
    local cert_type="${3:-developer_id}"  # Default to developer_id for backward compatibility

    if [ "$SKIP_SIGNING" = "true" ]; then
        echo "   ⏭️ Skipping signing for $app_name"
        return 0
    fi

    # Determine which signing identity to use
    local signing_identity
    case "$cert_type" in
        "app_store")
            if [ -z "$APP_STORE_SIGNING_IDENTITY" ]; then
                echo "   ⚠️ App Store certificate not available, skipping App Store signing for $app_name"
                return 0
            fi
            signing_identity="$APP_STORE_SIGNING_IDENTITY"
            echo "   🔐 Preparing to sign $app_name with App Store certificate..."
            ;;
        "developer_id"|*)
            signing_identity="$DEVELOPER_ID_APP_SIGNING_IDENTITY"
            echo "   🔐 Preparing to sign $app_name with Developer ID certificate..."
            ;;
    esac

    # First, remove any existing signature
    echo "   🗑️ Removing any existing signatures..."
    codesign --remove-signature "$app_path" 2>/dev/null || true

    # Create a fresh bundle to ensure no extended attributes
    create_fresh_bundle "$app_path" "$app_name"

    # Double-check that extended attributes are gone
    local remaining_attrs=$(find "$app_path" -exec xattr {} \; 2>/dev/null | wc -l | tr -d ' ')
    if [ "$remaining_attrs" -gt 0 ]; then
        echo "   ⚠️ Warning: $remaining_attrs extended attributes remain after cleaning"

        # List which files have attributes for debugging
        echo "   📝 Files with extended attributes:"
        find "$app_path" -exec sh -c 'attrs=$(xattr "$1" 2>/dev/null); if [ -n "$attrs" ]; then echo "      $1: $attrs"; fi' _ {} \; | head -20
        echo "   ..."
    fi

    echo "   🔐 Signing $app_name with $cert_type certificate..."
    echo "   App path: $app_path"
    echo "   Signing identity: $signing_identity"
    echo "   Using keychain: $TEMP_KEYCHAIN"

    # Unlock keychain before signing
    security unlock-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"

    # Find entitlements file
    local entitlements_path="entitlements.plist"
    if [ ! -f "$entitlements_path" ]; then
        entitlements_path="../entitlements.plist"
    fi
    if [ ! -f "$entitlements_path" ]; then
        entitlements_path="../../entitlements.plist"
    fi

    echo "   Using entitlements file: $entitlements_path"
    echo "   Entitlements file exists: $([ -f "$entitlements_path" ] && echo 'Yes' || echo 'No')"

    # Try signing with timestamp and strict verification
    local sign_success=false

    if [ -f "$entitlements_path" ]; then
        echo "   🔏 Attempting to sign with entitlements..."
        if codesign --force \
            --options runtime \
            --sign "$signing_identity" \
            --entitlements "$entitlements_path" \
            --timestamp \
            --keychain "$TEMP_KEYCHAIN" \
            "$app_path" 2>&1; then
            echo "   ✅ Successfully signed $app_name with entitlements"
            sign_success=true
        else
            echo "   ⚠️ Failed to sign with entitlements, trying without..."
        fi
    fi

    if [ "$sign_success" = "false" ]; then
        echo "   🔏 Attempting to sign without entitlements..."
        if codesign --force \
            --options runtime \
            --sign "$signing_identity" \
            --timestamp \
            --keychain "$TEMP_KEYCHAIN" \
            "$app_path" 2>&1; then
            echo "   ✅ Successfully signed $app_name without entitlements"
            sign_success=true
        else
            echo "   ❌ Failed to sign $app_name"

            # Show more detailed error information
            echo "   📋 Detailed codesign attempt:"
            codesign --force --verbose=4 \
                --options runtime \
                --sign "$signing_identity" \
                --keychain "$TEMP_KEYCHAIN" \
                "$app_path" 2>&1 | head -20

            return 1
        fi
    fi

    # Verify signature
    echo "   🔍 Verifying signature..."
    if codesign --verify --deep --strict --verbose=2 "$app_path" 2>&1; then
        echo "   ✅ Signature verification passed for $app_name"

        # Display signature info
        echo "   📋 Signature details:"
        codesign --display --verbose=2 "$app_path" 2>&1 | grep -E "(Authority|TeamIdentifier|Signature)" | head -5

        return 0
    else
        echo "   ❌ Signature verification failed for $app_name"
        return 1
    fi
}

# Function to sign installer package using imported certificates
sign_pkg() {
    local pkg_path="$1"
    local pkg_name="$2"
    local cert_type="${3:-developer_id}"  # Default to developer_id for backward compatibility

    if [ "$SKIP_SIGNING" = "true" ]; then
        echo "   ⏭️ Skipping package signing for $pkg_name"
        return 0
    fi

    # Determine which installer signing identity to use
    local installer_signing_identity
    case "$cert_type" in
        "app_store")
            echo "   ⚠️ App Store packages don't require installer signing, skipping package signing for $pkg_name"
            return 0
            ;;
        "developer_id"|*)
            installer_signing_identity="$DEVELOPER_ID_INSTALLER_SIGNING_IDENTITY"
            echo "   📦 Signing package $pkg_name with Developer ID Installer certificate..."
            ;;
    esac

    # Unlock keychain before signing
    security unlock-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"

    # Create signed package using the imported installer certificate
    local signed_pkg="${pkg_path%.pkg}-signed.pkg"

    echo "   Package signing command: productsign --sign '$installer_signing_identity' --keychain '$TEMP_KEYCHAIN' '$pkg_path' '$signed_pkg'"

    if productsign --sign "$installer_signing_identity" --keychain "$TEMP_KEYCHAIN" "$pkg_path" "$signed_pkg"; then
        mv "$signed_pkg" "$pkg_path"
        echo "   ✅ Successfully signed package $pkg_name"

        # Verify package signature
        if pkgutil --check-signature "$pkg_path"; then
            echo "   ✅ Package signature verification passed for $pkg_name"
            return 0
        else
            echo "   ❌ Package signature verification failed for $pkg_name"
            return 1
        fi
    else
        echo "   ❌ Failed to sign package $pkg_name"
        return 1
    fi
}

# Function to notarize package
notarize_pkg() {
    local pkg_path="$1"
    local pkg_name="$2"

    if [ "$SKIP_SIGNING" = "true" ] || [ "$ENABLE_NOTARIZATION" != "true" ]; then
        echo "   ⏭️ Skipping notarization for $pkg_name"
        return 0
    fi

    if [ -z "$APPLE_ID" ] || [ -z "$APP_PASSWORD" ]; then
        echo "   ⚠️ Apple ID credentials not found, skipping notarization for $pkg_name"
        return 0
    fi

    echo "   🍎 Notarizing package $pkg_name..."

    # Submit for notarization
    local submit_result
    if submit_result=$(xcrun notarytool submit "$pkg_path" \
        --apple-id "$APPLE_ID" \
        --password "$APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait 2>&1); then

        echo "   ✅ Successfully notarized $pkg_name"
        echo "$submit_result"

        # Staple the notarization
        if xcrun stapler staple "$pkg_path"; then
            echo "   ✅ Successfully stapled notarization to $pkg_name"
            return 0
        else
            echo "   ⚠️ Failed to staple notarization to $pkg_name (package is still notarized)"
            return 0
        fi
    else
        echo "   ❌ Failed to notarize $pkg_name"
        echo "$submit_result"
        return 1
    fi
}

# Function to create dual signed packages (Developer ID and App Store)
create_dual_signed_packages() {
    local app_path="$1"
    local app_name="$2"
    local base_pkg_name="$3"
    local version="$4"
    local identifier="$5"

    echo "📦 Creating dual signed packages for $app_name..."

    # Track success of each package type
    local dev_id_success=false
    local app_store_success=false

    # Create Developer ID (indi distribution) package
    echo "🔐 Creating Developer ID package..."

    # Make a copy of the app for Developer ID signing
    local dev_id_app_path="${app_path}_dev_id"
    cp -R "$app_path" "$dev_id_app_path"

    # Sign with Developer ID certificate
    if ! sign_app "$dev_id_app_path" "$app_name (Developer ID)" "developer_id"; then
        echo "❌ Failed to sign $app_name with Developer ID certificate"
        rm -rf "$dev_id_app_path"
    else
        # Create Developer ID package
        local dev_id_pkg="../artifacts/${base_pkg_name}-${version}-indi.pkg"
        if pkgbuild --identifier "$identifier" --version "$version" \
                 --install-location "/Applications" --component "$dev_id_app_path" \
                 "$dev_id_pkg"; then
            echo "   ✅ Successfully created Developer ID package"

            # Sign the Developer ID package
            if ! sign_pkg "$dev_id_pkg" "$app_name (Developer ID)" "developer_id"; then
                echo "❌ Failed to sign Developer ID package"
                rm -rf "$dev_id_app_path"
            else
                # Notarize the Developer ID package
                if ! notarize_pkg "$dev_id_pkg" "$app_name (Developer ID)"; then
                    echo "⚠️ Developer ID package notarization failed, but continuing..."
                fi
                dev_id_success=true
            fi
        else
            echo "   ❌ Failed to create Developer ID package"
            rm -rf "$dev_id_app_path"
        fi

        # Clean up Developer ID app copy
        rm -rf "$dev_id_app_path"
    fi

    # Create App Store package if App Store certificate is available (independent of Developer ID success)
    if [ "$APP_STORE_CERT_AVAILABLE" = "true" ] && [ -n "$APP_STORE_SIGNING_IDENTITY" ]; then
        echo "🏪 Creating App Store package..."

        # Make a copy of the app for App Store signing
        local app_store_app_path="${app_path}_app_store"
        cp -R "$app_path" "$app_store_app_path"

        # Sign with App Store certificate
        if ! sign_app "$app_store_app_path" "$app_name (App Store)" "app_store"; then
            echo "❌ Failed to sign $app_name with App Store certificate"
            rm -rf "$app_store_app_path"
        else
            # Create App Store package (note: App Store packages don't need installer signing)
            local app_store_pkg="../artifacts/${base_pkg_name}-${version}-appstore.pkg"
            if pkgbuild --identifier "$identifier.appstore" --version "$version" \
                     --install-location "/Applications" --component "$app_store_app_path" \
                     "$app_store_pkg"; then
                echo "   ✅ Successfully created App Store package"

                # App Store packages don't need installer signing or notarization
                echo "   ℹ️ App Store packages don't require installer signing or notarization"
                app_store_success=true
            else
                echo "   ❌ Failed to create App Store package"
                rm -rf "$app_store_app_path"
            fi

            # Clean up App Store app copy
            rm -rf "$app_store_app_path"
        fi
    else
        echo "⚠️ App Store certificate not available, skipping App Store package creation"
    fi

    # Return success if at least one package was created successfully
    if [ "$dev_id_success" = true ] || [ "$app_store_success" = true ]; then
        return 0
    else
        echo "❌ Failed to create any packages for $app_name"
        return 1
    fi
}

# Function to robust cleanup
robust_cleanup() {
    local dir="$1"
    echo "🧹 Cleaning $dir..."

    # Try multiple cleanup methods
    if [ -d "$dir" ]; then
        # First, remove extended attributes recursively
        echo "   Removing extended attributes..."
        find "$dir" -exec xattr -c {} \; 2>/dev/null || true

        # Check for files owned by root and change ownership
        echo "   Checking file ownership..."
        if find "$dir" -user root -print -quit | grep -q .; then
            echo "   Found root-owned files, changing ownership..."
            find "$dir" -user root -exec chown "$(whoami)" {} \; 2>/dev/null || true
        fi

        # Try to change permissions recursively
        echo "   Setting permissions..."
        chmod -R u+rwx "$dir" 2>/dev/null || true

        # First try normal removal
        rm -rf "$dir" 2>/dev/null || true

        # If directory still exists, try alternative cleanup methods
        if [ -d "$dir" ]; then
            echo "   Trying alternative cleanup methods..."
            # Try to change permissions first
            chmod -R 755 "$dir" 2>/dev/null || true
            rm -rf "$dir" 2>/dev/null || true
        fi

        # If still exists, try to remove contents first
        if [ -d "$dir" ]; then
            echo "   Trying selective cleanup..."
            find "$dir" -type f -delete 2>/dev/null || true
            find "$dir" -type d -empty -delete 2>/dev/null || true
            rm -rf "$dir" 2>/dev/null || true
        fi

        # Final attempt: try to remove each file individually
        if [ -d "$dir" ]; then
            echo "   Trying individual file removal..."
            find "$dir" -type f -exec rm -f {} \; 2>/dev/null || true
            find "$dir" -depth -type d -exec rmdir {} \; 2>/dev/null || true
        fi
    fi

    # Ensure directory is gone
    if [ -d "$dir" ]; then
        echo "❌ Failed to completely remove $dir. Manual cleanup may be required."
        echo "   Remaining contents:"
        ls -la "$dir" 2>/dev/null || true
        return 1
    fi

    echo "✅ $dir cleaned successfully"
    return 0
}

VERSION=""
BUILD_TYPE="local"
SKIP_SIGNING=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --version) VERSION="$2"; shift 2 ;;
        --dev) BUILD_TYPE="dev"; shift ;;
        --no-sign) SKIP_SIGNING=true; shift ;;
        --no-notarize) shift ;; # Accept but ignore
        *) echo "Usage: $0 [--version VERSION] [--dev] [--no-sign]"; exit 1 ;;
    esac
done

if [ -z "$VERSION" ]; then
    if [ -f "server/version.py" ]; then
        VERSION=$(python3 -c "import sys; sys.path.insert(0, 'server'); from version import __version__; print(__version__)")
    else
        VERSION="1.0.0"
    fi
fi

echo "🚀 Building R2MIDI Complete Suite v$VERSION..."

# Check environments
if [ ! -d "venv_client" ] || [ ! -d "venv_server" ]; then
    echo "❌ Virtual environments not found. Run: ./setup-virtual-environments.sh"
    exit 1
fi

# Verify entitlements file exists
if [ ! -f "entitlements.plist" ]; then
    echo "⚠️ entitlements.plist not found, creating one..."
    cat > entitlements.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.device.microphone</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
</dict>
</plist>
EOF
    echo "✅ Created entitlements.plist"
fi

mkdir -p artifacts

# Build client
echo "🎨 Building client..."
robust_cleanup "build_client"
mkdir -p build_client
cd build_client
cp ../setup_client.py setup.py
cp -r ../r2midi_client .
cp -r ../resources . 2>/dev/null || true
# Copy entitlements to build directory
echo "   📋 Copying entitlements file..."
if [ -f "../entitlements.plist" ]; then
    cp "../entitlements.plist" "entitlements.plist"
    echo "   ✅ Copied entitlements.plist to build directory"
else
    echo "   ⚠️ entitlements.plist not found in parent directory"
fi
sed -i.bak "s/__version__ = \".*\"/__version__ = \"$VERSION\"/" setup.py

# Clean up any unwanted files before building
echo "   🧹 Cleaning source files before build..."
find . -name ".DS_Store" -delete 2>/dev/null || true
find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true
find . -name "._*" -delete 2>/dev/null || true

# Remove all extended attributes from source files
echo "   🧼 Removing extended attributes from source files..."
find . -exec xattr -c {} \; 2>/dev/null || true

# Activate virtual environment and build
source ../venv_client/bin/activate

# Clear Python cache and py2app cache
export PYTHONDONTWRITEBYTECODE=1
export PYTHONWARNINGS="ignore::DeprecationWarning"
# Prevent macOS from creating extended attributes during build
export COPYFILE_DISABLE=1
export COPY_EXTENDED_ATTRIBUTES_DISABLE=1
python -m pip cache purge 2>/dev/null || true
rm -rf build dist 2>/dev/null || true
rm -rf ~/.py2app 2>/dev/null || true

# Run build with force clean and better error handling
echo "   Running py2app build..."
python setup.py clean --all 2>/dev/null || true

if ! python setup.py py2app --verbose; then
    echo "❌ Client build failed. Cleaning up..."
    deactivate
    cd ..
    robust_cleanup "build_client"
    exit 1
fi

deactivate

# Check if build was successful
if [ ! -d "dist" ]; then
    echo "❌ Client build failed - no dist directory created"
    cd ..
    robust_cleanup "build_client"
    exit 1
fi

[ -d "dist/main.app" ] && mv "dist/main.app" "dist/R2MIDI Client.app"
APP_PATH="dist/R2MIDI Client.app"

# Check if the app was created successfully
if [ ! -d "$APP_PATH" ]; then
    echo "❌ Client app was not created successfully"
    cd ..
    robust_cleanup "build_client"
    exit 1
fi

# Create dual signed packages (Developer ID and App Store)
if ! create_dual_signed_packages "$APP_PATH" "R2MIDI Client" "R2MIDI-Client" "$VERSION" "com.r2midi.client"; then
    echo "⚠️ Some client packages may have failed, but continuing with build..."
fi

cd ..

# Build server (similar process...)
echo "🖥️ Building server..."
robust_cleanup "build_server"
mkdir -p build_server
cd build_server
cp ../setup_server.py setup.py
cp -r ../server .
cp -r ../resources . 2>/dev/null || true
# Copy entitlements to build directory
echo "   📋 Copying entitlements file..."
if [ -f "../entitlements.plist" ]; then
    cp "../entitlements.plist" "entitlements.plist"
    echo "   ✅ Copied entitlements.plist to build directory"
else
    echo "   ⚠️ entitlements.plist not found in parent directory"
fi
sed -i.bak "s/__version__ = \".*\"/__version__ = \"$VERSION\"/" setup.py

# Clean up any unwanted files before building
echo "   🧹 Cleaning source files before build..."
find . -name ".DS_Store" -delete 2>/dev/null || true
find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true
find . -name "._*" -delete 2>/dev/null || true

# Remove all extended attributes from source files
echo "   🧼 Removing extended attributes from source files..."
find . -exec xattr -c {} \; 2>/dev/null || true

# Activate virtual environment and build
source ../venv_server/bin/activate

# Clear Python cache and py2app cache
export PYTHONDONTWRITEBYTECODE=1
export PYTHONWARNINGS="ignore::DeprecationWarning"
# Prevent macOS from creating extended attributes during build
export COPYFILE_DISABLE=1
export COPY_EXTENDED_ATTRIBUTES_DISABLE=1
python -m pip cache purge 2>/dev/null || true
rm -rf build dist 2>/dev/null || true
rm -rf ~/.py2app 2>/dev/null || true

# Run build with force clean and better error handling
echo "   Running py2app build..."
python setup.py clean --all 2>/dev/null || true

if ! python setup.py py2app --verbose; then
    echo "❌ Server build failed. Cleaning up..."
    deactivate
    cd ..
    robust_cleanup "build_server"
    exit 1
fi

deactivate

# Check if build was successful
if [ ! -d "dist" ]; then
    echo "❌ Server build failed - no dist directory created"
    cd ..
    robust_cleanup "build_server"
    exit 1
fi

[ -d "dist/main.app" ] && mv "dist/main.app" "dist/R2MIDI Server.app"
APP_PATH="dist/R2MIDI Server.app"

# Check if the app was created successfully
if [ ! -d "$APP_PATH" ]; then
    echo "❌ Server app was not created successfully"
    cd ..
    robust_cleanup "build_server"
    exit 1
fi

# Create dual signed packages (Developer ID and App Store)
if ! create_dual_signed_packages "$APP_PATH" "R2MIDI Server" "R2MIDI-Server" "$VERSION" "com.r2midi.server"; then
    echo "⚠️ Some server packages may have failed, but continuing with build..."
fi

cd ..

echo "✅ Build completed! Check artifacts/ directory."
echo "📦 Generated packages:"
for pkg in artifacts/R2MIDI-*-${VERSION}.pkg; do
    if [ -f "$pkg" ]; then
        echo "   ✅ $(basename "$pkg")"
        # Show package info
        echo "      Size: $(du -h "$pkg" | cut -f1)"
        echo "      Signed: $(pkgutil --check-signature "$pkg" >/dev/null 2>&1 && echo 'Yes' || echo 'No')"
        echo "      Notarized: $(spctl --assess --type install "$pkg" >/dev/null 2>&1 && echo 'Yes' || echo 'No')"
    fi
done

# Check which packages were successfully created
packages_created=0
missing_packages=""

if [ ! -f "artifacts/R2MIDI-Client-${VERSION}-indi.pkg" ]; then
    echo "⚠️ Client Developer ID package was not created"
    missing_packages="$missing_packages R2MIDI-Client-${VERSION}-indi.pkg"
else
    packages_created=$((packages_created + 1))
fi

if [ ! -f "artifacts/R2MIDI-Server-${VERSION}-indi.pkg" ]; then
    echo "⚠️ Server Developer ID package was not created"
    missing_packages="$missing_packages R2MIDI-Server-${VERSION}-indi.pkg"
else
    packages_created=$((packages_created + 1))
fi

# Check App Store packages if certificates were available
if [ "$APP_STORE_CERT_AVAILABLE" = "true" ] && [ -n "$APP_STORE_SIGNING_IDENTITY" ]; then
    if [ -f "artifacts/R2MIDI-Client-${VERSION}-appstore.pkg" ]; then
        packages_created=$((packages_created + 1))
    else
        echo "⚠️ Client App Store package was not created"
        missing_packages="$missing_packages R2MIDI-Client-${VERSION}-appstore.pkg"
    fi

    if [ -f "artifacts/R2MIDI-Server-${VERSION}-appstore.pkg" ]; then
        packages_created=$((packages_created + 1))
    else
        echo "⚠️ Server App Store package was not created"
        missing_packages="$missing_packages R2MIDI-Server-${VERSION}-appstore.pkg"
    fi
fi

# Only fail if no packages were created at all
if [ $packages_created -eq 0 ]; then
    echo "❌ No packages were created successfully"
    exit 1
fi

echo "
🎉 Build completed successfully!"
echo "📦 Ready for distribution:"

# List Developer ID packages that were actually created
dev_id_packages_exist=false
if [ -f "artifacts/R2MIDI-Client-${VERSION}-indi.pkg" ] || [ -f "artifacts/R2MIDI-Server-${VERSION}-indi.pkg" ]; then
    echo "   Developer ID (indi distribution):"
    dev_id_packages_exist=true
    if [ -f "artifacts/R2MIDI-Client-${VERSION}-indi.pkg" ]; then
        echo "   • R2MIDI-Client-${VERSION}-indi.pkg"
    fi
    if [ -f "artifacts/R2MIDI-Server-${VERSION}-indi.pkg" ]; then
        echo "   • R2MIDI-Server-${VERSION}-indi.pkg"
    fi
fi

# List App Store packages that were actually created
app_store_packages_exist=false
if [ "$APP_STORE_CERT_AVAILABLE" = "true" ] && [ -n "$APP_STORE_SIGNING_IDENTITY" ]; then
    if [ -f "artifacts/R2MIDI-Client-${VERSION}-appstore.pkg" ] || [ -f "artifacts/R2MIDI-Server-${VERSION}-appstore.pkg" ]; then
        echo "   App Store:"
        app_store_packages_exist=true
        if [ -f "artifacts/R2MIDI-Client-${VERSION}-appstore.pkg" ]; then
            echo "   • R2MIDI-Client-${VERSION}-appstore.pkg"
        fi
        if [ -f "artifacts/R2MIDI-Server-${VERSION}-appstore.pkg" ]; then
            echo "   • R2MIDI-Server-${VERSION}-appstore.pkg"
        fi
    fi
fi

# Show summary message
if [ -n "$missing_packages" ]; then
    echo "
⚠️ Some packages could not be created, but the build completed with $packages_created package(s)."
    echo "Missing packages:$missing_packages"
else
    echo "
All packages are signed and notarized (if enabled) and ready for distribution."
fi
echo ""
echo "🧹 To clean up certificates later, run:"
echo "   security delete-keychain \"$TEMP_KEYCHAIN\""
echo "   rm -f .local_build_env"
