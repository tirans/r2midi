#!/bin/bash
set -euo pipefail

# Local PKG Build Testing Script for R2MIDI
# This script allows you to test the PKG build process locally
# Usage: ./scripts/test_pkg_build_locally.sh [version] [build_type]

VERSION="${1:-0.1.181}"
BUILD_TYPE="${2:-dev}"

echo "🧪 R2MIDI Local PKG Build Test"
echo "================================"
echo "Version: $VERSION"
echo "Build Type: $BUILD_TYPE"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_step() {
    echo ""
    print_status $BLUE "🔹 $1"
}

print_success() {
    print_status $GREEN "✅ $1"
}

print_warning() {
    print_status $YELLOW "⚠️ $1"
}

print_error() {
    print_status $RED "❌ $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."
    
    local missing_deps=()
    
    # Check if we're on macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        print_error "This script must be run on macOS"
        exit 1
    fi
    
    # Check Python
    if ! command_exists python; then
        missing_deps+=("python")
    fi
    
    # Check briefcase
    if ! python -c "import briefcase" 2>/dev/null; then
        missing_deps+=("briefcase")
    fi
    
    # Check security command
    if ! command_exists security; then
        missing_deps+=("security")
    fi
    
    # Check codesign
    if ! command_exists codesign; then
        missing_deps+=("codesign")
    fi
    
    # Check productbuild
    if ! command_exists productbuild; then
        missing_deps+=("productbuild")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        echo ""
        echo "To install missing dependencies:"
        for dep in "${missing_deps[@]}"; do
            case $dep in
                "python")
                    echo "  - Install Python 3.12+ from https://python.org"
                    ;;
                "briefcase")
                    echo "  - Run: pip install briefcase"
                    ;;
                *)
                    echo "  - $dep should be available on macOS by default"
                    ;;
            esac
        done
        exit 1
    fi
    
    print_success "All prerequisites available"
}

# Function to check Apple Developer setup
check_apple_setup() {
    print_step "Checking Apple Developer setup..."
    
    # Check for certificates
    local app_certs=$(security find-identity -v -p codesigning | grep "Developer ID Application" | wc -l)
    local installer_certs=$(security find-identity -v | grep "Developer ID Installer" | wc -l)
    
    if [ "$app_certs" -gt 0 ]; then
        print_success "Found $app_certs Developer ID Application certificate(s)"
        security find-identity -v -p codesigning | grep "Developer ID Application" | head -1
    else
        print_warning "No Developer ID Application certificates found"
        echo "  This will use ad-hoc signing (development only)"
    fi
    
    if [ "$installer_certs" -gt 0 ]; then
        print_success "Found $installer_certs Developer ID Installer certificate(s)"
        security find-identity -v | grep "Developer ID Installer" | head -1
    else
        print_warning "No Developer ID Installer certificates found"
        echo "  PKG creation will be limited or may fail"
        echo "  Consider using DMG distribution instead"
    fi
    
    # Check for Apple credentials (optional for local testing)
    if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_ID_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
        print_success "Apple credentials configured for notarization"
    else
        print_warning "Apple credentials not configured"
        echo "  Set APPLE_ID, APPLE_ID_PASSWORD, and APPLE_TEAM_ID environment variables"
        echo "  for notarization testing (optional for local builds)"
    fi
}

# Function to setup local certificates (if available)
setup_certificates() {
    print_step "Setting up certificates..."
    
    # Check if local certificate files exist
    if [ -f "apple_credentials/certificates/app_cert.p12" ] && [ -f "apple_credentials/config/app_config.json" ]; then
        print_success "Found local certificate files"
        
        # Run the certificate setup script
        if [ -f ".github/scripts/setup-certificates.sh" ]; then
            print_status $BLUE "Running certificate setup..."
            ./.github/scripts/setup-certificates.sh
        else
            print_warning "Certificate setup script not found, using system certificates"
        fi
    else
        print_warning "No local certificate files found"
        echo "  Using system keychain certificates"
    fi
}

# Function to configure signing
configure_signing() {
    print_step "Configuring signing and entitlements..."
    
    # Make scripts executable
    chmod +x scripts/select_entitlements.py 2>/dev/null || true
    chmod +x scripts/configure_briefcase_signing.py 2>/dev/null || true
    
    # Configure briefcase signing identity
    if [ -f "scripts/configure_briefcase_signing.py" ]; then
        print_status $BLUE "Setting up briefcase signing identity..."
        python scripts/configure_briefcase_signing.py
    else
        print_warning "Briefcase signing configuration script not found"
    fi
    
    # Select appropriate entitlements
    if [ -f "scripts/select_entitlements.py" ]; then
        print_status $BLUE "Selecting appropriate entitlements..."
        python scripts/select_entitlements.py
    else
        print_warning "Entitlements selection script not found"
    fi
}

# Function to build applications
build_applications() {
    print_step "Building applications..."
    
    # Export Python path for briefcase
    export PYTHONPATH="${PWD}:${PYTHONPATH:-}"
    
    # Build server app
    print_status $BLUE "Building server app..."
    if briefcase build macos app -a server; then
        print_success "Server app built successfully"
    else
        print_error "Server app build failed"
        return 1
    fi
    
    # Build client app
    print_status $BLUE "Building client app..."
    if briefcase build macos app -a r2midi-client; then
        print_success "Client app built successfully"
    else
        print_error "Client app build failed"
        return 1
    fi
    
    print_success "Both applications built successfully"
}

# Function to create PKG installers
create_pkg_installers() {
    print_step "Creating PKG installers..."
    
    # Check if we have the required credentials for full PKG creation
    if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_ID_PASSWORD:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ]; then
        print_warning "Apple credentials not set, creating unsigned PKG for testing"
        
        # Create a simple test PKG without notarization
        create_test_pkg
    else
        # Use the full PKG creation script
        if [ -f ".github/scripts/create-macos-pkg.sh" ]; then
            print_status $BLUE "Running full PKG creation script..."
            ./.github/scripts/create-macos-pkg.sh "$VERSION" "$BUILD_TYPE" "$APPLE_ID" "$APPLE_ID_PASSWORD" "$APPLE_TEAM_ID"
        else
            print_error "PKG creation script not found"
            return 1
        fi
    fi
}

# Function to create a test PKG without notarization
create_test_pkg() {
    print_status $BLUE "Creating test PKG installers..."
    
    # Create artifacts directory
    mkdir -p artifacts
    
    # Check if apps were built
    local server_app="build/server/macos/app/R2MIDI Server.app"
    local client_app="build/r2midi-client/macos/app/R2MIDI Client.app"
    
    if [ ! -d "$server_app" ]; then
        print_error "Server app not found: $server_app"
        return 1
    fi
    
    if [ ! -d "$client_app" ]; then
        print_error "Client app not found: $client_app"
        return 1
    fi
    
    # Create simple PKG for server
    print_status $BLUE "Creating server PKG..."
    if productbuild --component "$server_app" /Applications "artifacts/R2MIDI-Server-${VERSION}-${BUILD_TYPE}.pkg"; then
        print_success "Server PKG created"
    else
        print_error "Failed to create server PKG"
    fi
    
    # Create simple PKG for client
    print_status $BLUE "Creating client PKG..."
    if productbuild --component "$client_app" /Applications "artifacts/R2MIDI-Client-${VERSION}-${BUILD_TYPE}.pkg"; then
        print_success "Client PKG created"
    else
        print_error "Failed to create client PKG"
    fi
}

# Function to validate results
validate_results() {
    print_step "Validating results..."
    
    # Check for PKG files
    local pkg_count=$(find artifacts/ -name "*.pkg" 2>/dev/null | wc -l)
    
    if [ "$pkg_count" -gt 0 ]; then
        print_success "$pkg_count PKG installer(s) created"
        echo ""
        echo "Created PKG files:"
        find artifacts/ -name "*.pkg" | while read pkg; do
            local size=$(du -h "$pkg" | cut -f1)
            echo "  📦 $(basename "$pkg") ($size)"
            
            # Quick signature check
            if pkgutil --check-signature "$pkg" 2>/dev/null | grep -q "signed"; then
                echo "     ✅ Signed"
            else
                echo "     ⚠️ Unsigned (test build)"
            fi
        done
    else
        print_error "No PKG files found"
        return 1
    fi
    
    # Check app bundles
    echo ""
    echo "Built applications:"
    if [ -d "build/server/macos/app/R2MIDI Server.app" ]; then
        echo "  🖥️ R2MIDI Server.app"
    fi
    if [ -d "build/r2midi-client/macos/app/R2MIDI Client.app" ]; then
        echo "  🖥️ R2MIDI Client.app"
    fi
}

# Function to show usage instructions
show_usage() {
    echo "Usage: $0 [version] [build_type]"
    echo ""
    echo "Arguments:"
    echo "  version     Application version (default: 0.1.181)"
    echo "  build_type  Build type: dev, staging, production (default: dev)"
    echo ""
    echo "Environment variables (optional):"
    echo "  APPLE_ID              Apple ID for notarization"
    echo "  APPLE_ID_PASSWORD     App-specific password for Apple ID"
    echo "  APPLE_TEAM_ID         Apple Developer Team ID"
    echo ""
    echo "Examples:"
    echo "  $0                           # Use defaults"
    echo "  $0 1.0.0 production         # Specific version and build type"
    echo "  APPLE_ID=dev@example.com $0  # With Apple credentials"
}

# Main execution
main() {
    # Check for help flag
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    # Run the build process
    check_prerequisites
    check_apple_setup
    setup_certificates
    configure_signing
    
    if build_applications; then
        if create_pkg_installers; then
            validate_results
            echo ""
            print_success "Local PKG build test completed successfully!"
            echo ""
            echo "Next steps:"
            echo "  1. Test the PKG installers in artifacts/"
            echo "  2. Install and verify the applications work"
            echo "  3. For production builds, ensure proper Apple certificates and credentials"
        else
            print_error "PKG creation failed"
            exit 1
        fi
    else
        print_error "Application build failed"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"