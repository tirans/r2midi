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

# Function to find and process targets
find_and_process_targets() {
    local targets=()

    if [ -n "$TARGET_PATH" ]; then
        if [ -e "$TARGET_PATH" ]; then
            targets=("$TARGET_PATH")
            log_info "Using specified target: $TARGET_PATH"
        else
            log_error "Specified target does not exist: $TARGET_PATH"
            return 1
        fi
    else
        # Auto-discover targets
        log_info "Auto-discovering targets..."

        # Look for app bundles in common locations
        local search_paths=("." "build_client/dist" "build_server/dist" "dist")

        for search_path in "${search_paths[@]}"; do
            if [ -d "$search_path" ]; then
                while IFS= read -r -d '' app; do
                    targets+=("$app")
                    log_info "Found app bundle: $app"
                done < <(find "$search_path" -name "*.app" -type d -print0 2>/dev/null)
            fi
        done

        # Look for pkg files in artifacts directory
        if [ -d "artifacts" ]; then
            while IFS= read -r -d '' pkg; do
                targets+=("$pkg")
                log_info "Found package: $pkg"
            done < <(find "artifacts" -name "*.pkg" -type f -print0 2>/dev/null)
        fi
    fi

    if [ ${#targets[@]} -eq 0 ]; then
        log_warning "No targets found for signing"
        return 1
    fi

    printf '%s\n' "${targets[@]}"
    return 0
}

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
                
                # Try emergency shell script cleaner as last resort
                local emergency_script="${SCRIPT_DIR}/emergency-clean-app.sh"
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
        
        # Verify cleanup
        local final_xattr_count=$(find "$target" -exec xattr -l {} \; 2>/dev/null | wc -l || echo "0")
        log_info "Final extended attributes count: $final_xattr_count"
        
        if [ "$final_xattr_count" -gt 0 ]; then
            log_warning "Some extended attributes remain after cleanup"
        else
            log_success "App bundle is clean"
        fi
    fi

    # Get target information
    if [ -d "$target" ]; then
        local target_size=$(du -sh "$target" 2>/dev/null | cut -f1 || echo "unknown")
        log_info "Target Type: Directory/Bundle"
        log_info "Target Size: $target_size"

        # Check if it's an app bundle
        if [[ "$target" == *.app ]]; then
            log_info "App Bundle detected"
            if [ -f "$target/Contents/Info.plist" ]; then
                local bundle_id=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$target/Contents/Info.plist" 2>/dev/null || echo "unknown")
                local bundle_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$target/Contents/Info.plist" 2>/dev/null || echo "unknown")
                log_info "Bundle ID: $bundle_id"
                log_info "Bundle Version: $bundle_version"
            fi
        fi
    else
        local target_size=$(ls -lh "$target" 2>/dev/null | awk '{print $5}' || echo "unknown")
        log_info "Target Type: File"
        log_info "Target Size: $target_size"
    fi

    # Pre-signing verification
    log_info "Pre-signing verification..."
    local pre_sign_status=$(codesign --verify --verbose "$target" 2>&1 || echo "Not signed or invalid signature")
    log_info "Pre-signing status: $pre_sign_status"

    # Build signing command
    local sign_command="codesign --force --options runtime --timestamp --deep --sign \"$identity\""
    if [ -n "$entitlements" ] && [ -f "$entitlements" ]; then
        sign_command="$sign_command --entitlements \"$entitlements\""
    fi
    sign_command="$sign_command \"$target\""

    log_command "$sign_command"

    # Execute signing with retry
    if execute_with_retry "$sign_command" "Code Signing $(basename "$target")" "$RETRY_COUNT"; then
        # Post-signing verification
        log_info "Post-signing verification..."
        local post_sign_status=$(codesign --verify --verbose "$target" 2>&1 || echo "Verification failed")
        log_info "Post-signing status: $post_sign_status"

        # Detailed signature information
        local signature_info=$(codesign --display --verbose=4 "$target" 2>&1 || echo "Could not get signature info")
        log_info "Signature details:"
        echo "$signature_info" | while read -r line; do
            log_info "  $line"
        done

        log_success "Successfully signed: $(basename "$target")"
        log_security "Code Signing" "Successfully signed $target with identity: $identity"
        return 0
    else
        log_error "Failed to sign: $(basename "$target")"
        log_security "Code Signing" "Failed to sign $target"
        return 1
    fi
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
    log_info "Target Path: $target"

    # Check if notarytool is available
    if ! command -v xcrun >/dev/null 2>&1 || ! xcrun --find notarytool >/dev/null 2>&1; then
        log_warning "notarytool not available - skipping notarization"
        return 0
    fi

    # Check for required environment variables
    if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_ID_PASSWORD:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ]; then
        log_warning "Apple ID credentials not configured - skipping notarization"
        log_info "Required: APPLE_ID, APPLE_ID_PASSWORD, APPLE_TEAM_ID"
        return 0
    fi

    log_info "Apple ID: $APPLE_ID"
    log_info "Team ID: $APPLE_TEAM_ID"

    # Create temporary zip for notarization if it's an app bundle
    local notarize_file="$target"
    local temp_zip=""

    if [[ "$target" == *.app ]]; then
        temp_zip="/tmp/$(basename "$target" .app)-notarize-$(date +%s).zip"
        log_info "Creating temporary zip for notarization: $temp_zip"

        if ditto -c -k --keepParent "$target" "$temp_zip"; then
            notarize_file="$temp_zip"
            log_success "Created notarization zip"
        else
            log_error "Failed to create notarization zip"
            return 1
        fi
    fi

    # Submit for notarization
    log_info "Submitting for notarization..."
    local notarize_command="xcrun notarytool submit \"$notarize_file\" --apple-id \"$APPLE_ID\" --password \"$APPLE_ID_PASSWORD\" --team-id \"$APPLE_TEAM_ID\" --wait"

    if execute_with_retry "$notarize_command" "Notarization $(basename "$target")" "$RETRY_COUNT" 10 1800; then
        log_success "Notarization completed successfully"
        log_security "Notarization" "Successfully notarized $target"

        # Staple the notarization (for app bundles)
        if [[ "$target" == *.app ]]; then
            log_info "Stapling notarization to app bundle..."
            if xcrun stapler staple "$target"; then
                log_success "Notarization stapled successfully"
                log_security "Notarization" "Successfully stapled notarization to $target"
            else
                log_warning "Failed to staple notarization (app may still work)"
            fi
        fi

        # Clean up temporary zip
        if [ -n "$temp_zip" ] && [ -f "$temp_zip" ]; then
            rm -f "$temp_zip"
            log_info "Cleaned up temporary zip"
        fi

        return 0
    else
        log_error "Notarization failed"
        log_security "Notarization" "Failed to notarize $target"

        # Clean up temporary zip on failure
        if [ -n "$temp_zip" ] && [ -f "$temp_zip" ]; then
            rm -f "$temp_zip"
        fi

        return 1
    fi
}

# Main execution
main() {
    local start_time=$(start_timer)

    log_step "Starting Enhanced Signing Process"

    # Setup keychain from app configuration
    log_step "Keychain Setup from Configuration"
    if setup_keychain_from_config "apple_credentials/config/app_config.json" "build"; then
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
    local signing_identity
    signing_identity=$(select_signing_identity "Developer ID Application" "${APPLE_TEAM_ID:-}")

    if [ -z "$signing_identity" ]; then
        log_error "No valid signing identity found"
        exit 1
    fi

    log_info "Selected signing identity: $signing_identity"

    # Validate certificate
    if ! validate_certificate "$signing_identity"; then
        log_error "Certificate validation failed"
        exit 1
    fi

    # Find targets
    local targets=()
    local targets_output
    if ! targets_output=$(find_and_process_targets); then
        log_error "No valid targets found"
        exit 1
    fi

    # Read targets into array, handling paths with spaces
    while IFS= read -r target; do
        if [ -n "$target" ]; then
            targets+=("$target")
        fi
    done <<< "$targets_output"

    # Create entitlements file
    local entitlements_file="/tmp/enhanced-entitlements-$(date +%s).plist"
    cat > "$entitlements_file" << EOF
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
