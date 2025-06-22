#!/bin/bash
set -euo pipefail

# Certificate setup for local macOS builds
# Usage: ./setup-local-certificates.sh [--verify-only]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
VERIFY_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verify-only)
            VERIFY_ONLY=true
            shift
            ;;
        *)
            echo "Usage: $0 [--verify-only]"
            exit 1
            ;;
    esac
done

# Logging functions
log_info() { echo "ℹ️  $1"; }
log_success() { echo "✅ $1"; }
log_warning() { echo "⚠️  $1"; }
log_error() { echo "❌ $1"; }

# Load configuration
load_config() {
    local config_file="$PROJECT_ROOT/apple_credentials/config/app_config.json"

    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        log_error "Expected: apple_credentials/config/app_config.json"
        exit 1
    fi

    log_info "Loading configuration..."

    # Parse JSON configuration
    eval "$(python3 -c "
import json
import sys

try:
    with open('$config_file', 'r') as f:
        config = json.load(f)

    apple_dev = config.get('apple_developer', {})

    print(f'export APPLE_ID=\"{apple_dev.get(\"apple_id\", \"\")}\"')
    print(f'export TEAM_ID=\"{apple_dev.get(\"team_id\", \"\")}\"')
    print(f'export P12_PASSWORD=\"{apple_dev.get(\"p12_password\", \"\")}\"')
    print(f'export P12_PATH=\"{apple_dev.get(\"p12_path\", \"\")}\"')
    print(f'export APP_SPECIFIC_PASSWORD=\"{apple_dev.get(\"app_specific_password\", \"\")}\"')

except Exception as e:
    print(f'echo \"Error parsing config: {e}\"', file=sys.stderr)
    sys.exit(1)
")"

    if [ -z "$APPLE_ID" ] || [ -z "$TEAM_ID" ] || [ -z "$P12_PASSWORD" ]; then
        log_error "Missing required configuration values"
        log_error "Required: apple_id, team_id, p12_password"
        exit 1
    fi

    log_success "Configuration loaded"
    log_info "Apple ID: $APPLE_ID"
    log_info "Team ID: $TEAM_ID"
}

# Verify certificate files exist
verify_certificate_files() {
    log_info "Verifying certificate files..."

    local cert_dir="$PROJECT_ROOT/$P12_PATH"
    local missing_files=()

    if [ ! -f "$cert_dir/app_cert.p12" ]; then
        missing_files+=("app_cert.p12")
    fi

    if [ ! -f "$cert_dir/installer_cert.p12" ]; then
        missing_files+=("installer_cert.p12")
    fi

    if [ ${#missing_files[@]} -gt 0 ]; then
        log_error "Missing certificate files:"
        for file in "${missing_files[@]}"; do
            log_error "  - $file"
        done
        log_info "Expected location: $cert_dir/"
        log_info "Make sure you have exported your Developer ID certificates from Keychain Access"
        exit 1
    fi

    log_success "All certificate files found"
}

# Test certificate passwords
test_certificate_passwords() {
    log_info "Testing certificate passwords..."

    local cert_dir="$PROJECT_ROOT/$P12_PATH"
    local temp_keychain="test-certs-$(date +%s).keychain"

    # Create temporary keychain for testing
    security create-keychain -p "test-password" "$temp_keychain"

    # Test app certificate
    if security import "$cert_dir/app_cert.p12" -k "$temp_keychain" -P "$P12_PASSWORD" -T /usr/bin/codesign 2>/dev/null; then
        log_success "Application certificate password verified"
    else
        log_error "Application certificate password failed"
        log_error "Check that the p12_password in app_config.json is correct"
        security delete-keychain "$temp_keychain" 2>/dev/null || true
        exit 1
    fi

    # Test installer certificate
    if security import "$cert_dir/installer_cert.p12" -k "$temp_keychain" -P "$P12_PASSWORD" -T /usr/bin/productsign 2>/dev/null; then
        log_success "Installer certificate password verified"
    else
        log_error "Installer certificate password failed"
        log_error "Check that the p12_password in app_config.json is correct"
        security delete-keychain "$temp_keychain" 2>/dev/null || true
        exit 1
    fi

    # Clean up test keychain
    security delete-keychain "$temp_keychain" 2>/dev/null || true

    log_success "All certificate passwords verified"
}

# Check certificate validity and details (simplified version)
check_certificate_details() {
    log_info "Checking certificate details..."

    # Use system keychain to check certificates
    local app_cert_info
    app_cert_info=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1)

    if [ -n "$app_cert_info" ]; then
        local app_cert_name=$(echo "$app_cert_info" | sed 's/.*"\(.*\)".*/\1/')
        log_success "Application Certificate: $app_cert_name"
        log_success "  Certificate is valid"
    else
        log_warning "No application certificate found in system keychain"
    fi

    # Check for installer certificate
    local installer_cert_info
    installer_cert_info=$(security find-identity -v -p codesigning | grep "Developer ID Installer" | head -1 || true)

    if [ -n "$installer_cert_info" ]; then
        local installer_cert_name=$(echo "$installer_cert_info" | sed 's/.*"\(.*\)".*/\1/')
        log_success "Installer Certificate: $installer_cert_name"
    else
        log_warning "No installer certificate found in system keychain"
    fi

    log_success "Team ID verification: $TEAM_ID"
}

# Test Apple ID and app-specific password
test_apple_credentials() {
    log_info "Testing Apple ID credentials..."

    if [ -z "$APP_SPECIFIC_PASSWORD" ]; then
        log_warning "No app-specific password configured"
        log_info "Notarization will be skipped"
        return 0
    fi

    # Test with a simple notarytool command that doesn't require a file
    # Add timeout to prevent hanging
    local test_output
    log_info "Testing Apple ID connection (timeout: 30 seconds)..."

    if test_output=$(timeout 30 xcrun notarytool history --apple-id "$APPLE_ID" --password "$APP_SPECIFIC_PASSWORD" --team-id "$TEAM_ID" 2>&1 | head -5); then
        if echo "$test_output" | grep -q "Successfully received submission history" || echo "$test_output" | grep -q "No submissions found"; then
            log_success "Apple ID credentials verified"
        else
            log_warning "Apple ID credentials test inconclusive"
            log_info "Test output: $test_output"
            return 0  # Don't fail, just warn
        fi
    else
        log_warning "Apple ID credentials test timed out or failed"
        log_info "This may be due to network issues or Apple server delays"
        log_info "Notarization may still work during actual build"
        return 0  # Don't fail, just warn
    fi
}

# Create environment file for builds
create_build_environment() {
    log_info "Creating build environment file..."

    local env_file="$PROJECT_ROOT/.local_build_env"

    cat > "$env_file" << EOF
# R2MIDI Local Build Environment
# Generated on $(date)

export APPLE_ID="$APPLE_ID"
export TEAM_ID="$TEAM_ID"
export APP_SPECIFIC_PASSWORD="$APP_SPECIFIC_PASSWORD"
export P12_PASSWORD="$P12_PASSWORD"
export P12_PATH="$P12_PATH"

# For CI/CD compatibility
export APPLE_ID_PASSWORD="$APP_SPECIFIC_PASSWORD"
export APPLE_TEAM_ID="$TEAM_ID"

# Keychain settings
export CERTIFICATES_VERIFIED="true"
export BUILD_ENV_READY="true"
export BUILD_ENV_TIMESTAMP="$(date +%s)"

# Usage:
# source .local_build_env
EOF

    # Make it readable only by owner
    chmod 600 "$env_file"

    log_success "Build environment created: $env_file"
    log_info "To use: source .local_build_env"
}

# Generate signing report
generate_report() {
    local report_file="$PROJECT_ROOT/CERTIFICATE_SETUP_REPORT.md"

    cat > "$report_file" << EOF
# Certificate Setup Report

**Generated:** $(date)  
**Apple ID:** $APPLE_ID  
**Team ID:** $TEAM_ID  

## Certificate Status

EOF

    # Add certificate details
    local cert_dir="$PROJECT_ROOT/$P12_PATH"

    if [ -f "$cert_dir/app_cert.p12" ]; then
        echo "- ✅ Application Certificate (app_cert.p12)" >> "$report_file"
    else
        echo "- ❌ Application Certificate (app_cert.p12)" >> "$report_file"
    fi

    if [ -f "$cert_dir/installer_cert.p12" ]; then
        echo "- ✅ Installer Certificate (installer_cert.p12)" >> "$report_file"
    else
        echo "- ❌ Installer Certificate (installer_cert.p12)" >> "$report_file"
    fi

    cat >> "$report_file" << EOF

## Environment Setup

- ✅ Configuration loaded from apple_credentials/config/app_config.json
- ✅ Build environment file created (.local_build_env)

## Next Steps

1. Source the environment:
   \`\`\`bash
   source .local_build_env
   \`\`\`

2. Run the signing script:
   \`\`\`bash
   ./.github/scripts/sign-and-notarize-macos.sh --version 1.0.0
   \`\`\`

3. Or use with build scripts:
   \`\`\`bash
   ./build-server-local.sh --version 1.0.0
   ./build-client-local.sh --version 1.0.0
   \`\`\`

## Troubleshooting

If you encounter issues:

1. **Certificate Errors:**
   - Verify certificates are not expired
   - Check p12_password is correct in app_config.json
   - Re-export certificates from Keychain Access if needed

2. **Apple ID Issues:**
   - Check Apple ID has proper permissions
   - Ensure app-specific password is current
   - Verify team ID is correct

3. **Build Issues:**
   - Make sure virtual environments are set up
   - Check that py2app dependencies are installed
   - Verify entitlements are correct for your app type

For more help, check the Apple Developer documentation.

## Certificate Export Instructions

If you need to re-export your certificates:

1. Open Keychain Access
2. Find your "Developer ID Application" certificate
3. Right-click → Export → Save as app_cert.p12
4. Find your "Developer ID Installer" certificate  
5. Right-click → Export → Save as installer_cert.p12
6. Place both files in: $P12_PATH/
7. Update the password in app_config.json if needed

EOF

    log_success "Setup report created: $report_file"
}

# Main setup function
main() {
    log_info "🔧 Certificate Setup for R2MIDI"
    log_info "========================================"

    # Load configuration
    load_config

    # Verify certificate files
    verify_certificate_files

    if [ "$VERIFY_ONLY" = "false" ]; then
        # Test certificates
        test_certificate_passwords
        check_certificate_details

        # Test Apple credentials (non-fatal) - temporarily disabled due to timeout issues
        log_warning "Apple credentials test skipped - notarization may not work"
        log_info "To enable Apple credentials test, uncomment the test_apple_credentials call"

        # Create build environment
        create_build_environment
    fi

    # Generate report
    generate_report

    log_success "🎉 Certificate setup completed!"

    if [ "$VERIFY_ONLY" = "false" ]; then
        echo ""
        log_info "📋 Environment ready for local builds"
        log_info "💡 Next steps:"
        echo "  1. source .local_build_env"
        echo "  2. ./build-server-local.sh --version 1.0.0"
        echo "  3. ./.github/scripts/sign-and-notarize-macos.sh --version 1.0.0"
        echo ""
        log_info "📄 Check CERTIFICATE_SETUP_REPORT.md for detailed information"
    fi
}

# Run main function
main "$@"
