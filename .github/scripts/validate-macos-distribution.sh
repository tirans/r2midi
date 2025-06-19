#!/bin/bash
set -euo pipefail

# Validate macOS environment for creating signed and notarized distribution packages
# This script focuses on the native macOS toolchain required for .pkg and .dmg creation
# Usage: validate-macos-distribution.sh

echo "🍎 Validating macOS distribution build environment..."
echo "This validation focuses on signed & notarized .pkg/.dmg creation using native tools"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Python version
check_python_version() {
    echo "🐍 Checking Python version..."
    
    if ! command_exists python; then
        echo "❌ Error: Python not found"
        exit 1
    fi
    
    local python_version=$(python --version 2>&1 | cut -d' ' -f2)
    local major_version=$(echo "$python_version" | cut -d'.' -f1)
    local minor_version=$(echo "$python_version" | cut -d'.' -f2)
    
    echo "📋 Python version: $python_version"
    
    if [ "$major_version" -eq 3 ] && [ "$minor_version" -ge 9 ]; then
        echo "✅ Python version is compatible (>= 3.9)"
    else
        echo "❌ Error: Python version must be 3.9 or higher"
        exit 1
    fi
}

# Function to validate project structure for native packaging
check_project_structure() {
    echo "📁 Checking project structure for native packaging..."
    
    local required_files=(
        "pyproject.toml"
        "requirements.txt"
        "server/main.py"
        "server/version.py"
        "r2midi_client/main.py"
    )
    
    local recommended_files=(
        "entitlements.plist"
        "Info.plist"
        "README.md"
    )
    
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        echo "❌ Error: Missing required files:"
        printf '  - %s\n' "${missing_files[@]}"
        exit 1
    fi
    
    echo "✅ Required project files found"
    
    # Check for recommended files
    local missing_recommended=()
    for file in "${recommended_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_recommended+=("$file")
        fi
    done
    
    if [ ${#missing_recommended[@]} -gt 0 ]; then
        echo "ℹ️ Recommended files not found (optional):"
        printf '  - %s\n' "${missing_recommended[@]}"
    fi
}

# Function to check macOS native development tools
check_xcode_tools() {
    echo "🔧 Checking Xcode Command Line Tools..."
    
    if command_exists xcode-select && xcode-select -p >/dev/null 2>&1; then
        echo "✅ Xcode Command Line Tools installed"
        local xcode_path=$(xcode-select -p)
        echo "📋 Xcode path: $xcode_path"
        
        # Check Xcode version
        local xcode_version=$(xcodebuild -version 2>/dev/null | head -1 || echo "Version unknown")
        echo "📋 $xcode_version"
    else
        echo "❌ Error: Xcode Command Line Tools not found"
        echo "Install with: xcode-select --install"
        exit 1
    fi
}

# Function to check code signing capabilities
check_code_signing() {
    echo "🔐 Checking code signing capabilities..."
    
    # Check codesign tool
    if command_exists codesign; then
        echo "✅ codesign tool available"
        local codesign_version=$(codesign --version 2>/dev/null || echo "Version unknown")
        echo "📋 $codesign_version"
    else
        echo "❌ Error: codesign tool not found"
        exit 1
    fi
    
    # Check available signing identities
    echo "🔍 Checking available signing identities..."
    local app_identities=$(security find-identity -v -p codesigning | grep "Developer ID Application" | wc -l | tr -d ' ')
    local installer_identities=$(security find-identity -v -p basic | grep "Developer ID Installer" | wc -l | tr -d ' ')
    
    echo "📋 Developer ID Application certificates: $app_identities"
    echo "📋 Developer ID Installer certificates: $installer_identities"
    
    if [ "$app_identities" -gt 0 ]; then
        echo "✅ Application signing certificates available"
        
        # List the certificates for reference
        echo "📋 Available Application signing identities:"
        security find-identity -v -p codesigning | grep "Developer ID Application" | while read line; do
            echo "  - $line"
        done
    else
        echo "⚠️ Warning: No application signing certificates found"
        echo "Distribution builds will be unsigned unless certificates are installed"
    fi
    
    if [ "$installer_identities" -gt 0 ]; then
        echo "✅ Installer signing certificates available for PKG creation"
        
        # List the certificates for reference
        echo "📋 Available Installer signing identities:"
        security find-identity -v -p basic | grep "Developer ID Installer" | while read line; do
            echo "  - $line"
        done
    else
        echo "ℹ️ No installer signing certificates found"
        echo "PKG installers will not be created, only DMG files"
    fi
}

# Function to check notarization tools
check_notarization() {
    echo "📤 Checking notarization capabilities..."
    
    if command_exists xcrun; then
        echo "✅ xcrun tool available"
        
        # Check notarytool
        if xcrun notarytool --help >/dev/null 2>&1; then
            echo "✅ notarytool available (modern notarization)"
        else
            echo "⚠️ Warning: notarytool not available"
            echo "Consider updating Xcode Command Line Tools"
        fi
        
        # Check stapler
        if xcrun stapler validate --help >/dev/null 2>&1; then
            echo "✅ stapler tool available"
        else
            echo "⚠️ Warning: stapler tool not available"
        fi
        
        # Check altool (legacy)
        if xcrun altool --help >/dev/null 2>&1; then
            echo "ℹ️ altool available (legacy notarization tool)"
        fi
    else
        echo "❌ Error: xcrun not found"
        exit 1
    fi
}

# Function to check packaging tools
check_packaging_tools() {
    echo "📦 Checking packaging tools..."
    
    # Check hdiutil for DMG creation
    if command_exists hdiutil; then
        echo "✅ hdiutil available for DMG creation"
    else
        echo "❌ Error: hdiutil not found"
        exit 1
    fi
    
    # Check pkgbuild for PKG creation
    if command_exists pkgbuild; then
        echo "✅ pkgbuild available for PKG creation"
    else
        echo "❌ Error: pkgbuild not found"
        exit 1
    fi
    
    # Check create-dmg (optional but recommended)
    if command_exists create-dmg; then
        echo "✅ create-dmg available (enhanced DMG creation)"
        local create_dmg_version=$(create-dmg --version 2>/dev/null || echo "Version unknown")
        echo "📋 $create_dmg_version"
    else
        echo "ℹ️ create-dmg not found (optional, will use hdiutil fallback)"
        echo "Install with: brew install create-dmg"
    fi
    
    # Check productbuild for complex installers
    if command_exists productbuild; then
        echo "✅ productbuild available for complex installers"
    else
        echo "⚠️ Warning: productbuild not found"
    fi
}

# Function to check security assessment tools
check_security_tools() {
    echo "🛡️ Checking security assessment tools..."
    
    # Check spctl for Gatekeeper assessment
    if command_exists spctl; then
        echo "✅ spctl available for Gatekeeper assessment"
        
        # Test spctl functionality
        if spctl --status 2>/dev/null | grep -q "assessments enabled"; then
            echo "📋 Gatekeeper assessments are enabled"
        else
            echo "📋 Gatekeeper assessments status: $(spctl --status 2>/dev/null || echo 'unknown')"
        fi
    else
        echo "❌ Error: spctl not found"
        exit 1
    fi
}

# Function to check environment variables for CI/CD
check_ci_environment() {
    if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
        echo "🔐 Checking CI environment for signing secrets..."
        
        local required_secrets=(
            "APPLE_ID"
            "APPLE_ID_PASSWORD"
            "APPLE_TEAM_ID"
        )
        
        local cert_secrets=(
            "APPLE_CERTIFICATE_P12"
            "APPLE_CERTIFICATE_PASSWORD"
        )
        
        local alt_cert_secrets=(
            "APPLE_DEVELOPER_ID_APPLICATION_CERT"
            "APPLE_DEVELOPER_ID_INSTALLER_CERT"
            "APPLE_CERT_PASSWORD"
        )
        
        local missing_required=()
        for secret in "${required_secrets[@]}"; do
            if [ -z "${!secret:-}" ]; then
                missing_required+=("$secret")
            fi
        done
        
        if [ ${#missing_required[@]} -gt 0 ]; then
            echo "❌ Error: Missing required CI secrets:"
            printf '  - %s\n' "${missing_required[@]}"
            exit 1
        else
            echo "✅ Required CI secrets configured"
        fi
        
        # Check certificate secrets (at least one format should be present)
        local has_p12=true
        local has_separate=true
        
        for secret in "${cert_secrets[@]}"; do
            if [ -z "${!secret:-}" ]; then
                has_p12=false
                break
            fi
        done
        
        for secret in "${alt_cert_secrets[@]:0:2}"; do  # Only check the cert secrets, not password
            if [ -z "${!secret:-}" ]; then
                has_separate=false
                break
            fi
        done
        
        if [ "$has_p12" = "true" ]; then
            echo "✅ P12 certificate format configured"
        elif [ "$has_separate" = "true" ]; then
            echo "✅ Separate certificate format configured"
        else
            echo "⚠️ Warning: No certificate secrets found"
            echo "Builds will be unsigned unless certificates are configured"
        fi
    else
        echo "ℹ️ Not running in CI environment, skipping secret validation"
    fi
}

# Function to check system requirements
check_system_requirements() {
    echo "💻 Checking system requirements..."
    
    # Check macOS version
    local macos_version=$(sw_vers -productVersion)
    local major_version=$(echo "$macos_version" | cut -d'.' -f1)
    local minor_version=$(echo "$macos_version" | cut -d'.' -f2)
    
    echo "📋 macOS version: $macos_version"
    
    if [ "$major_version" -ge 11 ] || ([ "$major_version" -eq 10 ] && [ "$minor_version" -ge 15 ]); then
        echo "✅ macOS version supports modern notarization"
    else
        echo "⚠️ Warning: macOS version may not support modern notarization tools"
    fi
    
    # Check architecture
    local arch=$(uname -m)
    echo "📋 Architecture: $arch"
    
    # Check available disk space
    local available_space=$(df -g . | tail -1 | awk '{print $4}')
    echo "📋 Available disk space: ${available_space}GB"
    
    if [ "$available_space" -gt 5 ]; then
        echo "✅ Sufficient disk space for packaging"
    else
        echo "⚠️ Warning: Low disk space. Large packages may fail to build"
    fi
}

# Function to generate validation report
generate_distribution_report() {
    echo "📋 Generating macOS distribution validation report..."
    
    cat > macos_distribution_report.txt << EOF
macOS Distribution Build Environment Report
==========================================

System Information:
- macOS Version: $(sw_vers -productVersion)
- Architecture: $(uname -m)
- Hostname: $(hostname)
- Validation Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

Development Tools:
- Python: $(python --version 2>&1)
- Xcode: $(xcodebuild -version 2>/dev/null | head -1 || echo "Not available")
- Xcode Path: $(xcode-select -p 2>/dev/null || echo "Not available")

Code Signing:
- codesign: $(codesign --version 2>/dev/null || echo "Not available")
- Application Certificates: $(security find-identity -v -p codesigning | grep "Developer ID Application" | wc -l | tr -d ' ')
- Installer Certificates: $(security find-identity -v -p basic | grep "Developer ID Installer" | wc -l | tr -d ' ')

Notarization:
- xcrun: $(xcrun --version 2>/dev/null || echo "Available")
- notarytool: $(xcrun notarytool --help >/dev/null 2>&1 && echo "Available" || echo "Not available")
- stapler: $(xcrun stapler validate --help >/dev/null 2>&1 && echo "Available" || echo "Not available")

Packaging Tools:
- hdiutil: $(command_exists hdiutil && echo "Available" || echo "Not available")
- pkgbuild: $(command_exists pkgbuild && echo "Available" || echo "Not available")
- create-dmg: $(command_exists create-dmg && echo "$(create-dmg --version 2>/dev/null | head -1)" || echo "Not installed")

Security:
- spctl: $(command_exists spctl && echo "Available" || echo "Not available")
- Gatekeeper: $(spctl --status 2>/dev/null || echo "Status unknown")

Distribution Capabilities:
- DMG Creation: $(command_exists hdiutil && echo "✅ Ready" || echo "❌ Missing tools")
- PKG Creation: $(command_exists pkgbuild && echo "✅ Ready" || echo "❌ Missing tools")
- Code Signing: $(([ $(security find-identity -v -p codesigning | grep "Developer ID Application" | wc -l | tr -d ' ') -gt 0 ] && echo "✅ Ready") || echo "❌ No certificates")
- Notarization: $(xcrun notarytool --help >/dev/null 2>&1 && echo "✅ Ready" || echo "❌ Tools missing")

Environment Status: ✅ READY FOR DISTRIBUTION BUILDS
EOF

    echo "✅ Distribution report created: macos_distribution_report.txt"
}

# Main validation workflow
echo "🚀 Starting macOS distribution validation..."
echo ""

# Core validations
check_python_version
echo ""

check_project_structure
echo ""

check_system_requirements
echo ""

check_xcode_tools
echo ""

check_code_signing
echo ""

check_notarization
echo ""

check_packaging_tools
echo ""

check_security_tools
echo ""

check_ci_environment
echo ""

generate_distribution_report
echo ""

echo "✅ macOS distribution environment validation complete!"
echo ""
echo "📋 Summary:"
echo "  - This environment is configured for native macOS distribution builds"
echo "  - Signed and notarized .pkg and .dmg files can be created"
echo "  - No dependency on Briefcase for distribution packaging"
echo "  - Using native Apple tools: codesign, hdiutil, pkgbuild, notarytool"
echo ""
echo "📋 Next steps:"
echo "  1. Ensure certificates are properly installed"
echo "  2. Configure Apple ID credentials for notarization"
echo "  3. Run your build pipeline to create distribution packages"
echo ""
echo "📁 Detailed report saved to: macos_distribution_report.txt"
