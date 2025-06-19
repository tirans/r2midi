#!/bin/bash
set -euo pipefail

# Validate build environment for different platforms
# Usage: validate-build-environment.sh <platform>

PLATFORM="${1:-unknown}"

echo "🔍 Validating build environment for $PLATFORM..."

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

# Function to check Briefcase
check_briefcase() {
    local platform="${1:-unknown}"
    
    echo "📦 Checking Briefcase..."
    
    if ! command_exists briefcase; then
        if [ "$platform" = "macos" ]; then
            echo "⚠️ Warning: Briefcase not found (optional for macOS distribution builds)"
            echo "For macOS, final distribution packages (.pkg/.dmg) are created using native tools"
            echo "If you need Briefcase for initial app building, install with: pip install briefcase"
            return 0
        else
            echo "❌ Error: Briefcase not found"
            echo "Install with: pip install briefcase"
            exit 1
        fi
    fi
    
    local briefcase_version=$(briefcase --version 2>/dev/null || echo "unknown")
    echo "📋 Briefcase version: $briefcase_version"
    echo "✅ Briefcase is available"
}

# Function to validate project structure
check_project_structure() {
    echo "📁 Checking project structure..."
    
    local required_files=(
        "pyproject.toml"
        "requirements.txt"
        "server/main.py"
        "server/version.py"
        "r2midi_client/main.py"
        "entitlements.plist"
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
    
    echo "✅ Project structure is valid"
}

# Function to check disk space
check_disk_space() {
    echo "💾 Checking disk space..."
    
    # Get available space in GB
    if command_exists df; then
        local available_space
        case "$(uname)" in
            Darwin*)  # macOS
                available_space=$(df -g . | tail -1 | awk '{print $4}')
                ;;
            Linux*)   # Linux
                available_space=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
                ;;
            CYGWIN*|MINGW*|MSYS*)  # Windows
                available_space=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
                ;;
            *)
                available_space="unknown"
                ;;
        esac
        
        if [ "$available_space" != "unknown" ] && [ "$available_space" -gt 2 ]; then
            echo "✅ Sufficient disk space available: ${available_space}GB"
        else
            echo "⚠️ Warning: Low disk space. Build may fail."
        fi
    else
        echo "⚠️ Warning: Cannot check disk space"
    fi
}

# Platform-specific validations
validate_linux() {
    echo "🐧 Validating Linux build environment..."
    
    # Check for required system packages
    local required_packages=("gcc" "pkg-config")
    local missing_packages=()
    
    for package in "${required_packages[@]}"; do
        if ! command_exists "$package"; then
            missing_packages+=("$package")
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo "❌ Error: Missing required system packages:"
        printf '  - %s\n' "${missing_packages[@]}"
        echo ""
        echo "Install with:"
        echo "  Ubuntu/Debian: sudo apt-get install build-essential pkg-config libasound2-dev portaudio19-dev"
        echo "  Fedora/RHEL: sudo dnf install gcc pkg-config alsa-lib-devel portaudio-devel"
        echo "  Arch: sudo pacman -S base-devel pkg-config alsa-lib portaudio"
        exit 1
    fi
    
    # Check for ALSA development libraries
    if [ -f "/usr/include/alsa/asoundlib.h" ] || [ -f "/usr/local/include/alsa/asoundlib.h" ]; then
        echo "✅ ALSA development libraries found"
    else
        echo "⚠️ Warning: ALSA development libraries may be missing"
        echo "Install with: sudo apt-get install libasound2-dev (Ubuntu/Debian)"
    fi
    
    echo "✅ Linux environment validation complete"
}

validate_windows() {
    echo "🪟 Validating Windows build environment..."
    
    # Check for Visual Studio Build Tools or similar
    if command_exists cl; then
        echo "✅ C++ compiler found"
    else
        echo "⚠️ Warning: C++ compiler not found in PATH"
        echo "Consider installing Visual Studio Build Tools"
    fi
    
    # Check Python development headers
    python -c "import sysconfig; print(sysconfig.get_path('include'))" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "✅ Python development headers accessible"
    else
        echo "⚠️ Warning: Python development headers may be missing"
    fi
    
    echo "✅ Windows environment validation complete"
}

validate_macos() {
    echo "🍎 Validating macOS build environment..."
    
    # Check Xcode Command Line Tools
    if command_exists xcode-select && xcode-select -p >/dev/null 2>&1; then
        echo "✅ Xcode Command Line Tools installed"
        local xcode_path=$(xcode-select -p)
        echo "📋 Xcode path: $xcode_path"
    else
        echo "❌ Error: Xcode Command Line Tools not found"
        echo "Install with: xcode-select --install"
        exit 1
    fi
    
    # Check for code signing tools
    if command_exists codesign; then
        echo "✅ Code signing tools available"
    else
        echo "❌ Error: Code signing tools not found"
        exit 1
    fi
    
    # Check for notarization tools
    if command_exists xcrun && xcrun notarytool --help >/dev/null 2>&1; then
        echo "✅ Notarization tools available"
    else
        echo "⚠️ Warning: Notarization tools may be outdated"
        echo "Consider updating Xcode Command Line Tools"
    fi
    
    # Check for create-dmg (optional)
    if command_exists create-dmg; then
        echo "✅ create-dmg tool available"
    else
        echo "ℹ️ create-dmg not found (optional, will use hdiutil fallback)"
        echo "Install with: brew install create-dmg"
    fi
    
    # Check available signing identities
    echo "🔍 Checking available signing identities..."
    local app_identities=$(security find-identity -v -p codesigning | grep "Developer ID Application" | wc -l)
    local installer_identities=$(security find-identity -v -p basic | grep "Developer ID Installer" | wc -l)
    
    echo "📋 Developer ID Application certificates: $app_identities"
    echo "📋 Developer ID Installer certificates: $installer_identities"
    
    if [ "$app_identities" -gt 0 ]; then
        echo "✅ Code signing certificates available"
    else
        echo "⚠️ Warning: No code signing certificates found"
        echo "Builds will be unsigned unless certificates are installed"
    fi
    
    echo "✅ macOS environment validation complete"
}

# Main validation workflow
echo "🚀 Starting build environment validation..."

# Common validations for all platforms
check_python_version
check_briefcase "$PLATFORM"
check_project_structure
check_disk_space

# Platform-specific validations
case "$PLATFORM" in
    linux)
        validate_linux
        ;;
    windows)
        validate_windows
        ;;
    macos)
        validate_macos
        ;;
    *)
        echo "⚠️ Warning: Unknown platform '$PLATFORM'"
        echo "Skipping platform-specific validations"
        ;;
esac

# Check environment variables for secrets (in CI)
if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
    echo "🔐 Checking CI environment..."
    
    case "$PLATFORM" in
        macos)
            required_secrets=(
                "APPLE_DEVELOPER_ID_APPLICATION_CERT"
                "APPLE_DEVELOPER_ID_INSTALLER_CERT"
                "APPLE_CERT_PASSWORD"
                "APPLE_ID"
                "APPLE_ID_PASSWORD"
                "APPLE_TEAM_ID"
            )
            
            missing_secrets=()
            for secret in "${required_secrets[@]}"; do
                if [ -z "${!secret:-}" ]; then
                    missing_secrets+=("$secret")
                fi
            done
            
            if [ ${#missing_secrets[@]} -gt 0 ]; then
                echo "⚠️ Warning: Missing macOS signing secrets:"
                printf '  - %s\n' "${missing_secrets[@]}"
                echo "Builds will be unsigned"
            else
                echo "✅ macOS signing secrets configured"
            fi
            ;;
    esac
fi

# Generate validation report
cat > build_environment_report.txt << EOF
Build Environment Validation Report
===================================

Platform: $PLATFORM
Validation Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Hostname: $(hostname)
OS: $(uname -s)
Architecture: $(uname -m)

Python:
$(python --version)

Tools:
- Briefcase: $(briefcase --version 2>/dev/null || echo "Not available")
- Git: $(git --version 2>/dev/null || echo "Not available")

Environment Status: ✅ PASSED
EOF

if [ "$PLATFORM" = "macos" ]; then
    echo "" >> build_environment_report.txt
    echo "macOS Specific:" >> build_environment_report.txt
    echo "- Xcode: $(xcode-select -p 2>/dev/null || echo "Not available")" >> build_environment_report.txt
    echo "- Code Signing Identities: $(security find-identity -v -p codesigning | grep "Developer ID Application" | wc -l || echo "0")" >> build_environment_report.txt
fi

echo ""
echo "✅ Build environment validation complete!"
echo "📋 Validation report:"
cat build_environment_report.txt