#!/bin/bash
set -euo pipefail

# sign-and-notarize-macos.sh - Enhanced signing and notarization with detailed logging
# This script replaces the corrupted version with proper modular design

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

# Source required modules
if [ -f "$MODULES_DIR/logging-utils.sh" ]; then
    source "$MODULES_DIR/logging-utils.sh"
else
    echo "❌ Error: logging-utils.sh not found at $MODULES_DIR/logging-utils.sh"
    exit 1
fi

if [ -f "$MODULES_DIR/certificate-manager.sh" ]; then
    source "$MODULES_DIR/certificate-manager.sh"
else
    log_error "certificate-manager.sh not found at $MODULES_DIR/certificate-manager.sh"
    exit 1
fi

if [ -f "$MODULES_DIR/build-utils.sh" ]; then
    source "$MODULES_DIR/build-utils.sh"
else
    log_error "build-utils.sh not found at $MODULES_DIR/build-utils.sh"
    exit 1
fi

if [ -f "$MODULES_DIR/deep-clean-utils.sh" ]; then
    source "$MODULES_DIR/deep-clean-utils.sh"
else
    log_warning "deep-clean-utils.sh not found at $MODULES_DIR/deep-clean-utils.sh"
fi

# Default values
VERSION=""
BUILD_TYPE="production"
SKIP_NOTARIZATION=false
TARGET_PATH=""
RETRY_COUNT=3

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --dev)
            BUILD_TYPE="dev"
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
        --retry-count)
            RETRY_COUNT="$2"
            shift 2
            ;;
        --help)
            cat << EOF
Enhanced Signing and Notarization Script

Usage: $0 [options]

Options:
  --version VERSION     Specify version
  --dev                Development build
  --skip-notarize      Skip notarization
  --target PATH        Specific target to sign (optional)
  --retry-count N      Number of retries for operations (default: 3)
  --help               Show this help

Examples:
  $0 --version 1.0.0
  $0 --version 1.0.0 --dev --skip-notarize
  $0 --version 1.0.0 --target "dist/MyApp.app"
EOF
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$VERSION" ]; then
    log_error "Version is required. Use --version VERSION"
    exit 1
fi

# Setup logging
create_auto_log_file "signing_${VERSION}" "logs"

log_banner "Enhanced Signing and Notarization"
log_info "Version: $VERSION"
log_info "Build Type: $BUILD_TYPE"
log_info "Skip Notarization: $SKIP_NOTARIZATION"
log_info "Retry Count: $RETRY_COUNT"

# Log system information
log_system_info

# Determine environment type
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    ENV_TYPE="github"
    log_environment "github"
else
    ENV_TYPE="local"
    log_environment "local"
fi


# Function to sign a target with enhanced logging
sign_target_enhanced() {
    local target="$1"
    local identity="$2"
    local entitlements="$3"

    log_step "Signing Target: $(basename "$target")"
    log_security "Code Signing" "Starting signing process for $target"
    log_info "Target Path: $target"
    log_info "Signing Identity: $identity"
    log_info "Entitlements: $entitlements"

    # Clean up the identity string to ensure it's in the correct format
    local clean_identity=$(echo "$identity" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    log_info "Cleaned Signing Identity: $clean_identity"

    # Pre-signing checks
    if [ ! -e "$target" ]; then
        log_error "Target does not exist: $target"
        return 1
    fi

    # Clean up app bundle to remove resource forks and metadata
    if [[ "$target" == *.app ]]; then
        log_info "Performing deep clean of app bundle..."

        # Use deep_clean_app_bundle function if available
        if type -t deep_clean_app_bundle >/dev/null 2>&1; then
            if deep_clean_app_bundle "$target"; then
                log_success "App bundle cleaned successfully"
            else
                log_warning "Deep clean function failed, using fallback cleanup"
                # Basic fallback cleanup
                find "$target" -name ".DS_Store" -delete 2>/dev/null || true
                find "$target" -name "._*" -delete 2>/dev/null || true
                xattr -rc "$target" 2>/dev/null || true
            fi
        else
            # Try bulletproof clean first
            local repo_root="${SCRIPT_DIR}/../.."
            local bulletproof_script="${repo_root}/scripts/bulletproof_clean_app_bundle.py"

            # Debug: Show where we're looking
            log_info "Looking for bulletproof script at: $bulletproof_script"
            log_info "Current directory: $(pwd)"
            log_info "Script directory: $SCRIPT_DIR"

            # Also try relative to current directory
            if [ ! -f "$bulletproof_script" ]; then
                bulletproof_script="scripts/bulletproof_clean_app_bundle.py"
                log_info "Trying relative path: $bulletproof_script"
            fi

            if [ -f "$bulletproof_script" ]; then
                log_info "Found bulletproof clean script: $bulletproof_script"

                # Make script executable
                chmod +x "$bulletproof_script"

                # Run bulletproof clean with ditto method first
                if python3 "$bulletproof_script" --method ditto "$target"; then
                    log_success "Bulletproof clean completed successfully"
                else
                    log_warning "Bulletproof clean failed, trying auto method"
                    if python3 "$bulletproof_script" --method auto "$target"; then
                        log_success "Bulletproof clean succeeded with auto method"
                    else
                        log_error "All bulletproof clean methods failed"
                    fi
                fi
            else
                log_warning "Bulletproof clean script not found!"
                log_warning "Expected locations:"
                log_warning "  - ${repo_root}/scripts/bulletproof_clean_app_bundle.py"
                log_warning "  - scripts/bulletproof_clean_app_bundle.py"
                log_warning "Using standard cleanup (less effective)"

                # Standard cleanup
                log_info "Removing metadata files..."
                find "$target" -name ".DS_Store" -delete 2>/dev/null || true
                find "$target" -name "__MACOSX" -type d -exec rm -rf {} + 2>/dev/null || true
                find "$target" -name "._*" -delete 2>/dev/null || true

                log_info "Stripping extended attributes with xattr -rc..."
                xattr -rc "$target" 2>/dev/null || true

                # Try harder - remove Python cache files that often have xattrs
                log_info "Removing Python cache files..."
                find "$target" -name "*.pyc" -delete 2>/dev/null || true
                find "$target" -name "*.pyo" -delete 2>/dev/null || true
                find "$target" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

                # Remove .idea and other development directories
                find "$target" -name ".idea" -type d -exec rm -rf {} + 2>/dev/null || true
                find "$target" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
                find "$target" -name ".pytest_cache" -type d -exec rm -rf {} + 2>/dev/null || true

                # Use more aggressive xattr removal
                log_info "Using xattr -d * to delete ALL attributes..."
                find "$target" -type f -exec xattr -d "*" {} \; 2>/dev/null || true
                find "$target" -type d -exec xattr -d "*" {} \; 2>/dev/null || true

                # Try SetFile if available
                if command -v SetFile >/dev/null 2>&1; then
                    log_info "Using SetFile to clear Finder info..."
                    find "$target" -type f -exec SetFile -c "" -t "" {} \; 2>/dev/null || true
                fi

                # Use dot_clean utility
                log_info "Running dot_clean utility..."
                dot_clean -m "$(dirname "$target")" 2>/dev/null || true

                # Focus on frameworks specifically
                if [ -d "$target/Contents/Frameworks" ]; then
                    log_info "Aggressive framework cleaning..."
                    for framework in "$target/Contents/Frameworks"/*; do
                        if [ -e "$framework" ]; then
                            xattr -cr "$framework" 2>/dev/null || true
                            xattr -d "*" "$framework" 2>/dev/null || true
                            # Remove specific problematic attributes
                            xattr -d com.apple.FinderInfo "$framework" 2>/dev/null || true
                            xattr -d com.apple.ResourceFork "$framework" 2>/dev/null || true
                        fi
                    done
                fi

                # Try emergency shell script cleaner as last resort
                local emergency_script="${SCRIPT_DIR}/clean-app.sh"
                if [ -f "$emergency_script" ]; then
                    log_info "Using emergency shell script cleaner..."
                    chmod +x "$emergency_script"
                    if "$emergency_script" "$target"; then
                        log_success "Emergency cleaning completed"
                    else
                        log_warning "Emergency cleaning had issues"
                    fi
                else
                    log_warning "No emergency cleaner available"
                fi
            fi
        fi

        # Verify cleanup with detailed reporting
        log_info "Verifying cleanup results..."

        # Sign all native code first (frameworks, dylibs, etc.)
        log_info "Signing native code components..."

        # Sign all .dylib files
        find "$target" -name "*.dylib" -type f | while read -r dylib; do
            log_info "Signing dylib: $(basename "$dylib")"
            if ! codesign --force --sign "$clean_identity" --timestamp --options runtime "$dylib" 2>/dev/null; then
                log_warning "Failed to sign dylib: $dylib"
            fi
        done

        # Sign all .so files (Python extensions)
        find "$target" -name "*.so" -type f | while read -r so_file; do
            log_info "Signing Python extension: $(basename "$so_file")"
            if ! codesign --force --sign "$clean_identity" --timestamp --options runtime "$so_file" 2>/dev/null; then
                log_warning "Failed to sign Python extension: $so_file"
            fi
        done

        # Sign frameworks
        if [ -d "$target/Contents/Frameworks" ]; then
            find "$target/Contents/Frameworks" -name "*.framework" -type d | while read -r framework; do
                log_info "Signing framework: $(basename "$framework")"
                if ! codesign --force --sign "$clean_identity" --timestamp --options runtime "$framework" 2>/dev/null; then
                    log_warning "Failed to sign framework: $framework"
                fi
            done
        fi

        # Sign the main executable
        if [ -d "$target/Contents/MacOS/" ]; then
            local main_executable=""

            # First, try to find the app-specific executable (matching the app name)
            local app_name=$(basename "$target" .app)
            if [ -f "$target/Contents/MacOS/$app_name" ] && [ -x "$target/Contents/MacOS/$app_name" ]; then
                main_executable="$target/Contents/MacOS/$app_name"
                log_info "Found app-specific executable: $app_name"
            else
                # Fallback: find any executable, but exclude 'python' if there are other options
                local all_executables=($(find "$target/Contents/MacOS" -type f -perm +111))
                for exe in "${all_executables[@]}"; do
                    if [[ "$(basename "$exe")" != "python" ]]; then
                        main_executable="$exe"
                        break
                    fi
                done

                # If only python was found, use it
                if [ -z "$main_executable" ] && [ ${#all_executables[@]} -gt 0 ]; then
                    main_executable="${all_executables[0]}"
                fi
            fi

            if [ -n "$main_executable" ]; then
                log_info "Signing main executable: $(basename "$main_executable")"

                # Aggressive cleanup of the main executable specifically
                log_info "Performing aggressive cleanup of main executable..."

                # First pass: Remove all extended attributes
                xattr -c "$main_executable" 2>/dev/null || true
                xattr -d "*" "$main_executable" 2>/dev/null || true
                xattr -d com.apple.FinderInfo "$main_executable" 2>/dev/null || true
                xattr -d com.apple.ResourceFork "$main_executable" 2>/dev/null || true
                xattr -d com.apple.metadata:kMDItemWhereFroms "$main_executable" 2>/dev/null || true

                # Use SetFile if available to clear Finder info
                if command -v SetFile >/dev/null 2>&1; then
                    SetFile -c "" -t "" "$main_executable" 2>/dev/null || true
                fi

                # Use ditto to create a completely clean copy (strips all resource forks)
                local temp_executable="${main_executable}.clean"
                log_info "Creating resource-fork-free copy with ditto..."
                if ditto --norsrc --noextattr --noacl "$main_executable" "$temp_executable"; then
                    # Replace original with clean copy
                    mv "$temp_executable" "$main_executable"
                    log_info "Created clean copy of main executable with ditto"

                    # Final cleanup pass on the new file
                    xattr -c "$main_executable" 2>/dev/null || true

                    # Verify no extended attributes remain
                    local xattr_check=$(xattr "$main_executable" 2>/dev/null || echo "")
                    if [ -z "$xattr_check" ]; then
                        log_info "Verified: No extended attributes on main executable"
                    else
                        log_warning "Warning: Extended attributes still present: $xattr_check"
                        # Try specific removal of problematic attributes
                        xattr -d com.apple.provenance "$main_executable" 2>/dev/null || true
                        xattr -d com.apple.quarantine "$main_executable" 2>/dev/null || true
                        xattr -d com.apple.metadata:kMDItemWhereFroms "$main_executable" 2>/dev/null || true
                        xattr -d com.apple.metadata:kMDItemDownloadedDate "$main_executable" 2>/dev/null || true
                        # Final aggressive removal
                        xattr -d "*" "$main_executable" 2>/dev/null || true

                        # Verify again
                        local final_check=$(xattr "$main_executable" 2>/dev/null || echo "")
                        if [ -z "$final_check" ]; then
                            log_info "Successfully removed all extended attributes"
                        else
                            log_error "Failed to remove extended attributes: $final_check"

                            # Last resort: recreate the file completely to bypass stubborn attributes
                            log_info "Attempting file recreation to bypass stubborn attributes..."
                            local recreated_executable="${main_executable}.recreated"

                            # Copy the binary content to a new file
                            if dd if="$main_executable" of="$recreated_executable" bs=1024 2>/dev/null; then
                                # Set executable permissions
                                chmod +x "$recreated_executable"

                                # Replace original with recreated file
                                mv "$recreated_executable" "$main_executable"
                                log_info "Successfully recreated executable file"

                                # Final verification
                                local recreated_check=$(xattr "$main_executable" 2>/dev/null || echo "")
                                if [ -z "$recreated_check" ]; then
                                    log_info "Verified: Recreated file has no extended attributes"
                                else
                                    log_warning "Recreated file still has attributes: $recreated_check"
                                fi
                            else
                                log_error "Failed to recreate executable file"
                            fi
                        fi
                    fi
                else
                    log_warning "Failed to create clean copy with ditto, using fallback"
                    # Fallback: try cp and aggressive cleanup
                    if cp "$main_executable" "$temp_executable"; then
                        xattr -c "$temp_executable" 2>/dev/null || true
                        mv "$temp_executable" "$main_executable"
                        log_info "Created clean copy of main executable with cp"
                    fi
                fi

                if ! codesign --force --sign "$clean_identity" --timestamp --options runtime --entitlements "$entitlements" "$main_executable"; then
                    log_error "Failed to sign main executable: $main_executable"
                    return 1
                fi
            else
                log_warning "No main executable found in $target/Contents/MacOS/"
            fi
        fi
        # Enhanced resource fork and detritus removal
        log_info "Enhanced cleanup for signing..."

        # First pass: Remove all extended attributes recursively
        log_info "Removing extended attributes..."
        find "$target" -exec xattr -c {} \; 2>/dev/null || true

        # Second pass: Remove specific problematic attributes
        log_info "Removing specific problematic attributes..."
        find "$target" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
        find "$target" -exec xattr -d com.apple.ResourceFork {} \; 2>/dev/null || true
        find "$target" -exec xattr -d com.apple.metadata:kMDItemWhereFroms {} \; 2>/dev/null || true

        # Remove .DS_Store and resource forks
        log_info "Removing metadata files..."
        find "$target" -name ".DS_Store" -delete 2>/dev/null || true
        find "$target" -name "._*" -delete 2>/dev/null || true
        find "$target" -name "__MACOSX" -type d -exec rm -rf {} + 2>/dev/null || true

        # Use dot_clean utility to remove AppleDouble files
        log_info "Running dot_clean utility..."
        dot_clean -m "$target" 2>/dev/null || true

        # Use ditto to create a clean copy (this strips resource forks)
        log_info "Creating clean copy with ditto..."
        TEMP_APP="/tmp/$(basename "$target").clean"
        rm -rf "$TEMP_APP" 2>/dev/null || true
        if ditto --norsrc --noextattr --noacl "$target" "$TEMP_APP"; then
            rm -rf "$target"
            mv "$TEMP_APP" "$target"
            log_info "Created clean copy of app bundle"
        else
            log_warning "Failed to create clean copy, proceeding with original"
        fi

        # Final cleanup pass
        log_info "Final cleanup pass..."
        find "$target" -exec xattr -c {} \; 2>/dev/null || true
        # Finally, sign the entire app bundle
        log_info "Signing entire app bundle..."
        if codesign --force --sign "$clean_identity" --timestamp --options runtime --entitlements "$entitlements" --deep "$target"; then
            log_success "App bundle signed successfully"
        else
            log_error "Failed to sign app bundle"
            return 1
        fi

        # Verify the signature
        log_info "Verifying app bundle signature..."
        if codesign --verify --deep --strict --verbose=2 "$target" 2>&1; then
            log_success "App bundle signature verified"
        else
            log_error "App bundle signature verification failed"
            return 1
        fi

    elif [[ "$target" == *.pkg ]]; then
        # For .pkg files, use productsign
        log_info "Signing .pkg file..."

        # Get installer identity
        local installer_identity
        installer_identity=$(security find-identity -v -p codesigning | grep "Developer ID Installer" | head -1 | sed 's/.*) \(.*\)/\1/' | tr -d '"')

        if [ -z "$installer_identity" ]; then
           log_warning "No Developer ID Installer certificate found, skipping pkg signing"
           return 0
        fi

        log_info "Using installer identity: $installer_identity"

        # Create signed version
        local signed_pkg="${target%.pkg}-signed.pkg"
        if productsign --sign "$installer_identity" "$target" "$signed_pkg"; then
            # Replace original with signed version
            mv "$signed_pkg" "$target"
            log_success "Package signed successfully"
        else
            log_error "Failed to sign package"
            return 1
        fi

        # Verify package signature
        log_info "Verifying package signature..."
        if pkgutil --check-signature "$target" >/dev/null 2>&1; then
            log_success "Package signature verified"
        else
            log_error "Package signature verification failed"
            return 1
        fi
    fi

    return 0
}

# Function to notarize a target with enhanced logging
notarize_target_enhanced() {
    local target="$1"

    if [ "$SKIP_NOTARIZATION" = true ]; then
        log_info "Skipping notarization (--skip-notarize specified)"
        return 0
    fi

    log_step "Notarizing Target: $(basename "$target")"
    log_security "Notarization" "Starting notarization process for $target"

    # Check if required credentials are available
    if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_ID_PASSWORD:-}" ]; then
        log_error "Apple ID credentials not available for notarization"
        return 1
    fi

    # Create a temporary zip for app bundles (required for notarization)
    local notarize_file="$target"
    local temp_zip=""

    if [[ "$target" == *.app ]]; then
        temp_zip="/tmp/$(basename "$target" .app)-$(date +%s).zip"
        log_info "Creating zip archive for notarization: $temp_zip"

        if ! ditto -c -k --keepParent "$target" "$temp_zip"; then
            log_error "Failed to create zip archive for notarization"
            return 1
        fi
        notarize_file="$temp_zip"
    fi

    # Submit for notarization using notarytool (preferred) or altool (fallback)
    log_info "Submitting for notarization..."

    local bundle_id="com.r2midi.$(basename "$target" | sed 's/\.[^.]*$//' | tr '[:upper:]' '[:lower:]')"
    local submission_id=""

    # Try notarytool first (macOS 12+)
    if command -v xcrun >/dev/null 2>&1 && xcrun notarytool --help >/dev/null 2>&1; then
        log_info "Using xcrun notarytool for notarization"

        # Create keychain profile for notarytool
        local profile_name="r2midi-notarization-$(date +%s)"
        if xcrun notarytool store-credentials "$profile_name" --apple-id "${APPLE_ID}" --password "${APPLE_ID_PASSWORD}" --team-id "${APPLE_TEAM_ID:-}" 2>/dev/null; then
            log_info "Created notarytool keychain profile"

            # Submit for notarization
            local notarize_output
            if notarize_output=$(xcrun notarytool submit "$notarize_file" --keychain-profile "$profile_name" --wait 2>&1); then
                log_success "Notarization completed successfully"
                log_info "Notarization output: $notarize_output"
            else
                log_error "Notarization failed"
                log_error "Output: $notarize_output"

                # Clean up keychain profile
                xcrun notarytool delete-credentials "$profile_name" 2>/dev/null || true

                # Clean up temp zip
                [ -n "$temp_zip" ] && rm -f "$temp_zip"
                return 1
            fi

            # Clean up keychain profile
            xcrun notarytool delete-credentials "$profile_name" 2>/dev/null || true
        else
            log_warning "Failed to create notarytool keychain profile, falling back to altool"
        fi
    fi

    # Fallback to altool if notarytool failed or is not available
    if [ -z "$notarize_output" ] || [[ "$notarize_output" == *"error"* ]]; then
        log_info "Using xcrun altool for notarization (fallback)"

        local altool_output
        if altool_output=$(xcrun altool --notarize-app --file "$notarize_file" --primary-bundle-id "$bundle_id" --username "${APPLE_ID}" --password "${APPLE_ID_PASSWORD}" ${APPLE_TEAM_ID:+--asc-provider "$APPLE_TEAM_ID"} 2>&1); then
            # Extract RequestUUID from output
            submission_id=$(echo "$altool_output" | grep "RequestUUID" | awk '{print $NF}')

            if [ -n "$submission_id" ]; then
                log_info "Notarization submitted with ID: $submission_id"

                # Wait for notarization to complete
                log_info "Waiting for notarization to complete..."
                local max_attempts=30
                local attempt=0

                while [ $attempt -lt $max_attempts ]; do
                    sleep 30
                    attempt=$((attempt + 1))

                    local status_output
                    if status_output=$(xcrun altool --notarization-info "$submission_id" --username "${APPLE_ID}" --password "${APPLE_ID_PASSWORD}" 2>&1); then
                        if echo "$status_output" | grep -q "Status: success"; then
                            log_success "Notarization completed successfully"
                            break
                        elif echo "$status_output" | grep -q "Status: invalid"; then
                            log_error "Notarization failed - invalid"
                            log_error "Status output: $status_output"

                            # Clean up temp zip
                            [ -n "$temp_zip" ] && rm -f "$temp_zip"
                            return 1
                        else
                            log_info "Notarization in progress... (attempt $attempt/$max_attempts)"
                        fi
                    else
                        log_warning "Failed to check notarization status"
                    fi
                done

                if [ $attempt -eq $max_attempts ]; then
                    log_error "Notarization timed out"

                    # Clean up temp zip
                    [ -n "$temp_zip" ] && rm -f "$temp_zip"
                    return 1
                fi
            else
                log_error "Failed to extract submission ID from altool output"
                log_error "Output: $altool_output"

                # Clean up temp zip
                [ -n "$temp_zip" ] && rm -f "$temp_zip"
                return 1
            fi
        else
            log_error "Failed to submit for notarization with altool"
            log_error "Output: $altool_output"

            # Clean up temp zip
            [ -n "$temp_zip" ] && rm -f "$temp_zip"
            return 1
        fi
    fi

    # Staple the notarization ticket
    if [[ "$target" == *.app ]]; then
        log_info "Stapling notarization ticket to app bundle..."
        if xcrun stapler staple "$target"; then
            log_success "Notarization ticket stapled successfully"
        else
            log_warning "Failed to staple notarization ticket (app may still work)"
        fi
    elif [[ "$target" == *.pkg ]]; then
        log_info "Stapling notarization ticket to package..."
        if xcrun stapler staple "$target"; then
            log_success "Notarization ticket stapled successfully"
        else
            log_warning "Failed to staple notarization ticket (package may still work)"
        fi
    fi

    # Clean up temp zip
    [ -n "$temp_zip" ] && rm -f "$temp_zip"

    log_success "Notarization process completed"
    return 0
}

# Function to setup keychain for local builds
setup_keychain_local() {
    local keychain_name="$1"

    log_info "Setting up keychain for local build"

    # Check if we're in local environment
    if [ "$ENV_TYPE" = "local" ]; then
        local p12_path="apple_credentials/certificates/installer_cert.p12"
        local p12_password="x2G2srk2RHtp"

        if [ -f "$p12_path" ]; then
            log_info "Found local P12 certificate: $p12_path"

            # Create temporary keychain
            local temp_keychain="/tmp/${keychain_name}-$(date +%s).keychain"

            # Create keychain
            if security create-keychain -p "temp_password" "$temp_keychain"; then
                log_success "Created temporary keychain: $temp_keychain"

                # Import P12 certificate
                if security import "$p12_path" -k "$temp_keychain" -P "$p12_password" -T /usr/bin/codesign -T /usr/bin/productsign; then
                    log_success "Imported P12 certificate to keychain"

                    # Add to keychain search list
                    security list-keychains -d user -s "$temp_keychain" $(security list-keychains -d user | tr -d '"')

                    # Unlock keychain
                    security unlock-keychain -p "temp_password" "$temp_keychain"

                    # Set keychain settings
                    security set-keychain-settings -t 3600 -l "$temp_keychain"

                    # Store keychain path for cleanup
                    echo "TEMP_KEYCHAIN=\"$temp_keychain\"" > .local_build_env

                    return 0
                else
                    log_error "Failed to import P12 certificate"
                    security delete-keychain "$temp_keychain" 2>/dev/null || true
                    return 1
                fi
            else
                log_error "Failed to create temporary keychain"
                return 1
            fi
        else
            log_warning "Local P12 certificate not found: $p12_path"
            return 1
        fi
    else
        log_info "Not in local environment, skipping local keychain setup"
        return 0
    fi
}

# Function to list signing identities
list_signing_identities() {
    local cert_type="$1"

    log_info "Listing signing identities for: $cert_type"

    local identities=$(security find-identity -v -p codesigning | grep "$cert_type" || true)

    if [ -z "$identities" ]; then
        log_warning "No $cert_type certificates found"
        return 1
    fi

    log_info "Found signing identities:"
    echo "$identities" | while read -r line; do
        log_info "  $line"
    done

    return 0
}

# Function to cleanup keychain
cleanup_keychain() {
    local keychain_name="$1"

    log_info "Cleaning up keychain: $keychain_name"

    # Check if we have a temporary keychain to clean up
    if [ -f .local_build_env ]; then
        source .local_build_env
        if [ -n "${TEMP_KEYCHAIN:-}" ]; then
            log_info "Removing temporary keychain: $TEMP_KEYCHAIN"
            security delete-keychain "$TEMP_KEYCHAIN" 2>/dev/null || true
        fi
        rm -f .local_build_env
    fi

    return 0
}


# Function to find and process targets for signing
find_and_process_targets() {
    # Note: No logging in this function to keep stdout clean for return values
    local found_targets=()

    # Look for .app bundles in common locations
    while IFS= read -r -d '' app_path; do
        if [ -d "$app_path" ]; then
            found_targets+=("$app_path")
        fi
    done < <(find . -name "*.app" -type d -print0 2>/dev/null)

    # Look for .pkg files in artifacts directory
    if [ -d "artifacts" ]; then
        while IFS= read -r -d '' pkg_path; do
            if [ -f "$pkg_path" ]; then
                found_targets+=("$pkg_path")
            fi
        done < <(find artifacts -name "*.pkg" -type f -print0 2>/dev/null)
    fi

    # Look for .pkg files in build directories
    while IFS= read -r -d '' pkg_path; do
        if [ -f "$pkg_path" ]; then
            found_targets+=("$pkg_path")
        fi
    done < <(find . -path "*/build*/dist/*.pkg" -type f -print0 2>/dev/null)

    # If a specific target was provided, use only that
    if [ -n "$TARGET_PATH" ]; then
        if [ -e "$TARGET_PATH" ]; then
            echo "$TARGET_PATH"
            return 0
        else
            return 1
        fi
    fi

    # Return found targets
    if [ ${#found_targets[@]} -eq 0 ]; then
        return 1
    fi

    for target in "${found_targets[@]}"; do
        echo "$target"
    done

    return 0
}

# Main execution
main() {
    local start_time=$(start_timer)

    log_step "Starting Enhanced Signing Process"

    # Clean app bundles before signing and notarizing
    log_step "Cleaning App Bundles"
    log_info "Running clean-app.sh on all found app bundles..."

    # Find all .app bundles and clean them
    local cleaned_apps=0
    while IFS= read -r -d '' app_path; do
        if [ -d "$app_path" ]; then
            log_info "Cleaning app bundle: $(basename "$app_path")"
            if [ -f "$SCRIPT_DIR/clean-app.sh" ]; then
                if "$SCRIPT_DIR/clean-app.sh" "$app_path"; then
                    log_success "Successfully cleaned: $(basename "$app_path")"
                    cleaned_apps=$((cleaned_apps + 1))
                else
                    log_warning "Failed to clean: $(basename "$app_path")"
                fi
            else
                log_warning "clean-app.sh not found at $SCRIPT_DIR/clean-app.sh"
            fi
        fi
    done < <(find . -name "*.app" -type d -print0 2>/dev/null)

    if [ $cleaned_apps -gt 0 ]; then
        log_success "Cleaned $cleaned_apps app bundle(s) before signing"
    else
        log_info "No app bundles found to clean"
    fi

    # Setup keychain for local builds
    log_step "Keychain Setup"
    if setup_keychain_local "build"; then
        log_success "Keychain setup completed successfully"
    else
        log_warning "Keychain setup failed, proceeding with existing certificates"
    fi

    # Get certificate information
    log_step "Certificate Discovery and Validation"
    list_signing_identities "Developer ID Application" || {
        log_error "No Developer ID Application certificates found"
        exit 1
    }

    # Select signing identity
    log_info "Selecting signing identity for: Developer ID Application"
    local signing_identity
    signing_identity=$(select_signing_identity "Developer ID Application" "${APPLE_TEAM_ID:-}")

    if [ -z "$signing_identity" ]; then
        log_error "No valid signing identity found"
        exit 1
    fi

    log_info "Selected identity: $signing_identity"
    log_info "Selected signing identity: $signing_identity"

    # Validate certificate
    log_info "Validating certificate: $signing_identity"
    if ! validate_certificate "$signing_identity"; then
        log_error "Certificate validation failed"
        exit 1
    fi

    log_success "Certificate validation passed"

    # Find targets
    log_info "Searching for targets to sign and notarize..."
    local targets=()
    local targets_output
    if targets_output=$(find_and_process_targets); then
        # Log what we found
        echo "$targets_output" | while read -r target; do
            if [ -n "$target" ]; then
                log_info "Found target: $target"
            fi
        done

        # Read targets into array, handling paths with spaces
        while IFS= read -r target; do
            if [ -n "$target" ]; then
                targets+=("$target")
            fi
        done <<< "$targets_output"

        log_info "Total targets found: ${#targets[@]}"
    else
        log_error "No valid targets found"
        exit 1
    fi

    # Create entitlements file
    local entitlements_file="/tmp/enhanced-entitlements-$(date +%s).plist"

    # Create entitlements file using echo to avoid heredoc issues
    echo '<?xml version="1.0" encoding="UTF-8"?>' > "$entitlements_file"
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> "$entitlements_file"
    echo '<plist version="1.0">' >> "$entitlements_file"
    echo '<dict>' >> "$entitlements_file"
    echo '    <key>com.apple.security.cs.allow-jit</key>' >> "$entitlements_file"
    echo '    <true/>' >> "$entitlements_file"
    echo '    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>' >> "$entitlements_file"
    echo '    <true/>' >> "$entitlements_file"
    echo '    <key>com.apple.security.cs.disable-library-validation</key>' >> "$entitlements_file"
    echo '    <true/>' >> "$entitlements_file"
    echo '    <key>com.apple.security.network.client</key>' >> "$entitlements_file"
    echo '    <true/>' >> "$entitlements_file"
    echo '    <key>com.apple.security.network.server</key>' >> "$entitlements_file"
    echo '    <true/>' >> "$entitlements_file"
    echo '    <key>com.apple.security.files.user-selected.read-write</key>' >> "$entitlements_file"
    echo '    <true/>' >> "$entitlements_file"
    echo '</dict>' >> "$entitlements_file"
    echo '</plist>' >> "$entitlements_file"

    log_info "Created entitlements file: $entitlements_file"

    # Process each target
    local overall_success=true
    local processed_count=0
    local total_count=${#targets[@]}

    for target in "${targets[@]}"; do
        processed_count=$((processed_count + 1))
        log_progress "$processed_count" "$total_count" "Processing $(basename "$target")"

        # Sign the target
        if sign_target_enhanced "$target" "$signing_identity" "$entitlements_file"; then
            # Notarize the target
            if notarize_target_enhanced "$target"; then
                log_success "Successfully processed: $(basename "$target")"
            else
                log_error "Notarization failed for: $(basename "$target")"
                if [ "$BUILD_TYPE" != "dev" ]; then
                    overall_success=false
                fi
            fi
        else
            log_error "Signing failed for: $(basename "$target")"
            overall_success=false
        fi
    done

    # Cleanup
    if [ -f "$entitlements_file" ]; then
        rm -f "$entitlements_file"
        log_info "Cleaned up entitlements file"
    fi

    # Cleanup keychain if it was created
    cleanup_keychain "build"

    # Final summary
    local duration=$(end_timer "$start_time" "Enhanced Signing Process")
    log_step "Enhanced Signing Summary"

    if [ "$overall_success" = true ]; then
        log_success "All targets processed successfully!"
        create_summary_report "Enhanced Signing and Notarization" "SUCCESS" "Processed $total_count targets in ${duration}s"
        exit 0
    else
        log_error "Some targets failed processing"
        create_summary_report "Enhanced Signing and Notarization" "FAILED" "Some of $total_count targets failed"
        exit 1
    fi
}

# Run main function
main "$@"
