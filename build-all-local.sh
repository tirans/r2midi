#!/bin/bash
set -euo pipefail
# build-all-local.sh - R2MIDI build system with proper signing
# Usage: ./build-all-local.sh [options]

# Source common certificate setup
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SOURCE_DIR/scripts/common-certificate-setup.sh" ]; then
    source "$SOURCE_DIR/scripts/common-certificate-setup.sh"
fi

echo "🚀 R2MIDI Build System"
echo "==============================="

# Default values
VERSION=""
BUILD_TYPE="production"
SKIP_SIGNING=false
SKIP_NOTARIZATION=false
CLEAN_BUILD=false

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
        --staging)
            BUILD_TYPE="staging"
            shift
            ;;
        --no-sign)
            SKIP_SIGNING=true
            shift
            ;;
        --no-notarize)
            SKIP_NOTARIZATION=true
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --help)
            cat << EOF
R2MIDI Build System

Usage: $0 [options]

Options:
  --version VERSION    Specify version (auto-detected if not provided)
  --dev               Development build (faster, less verification)
  --staging           Staging build (production-like with full verification)
  --no-sign           Skip code signing
  --no-notarize       Skip notarization
  --clean             Clean previous builds first
  --help              Show this help

Examples:
  $0                                  # Build everything with auto-detected version
  $0 --version 1.2.3                # Build with specific version
  $0 --dev --no-notarize            # Fast development build
  $0 --staging --version 1.2.3      # Staging build with full verification
  $0 --clean                        # Clean build

Supports both local development and GitHub Actions environments.
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Enhanced logging functions with timestamps and file support
LOG_FILE=""
LOG_LEVEL=${LOG_LEVEL:-1}  # 0=debug, 1=info, 2=warning, 3=error

# Function to get timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Core logging function
write_log() {
    local level="$1"
    local icon="$2"
    local message="$3"
    local timestamp=$(get_timestamp)
    local formatted_message="[$timestamp] $icon $message"

    # Output to console
    echo "$formatted_message"

    # Output to log file if specified
    if [ -n "$LOG_FILE" ]; then
        echo "$formatted_message" >> "$LOG_FILE"
    fi
}

# Enhanced logging functions
log_debug() { [ "$LOG_LEVEL" -le 0 ] && write_log "DEBUG" "🔍" "$1"; }
log_info() { [ "$LOG_LEVEL" -le 1 ] && write_log "INFO" "ℹ️ " "$1"; }
log_success() { [ "$LOG_LEVEL" -le 1 ] && write_log "SUCCESS" "✅" "$1"; }
log_warning() { [ "$LOG_LEVEL" -le 2 ] && write_log "WARNING" "⚠️ " "$1"; }
log_error() { [ "$LOG_LEVEL" -le 3 ] && write_log "ERROR" "❌" "$1"; }
log_step() { 
    echo ""
    write_log "STEP" "🔄" "$1"
    echo "$(printf '=%.0s' {1..60})"
}

# Performance logging
log_performance() {
    local operation="$1"
    local duration="$2"
    write_log "PERFORMANCE" "⏱️ " "$operation completed in ${duration}s"
}

# Command logging
log_command() {
    local command="$1"
    log_debug "Executing: $command"
}

# Progress logging
log_progress() {
    local current="$1"
    local total="$2"
    local message="$3"
    local percentage=$((current * 100 / total))
    write_log "PROGRESS" "📊" "[$current/$total] ($percentage%) $message"
}

# Function to start timing
start_timer() {
    echo $(date +%s)
}

# Function to end timing and log performance
end_timer() {
    local start_time="$1"
    local operation="$2"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_performance "$operation" "$duration"
    echo "$duration"
}

# Setup logging
setup_logging() {
    local log_dir="logs"
    mkdir -p "$log_dir"

    local timestamp=$(date '+%Y%m%d_%H%M%S')
    LOG_FILE="$log_dir/build_all_${timestamp}.log"

    log_info "Build log file: $LOG_FILE"

    # Write header to log file
    {
        echo "========================================"
        echo "R2MIDI Build System Log"
        echo "Started at: $(get_timestamp)"
        echo "Script: $0"
        echo "Arguments: $*"
        echo "PID: $$"
        echo "User: $(whoami)"
        echo "Working Directory: $(pwd)"
        echo "========================================"
    } >> "$LOG_FILE"
}

# Setup enhanced logging first
setup_logging

# Log system information
log_step "System Information"
log_info "Operating System: $(uname -s) $(uname -r)"
log_info "Architecture: $(uname -m)"
log_info "Hostname: $(hostname)"
log_info "User: $(whoami)"
log_info "Working Directory: $(pwd)"
log_info "Shell: $SHELL"

# Check if we're running in GitHub Actions
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    log_info "Running in GitHub Actions environment"
    IS_GITHUB_ACTIONS=true
    log_info "Repository: ${GITHUB_REPOSITORY:-unknown}"
    log_info "Workflow: ${GITHUB_WORKFLOW:-unknown}"
    log_info "Run ID: ${GITHUB_RUN_ID:-unknown}"
else
    log_info "Running in local development environment"
    IS_GITHUB_ACTIONS=false
fi

# Check macOS version and tools
check_environment() {
    local start_time=$(start_timer)
    log_step "Checking Environment"

    log_info "Validating operating system..."
    if [ "$(uname)" != "Darwin" ]; then
        log_error "This script requires macOS"
        exit 1
    fi

    local macos_version=$(sw_vers -productVersion)
    local build_version=$(sw_vers -buildVersion 2>/dev/null || echo "unknown")
    log_info "Running on macOS $macos_version (Build: $build_version)"

    # Check Xcode version if available
    if command -v xcodebuild >/dev/null 2>&1; then
        local xcode_version=$(xcodebuild -version 2>/dev/null | head -1 || echo "unknown")
        log_info "Xcode: $xcode_version"
    else
        log_warning "Xcode not found - may affect code signing"
    fi

    # Check for required tools with detailed logging
    log_info "Checking required development tools..."
    local missing_tools=()
    local available_tools=()

    for tool in python3 security codesign productsign pkgbuild xcrun; do
        if command -v "$tool" >/dev/null 2>&1; then
            available_tools+=("$tool")
            local tool_path=$(command -v "$tool")
            case "$tool" in
                "python3")
                    local version=$(python3 --version 2>/dev/null | cut -d' ' -f2 || echo "unknown")
                    log_success "$tool is available at $tool_path (version: $version)"
                    ;;
                *)
                    log_success "$tool is available at $tool_path"
                    ;;
            esac
        else
            missing_tools+=("$tool")
            log_error "$tool is missing"
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools:"
        for tool in "${missing_tools[@]}"; do
            log_error "  - $tool"
        done
        log_error "Please install missing tools before continuing"
        exit 1
    fi

    log_info "Found ${#available_tools[@]} required tools"

    # Check if notarytool is available
    log_info "Checking notarization capabilities..."
    if command -v xcrun &> /dev/null && xcrun --find notarytool &> /dev/null; then
        local notarytool_path=$(xcrun --find notarytool)
        log_success "notarytool is available at $notarytool_path"
    else
        log_warning "notarytool not found - notarization may fail (requires Xcode 13+ or macOS 12+)"
    fi

    # Check virtual environments with detailed logging
    log_info "Checking Python virtual environments..."
    local venv_issues=()

    if [ ! -d "venv_client" ]; then
        venv_issues+=("venv_client")
        log_warning "Client virtual environment not found: venv_client"
    else
        local client_python="venv_client/bin/python"
        if [ -x "$client_python" ]; then
            local client_version=$("$client_python" --version 2>/dev/null || echo "unknown")
            log_success "Client virtual environment found: $client_version"
        else
            log_warning "Client virtual environment exists but Python not executable"
        fi
    fi

    if [ ! -d "venv_server" ]; then
        venv_issues+=("venv_server")
        log_warning "Server virtual environment not found: venv_server"
    else
        local server_python="venv_server/bin/python"
        if [ -x "$server_python" ]; then
            local server_version=$("$server_python" --version 2>/dev/null || echo "unknown")
            log_success "Server virtual environment found: $server_version"
        else
            log_warning "Server virtual environment exists but Python not executable"
        fi
    fi

    if [ ${#venv_issues[@]} -gt 0 ]; then
        log_info "Virtual environment issues found: ${venv_issues[*]}"
        log_info "Note: Individual build scripts will create virtual environments as needed"
        log_info "This is normal for fresh builds or after cleanup"
    fi

    # Check disk space
    log_info "Checking available disk space..."
    local available_space=$(df -g . 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")
    if [ "$available_space" != "unknown" ]; then
        log_info "Available disk space: ${available_space}GB"
        if [ "$available_space" -lt 5 ]; then
            log_warning "Low disk space: ${available_space}GB available (recommend 5GB+)"
        fi
    fi

    local duration=$(end_timer "$start_time" "Environment Check")
    log_success "Environment check passed"
}

# Setup certificates - GitHub Actions vs Local
setup_build_certificates() {
    local start_time=$(start_timer)
    log_step "Setting Up Certificates"

    log_info "Environment type: $([ "$IS_GITHUB_ACTIONS" = true ] && echo "GitHub Actions" || echo "Local Development")"

    if [ "$IS_GITHUB_ACTIONS" = true ]; then
        log_info "Using GitHub Actions certificate setup..."
        setup_github_certificates
    else
        log_info "Using common certificate setup..."
        # The common certificate setup script is already sourced at the top of this file
        # Call the common setup function with skip_signing parameter
        local skip_signing_param="$SKIP_SIGNING"
        if [ "$skip_signing_param" = "true" ]; then
            setup_certificates "true"
        else
            setup_certificates "false"
        fi
    fi

    local duration=$(end_timer "$start_time" "Certificate Setup")
}

# GitHub Actions certificate setup
setup_github_certificates() {
    local start_time=$(start_timer)
    log_info "Setting up certificates from GitHub Actions environment..."

    # Check required environment variables
    log_info "Validating required environment variables..."
    local required_vars=("APPLE_DEVELOPER_ID_APPLICATION_CERT" "APPLE_DEVELOPER_ID_INSTALLER_CERT" "APPLE_CERT_PASSWORD" "APPLE_TEAM_ID" "APPLE_ID" "APPLE_ID_PASSWORD")
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing_vars+=("$var")
            log_error "Missing environment variable: $var"
        else
            if [[ "$var" == *"PASSWORD"* ]] || [[ "$var" == *"CERT"* ]]; then
                log_success "$var is set [REDACTED]"
            else
                log_success "$var is set: ${!var}"
            fi
        fi
    done

    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Required certificate environment variables not found:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        exit 1
    fi

    # Create temporary certificate directory
    log_info "Creating temporary certificate directory..."
    local cert_dir="/tmp/github_certs"
    mkdir -p "$cert_dir"
    log_success "Certificate directory created: $cert_dir"

    # Decode and save certificates
    log_info "Decoding and saving certificates..."
    local app_cert_file="$cert_dir/app_cert.p12"
    local installer_cert_file="$cert_dir/installer_cert.p12"

    if echo "$APPLE_DEVELOPER_ID_APPLICATION_CERT" | base64 --decode > "$app_cert_file"; then
        local app_cert_size=$(ls -lh "$app_cert_file" | awk '{print $5}')
        log_success "Application certificate decoded: $app_cert_file ($app_cert_size)"
    else
        log_error "Failed to decode application certificate"
        exit 1
    fi

    if echo "$APPLE_DEVELOPER_ID_INSTALLER_CERT" | base64 --decode > "$installer_cert_file"; then
        local installer_cert_size=$(ls -lh "$installer_cert_file" | awk '{print $5}')
        log_success "Installer certificate decoded: $installer_cert_file ($installer_cert_size)"
    else
        log_error "Failed to decode installer certificate"
        exit 1
    fi

    # Create temporary config for GitHub Actions
    cat > /tmp/github_app_config.json << EOF
{
  "apple_developer": {
    "team_id": "${APPLE_TEAM_ID}",
    "p12_path": "/tmp/github_certs",
    "p12_password": "${APPLE_CERT_PASSWORD}",
    "app_specific_password": "${APPLE_ID_PASSWORD}",
    "apple_id": "${APPLE_ID}"
  },
  "build_options": {
    "enable_notarization": true
  }
}
EOF

    # Create temporary keychain
    TEMP_KEYCHAIN="r2midi-github-$(date +%s).keychain"
    TEMP_KEYCHAIN_PASSWORD="github_$(date +%s)_$(openssl rand -hex 8)"

    # Clean up any existing keychains
    security delete-keychain "$TEMP_KEYCHAIN" 2>/dev/null || true

    # Create and configure keychain
    security create-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"
    security set-keychain-settings -lut 21600 "$TEMP_KEYCHAIN"
    security unlock-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"
    security list-keychains -d user -s "$TEMP_KEYCHAIN" $(security list-keychains -d user | xargs)

    # Import certificates
    security import "/tmp/github_certs/app_cert.p12" -k "$TEMP_KEYCHAIN" -P "${APPLE_CERT_PASSWORD}" -T /usr/bin/codesign -T /usr/bin/security
    security import "/tmp/github_certs/installer_cert.p12" -k "$TEMP_KEYCHAIN" -P "${APPLE_CERT_PASSWORD}" -T /usr/bin/productsign -T /usr/bin/security

    # Set partition list
    security set-key-partition-list -S apple-tool:,apple: -s -k "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"

    # Export keychain info for signing script
    export KEYCHAIN_NAME="$TEMP_KEYCHAIN"
    export KEYCHAIN_PASSWORD="$TEMP_KEYCHAIN_PASSWORD"

    log_success "GitHub Actions certificates setup complete"
}

# Local certificate setup
setup_local_certificates() {
    local start_time=$(start_timer)
    log_info "Setting up local certificates..."

    # Check if enhanced certificate setup exists
    log_info "Checking for certificate setup script..."
    if [ -f "setup-local-certificates.sh" ]; then
        log_success "Found certificate setup script: setup-local-certificates.sh"
        log_info "Running certificate setup script..."

        if ./setup-local-certificates.sh; then
            log_success "Certificate setup script completed successfully"
        else
            log_error "Certificate setup script failed"
            exit 1
        fi

        # Source environment if available
        log_info "Checking for build environment file..."
        if [ -f ".local_build_env" ]; then
            log_info "Sourcing build environment: .local_build_env"
            source .local_build_env
            log_success "Build environment loaded"

            # Log loaded environment variables
            if [ -n "${APPLE_ID:-}" ]; then
                log_info "Apple ID: $APPLE_ID"
            fi
            if [ -n "${APPLE_TEAM_ID:-}" ]; then
                log_info "Team ID: $APPLE_TEAM_ID"
            fi
        else
            log_warning "Build environment file not found: .local_build_env"
        fi
    else
        log_warning "Certificate setup script not found: setup-local-certificates.sh"
        log_info "Performing basic certificate check..."

        # Basic certificate check with detailed logging
        log_info "Searching for Developer ID Application certificates..."
        local app_certs=$(security find-identity -v -p codesigning | grep "Developer ID Application" || true)

        if [ -z "$app_certs" ]; then
            log_error "No Developer ID Application certificate found"
            log_error "Available certificates:"
            security find-identity -v -p codesigning | while read -r line; do
                log_info "  $line"
            done
            log_error "Install your Apple Developer certificates first"
            exit 1
        else
            log_success "Found Developer ID Application certificates:"
            echo "$app_certs" | while read -r line; do
                log_info "  $line"
            done
        fi

        # Check for installer certificates
        log_info "Searching for Developer ID Installer certificates..."
        local installer_certs=$(security find-identity -v -p codesigning | grep "Developer ID Installer" || true)

        if [ -n "$installer_certs" ]; then
            log_success "Found Developer ID Installer certificates:"
            echo "$installer_certs" | while read -r line; do
                log_info "  $line"
            done
        else
            log_warning "No Developer ID Installer certificates found"
        fi

        log_success "Basic certificate check completed"
    fi

    local duration=$(end_timer "$start_time" "Local Certificate Setup")
}

# Extract version
extract_version() {
    if [ -n "$VERSION" ]; then
        log_info "Using specified version: $VERSION"
        return
    fi

    log_info "Auto-detecting version..."

    # Try server version first
    if [ -f "server/version.py" ]; then
        VERSION=$(python3 -c "
import sys
sys.path.insert(0, 'server')
try:
    from version import __version__
    print(__version__)
except:
    pass
" 2>/dev/null || echo "")
    fi

    # Try client version if server failed
    if [ -z "$VERSION" ] && [ -f "r2midi_client/version.py" ]; then
        VERSION=$(python3 -c "
import sys
sys.path.insert(0, 'r2midi_client')
try:
    from version import __version__
    print(__version__)
except:
    pass
" 2>/dev/null || echo "")
    fi

    # Fallback version
    if [ -z "$VERSION" ]; then
        VERSION="0.1.$(date +%Y%m%d)"
        log_warning "Could not detect version, using: $VERSION"
    else
        log_success "Detected version: $VERSION"
    fi
}

# Clean previous builds
clean_builds() {
    log_step "Cleaning Build Environment"

    # Check if virtual environments already exist and we're in GitHub Actions
    local venv_client_exists=false
    local venv_server_exists=false

    if [ -d "venv_client" ] && [ -x "venv_client/bin/python" ]; then
        venv_client_exists=true
    fi

    if [ -d "venv_server" ] && [ -x "venv_server/bin/python" ]; then
        venv_server_exists=true
    fi

    # In GitHub Actions, if virtual environments already exist, preserve them
    if [ "$IS_GITHUB_ACTIONS" = true ] && [ "$venv_client_exists" = true ] && [ "$venv_server_exists" = true ]; then
        log_info "GitHub Actions: Virtual environments already exist, preserving them..."
        log_info "Cleaning only build artifacts while preserving virtual environments..."

        # Clean build artifacts but preserve virtual environments
        rm -rf build_client build_server 2>/dev/null || true
        rm -rf build dist artifacts 2>/dev/null || true
        rm -rf build_native 2>/dev/null || true

        # Clean Python cache
        find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
        find . -name "*.pyc" -delete 2>/dev/null || true
        find . -name "*.pyo" -delete 2>/dev/null || true

        # Clean py2app cache
        rm -rf ~/.py2app "$HOME/.py2app" 2>/dev/null || true

        # Clean setuptools/wheel cache and build artifacts
        find . -name "*.egg-info" -type d -exec rm -rf {} + 2>/dev/null || true
        find . -name "*.egg" -delete 2>/dev/null || true

        log_success "Build artifacts cleaned, virtual environments preserved"
    else
        # Standard cleanup for local development or when virtual environments don't exist
        log_info "Running comprehensive environment cleanup..."
        if [ -f "./clean-environment.sh" ]; then
            if [ "$CLEAN_BUILD" = true ]; then
                log_info "Deep cleaning environment (--clean flag enabled)..."
                ./clean-environment.sh --deep
            else
                log_info "Standard environment cleanup..."
                ./clean-environment.sh
            fi
            log_success "Environment cleanup completed"
        else
            log_warning "clean-environment.sh not found, falling back to basic cleanup"

            # Fallback to basic cleanup if clean-environment.sh is not available
            if [ "$CLEAN_BUILD" = true ]; then
                log_info "Removing build directories..."
                rm -rf build_server/build build_server/dist
                rm -rf build_client/build build_client/dist

                log_info "Removing artifacts..."
                rm -rf artifacts/*.pkg artifacts/*.dmg artifacts/*.app

                log_info "Cleaning Python cache..."
                find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
                find . -name "*.pyc" -delete 2>/dev/null || true

                log_success "Basic build environment cleaned"
            fi
        fi
    fi
}

# Build individual component
build_component() {
    local component="$1"  # "server" or "client"
    local script_name="build-${component}-local.sh"
    local start_time=$(start_timer)

    # Capitalize first letter of component name for display
    local component_display="$(echo "${component:0:1}" | tr '[:lower:]' '[:upper:]')${component:1}"

    log_step "Building R2MIDI ${component_display}"

    # Pre-build validation
    log_info "Validating build prerequisites for $component_display..."

    if [ ! -f "$script_name" ]; then
        log_error "Build script not found: $script_name"
        log_error "Expected location: $(pwd)/$script_name"
        return 1
    fi

    if [ ! -x "$script_name" ]; then
        log_warning "Build script is not executable: $script_name"
        log_info "Making script executable..."
        chmod +x "$script_name"
    fi

    log_success "Build script found: $script_name"

    # Note: Virtual environment validation removed - individual build scripts handle this
    log_info "Virtual environment will be created by build script if needed"

    # Build arguments
    local build_args="--version $VERSION"
    log_info "Base build arguments: $build_args"

    if [ "$BUILD_TYPE" = "dev" ]; then
        build_args="$build_args --dev"
        log_info "Added development build flag"
    fi

    if [ "$SKIP_SIGNING" = true ]; then
        build_args="$build_args --no-sign"
        log_info "Added skip signing flag"
    fi

    if [ "$SKIP_NOTARIZATION" = true ]; then
        build_args="$build_args --no-notarize"
        log_info "Added skip notarization flag"
    fi

    log_info "Final build command: ./$script_name $build_args"
    log_info "Starting $component_display build process..."

    # Execute build with detailed logging
    log_command "./$script_name $build_args"

    # Create a temporary log file for this build
    local temp_log="logs/${component}_build_$(date '+%Y%m%d_%H%M%S').log"
    mkdir -p logs

    if ./"$script_name" $build_args > "$temp_log" 2>&1; then
        local duration=$(end_timer "$start_time" "${component_display} Build")
        log_success "${component_display} build completed successfully"
        log_info "Detailed build output saved to: $temp_log"

        # Check for build artifacts
        log_info "Checking for build artifacts..."
        local build_dir="build_${component}"
        local artifacts_found=0

        if [ -d "$build_dir/dist" ]; then
            log_info "Checking dist directory: $build_dir/dist"
            find "$build_dir/dist" -name "*.app" -o -name "*.pkg" | while read -r artifact; do
                if [ -e "$artifact" ]; then
                    local artifact_size=$(du -sh "$artifact" 2>/dev/null | cut -f1 || echo "unknown")
                    log_success "Found artifact: $(basename "$artifact") ($artifact_size)"
                    artifacts_found=$((artifacts_found + 1))
                fi
            done
        fi

        if [ -d "artifacts" ]; then
            log_info "Checking artifacts directory..."
            find "artifacts" -name "*${component}*" -name "*.pkg" | while read -r artifact; do
                if [ -e "$artifact" ]; then
                    local artifact_size=$(du -sh "$artifact" 2>/dev/null | cut -f1 || echo "unknown")
                    log_success "Found package: $(basename "$artifact") ($artifact_size)"
                fi
            done
        fi

        return 0
    else
        local exit_code=$?
        local duration=$(end_timer "$start_time" "${component_display} Build (FAILED)")
        log_error "${component_display} build failed with exit code: $exit_code"
        log_error "Build duration before failure: ${duration}s"
        log_error "Detailed build output saved to: $temp_log"

        # Log potential issues
        log_info "Checking for common build issues..."
        if [ ! -f "$script_name" ]; then
            log_error "Build script missing: $script_name"
        fi

        return $exit_code
    fi
}

# Signing and notarization using the signing script
enhanced_signing() {
    if [ "$SKIP_SIGNING" = true ]; then
        log_info "Skipping signing and notarization (--no-sign specified)"
        return 0
    fi

    log_step "Signing and Notarization"

    # Check if signing script exists
    if [ ! -f ".github/scripts/sign-notarize.sh" ]; then
        log_warning "Signing script not found at .github/scripts/sign-notarize.sh"
        log_warning "Signing was handled by individual build scripts"
        return 0
    fi

    # Build arguments for signing script
    local sign_args="--version $VERSION"

    if [ "$BUILD_TYPE" = "dev" ]; then
        sign_args="$sign_args --dev"
    fi

    if [ "$SKIP_NOTARIZATION" = true ]; then
        sign_args="$sign_args --skip-notarize"
    fi

    log_info "Running signing and notarization: ./.github/scripts/sign-notarize.sh $sign_args"

    if ./.github/scripts/sign-notarize.sh $sign_args; then
        log_success "Signing and notarization completed"
        return 0
    else
        log_error "Signing failed"
        if [ "$BUILD_TYPE" != "dev" ]; then
            return 1
        else
            log_warning "Continuing despite signing failure (dev build)"
            return 0
        fi
    fi
}

# Generate comprehensive build report
generate_build_report() {
    log_step "Generating Build Report"

    local report_file="artifacts/BUILD_REPORT_$VERSION.md"
    mkdir -p artifacts

    cat > "$report_file" << EOF
# R2MIDI Complete Build Report

**Version:** $VERSION  
**Build Date:** $(date)  
**Build Type:** $BUILD_TYPE  
**Environment:** $([ "$IS_GITHUB_ACTIONS" = true ] && echo "GitHub Actions" || echo "Local Development")  
**Platform:** $(uname -s) $(uname -r)  
**Architecture:** $(uname -m)  

## Build Configuration

- **Signing:** $([ "$SKIP_SIGNING" = true ] && echo "Disabled" || echo "Enabled")
- **Notarization:** $([ "$SKIP_NOTARIZATION" = true ] && echo "Disabled" || echo "Enabled")
- **Clean Build:** $([ "$CLEAN_BUILD" = true ] && echo "Yes" || echo "No")
- **Python Version:** $(python3 --version)

## Generated Artifacts

EOF

    # List all generated artifacts
    if [ -d "artifacts" ]; then
        find artifacts -name "*.pkg" -o -name "*.dmg" -o -name "*.app" | sort | while read artifact; do
            if [ -f "$artifact" ]; then
                local size=$(du -sh "$artifact" 2>/dev/null | cut -f1 || echo "unknown")
                local signed="Unknown"
                local notarized="Unknown"

                # Check if it's a package
                if [[ "$artifact" == *.pkg ]]; then
                    if pkgutil --check-signature "$artifact" >/dev/null 2>&1; then
                        signed="Yes"
                    else
                        signed="No"
                    fi

                    if spctl --assess --type install "$artifact" >/dev/null 2>&1; then
                        notarized="Yes"
                    else
                        notarized="No"
                    fi

                    echo "- **$(basename "$artifact")** ($size)" >> "$report_file"
                    echo "  - Signed: $signed" >> "$report_file"
                    echo "  - Notarized: $notarized" >> "$report_file"
                else
                    echo "- **$(basename "$artifact")** ($size)" >> "$report_file"
                fi
            fi
        done
    fi

    cat >> "$report_file" << EOF

## Installation Instructions

### Using Package Installers
\`\`\`bash
# Install server
sudo installer -pkg artifacts/R2MIDI-Server-$VERSION*.pkg -target /

# Install client  
sudo installer -pkg artifacts/R2MIDI-Client-$VERSION*.pkg -target /
\`\`\`

### Manual Installation
\`\`\`bash
# Copy apps to Applications folder
cp -R build_server/dist/R2MIDI\\ Server.app /Applications/
cp -R build_client/dist/R2MIDI\\ Client.app /Applications/
\`\`\`

## Usage

### Start Server
\`\`\`bash
open "/Applications/R2MIDI Server.app"
# Server will be available at: http://localhost:8000
\`\`\`

### Start Client
\`\`\`bash
open "/Applications/R2MIDI Client.app"
\`\`\`

## Verification Commands

\`\`\`bash
# Verify package signatures
pkgutil --check-signature artifacts/*.pkg

# Verify app signatures
codesign --verify --deep --strict --verbose=2 "/Applications/R2MIDI Server.app"
codesign --verify --deep --strict --verbose=2 "/Applications/R2MIDI Client.app"

# Check Gatekeeper
spctl --assess --type exec --verbose "/Applications/R2MIDI Server.app"
spctl --assess --type exec --verbose "/Applications/R2MIDI Client.app"
\`\`\`

---
Generated by build-all-local.sh (Enhanced Build System)
EOF

    log_success "Build report created: $report_file"
}

# Cleanup function
cleanup() {
    if [ -n "${TEMP_KEYCHAIN:-}" ]; then
        log_info "Cleaning up temporary keychain: $TEMP_KEYCHAIN"
        security delete-keychain "$TEMP_KEYCHAIN" 2>/dev/null || true
    fi

    if [ "$IS_GITHUB_ACTIONS" = true ]; then
        rm -f /tmp/github_app_config.json
        rm -rf /tmp/github_certs
    fi
}

# Set up cleanup trap
trap cleanup EXIT INT TERM

# Main execution
main() {
    local overall_start_time=$(start_timer)

    log_step "Starting R2MIDI Build System"
    log_info "Build configuration:"
    log_info "  Version: $VERSION"
    log_info "  Build Type: $BUILD_TYPE"
    log_info "  Skip Signing: $SKIP_SIGNING"
    log_info "  Skip Notarization: $SKIP_NOTARIZATION"
    log_info "  Clean Build: $CLEAN_BUILD"
    log_info "  Environment: $([ "$IS_GITHUB_ACTIONS" = true ] && echo "GitHub Actions" || echo "Local Development")"

    # Track build progress
    local total_steps=7
    local current_step=0

    # Step 1: Environment check
    current_step=$((current_step + 1))
    log_progress "$current_step" "$total_steps" "Checking Environment"
    check_environment

    # Step 2: Version extraction
    current_step=$((current_step + 1))
    log_progress "$current_step" "$total_steps" "Extracting Version"
    extract_version

    # Step 3: Clean builds (if requested)
    current_step=$((current_step + 1))
    log_progress "$current_step" "$total_steps" "Cleaning Previous Builds"
    clean_builds

    # Step 4: Certificate setup
    current_step=$((current_step + 1))
    log_progress "$current_step" "$total_steps" "Setting Up Certificates"
    setup_build_certificates

    # Create artifacts directory
    log_info "Creating artifacts directory..."
    mkdir -p artifacts
    log_success "Artifacts directory ready: $(pwd)/artifacts"

    # Step 5: Build components
    current_step=$((current_step + 1))
    log_progress "$current_step" "$total_steps" "Building Components"

    local build_success=true
    local components_built=0
    local components_failed=0

    # Build server
    log_info "Building server component (1/2)..."
    if build_component "server"; then
        components_built=$((components_built + 1))
        log_success "Server component build completed"
    else
        components_failed=$((components_failed + 1))
        log_error "Server component build failed"
        build_success=false
    fi

    # Build client  
    log_info "Building client component (2/2)..."
    if build_component "client"; then
        components_built=$((components_built + 1))
        log_success "Client component build completed"
    else
        components_failed=$((components_failed + 1))
        log_error "Client component build failed"
        build_success=false
    fi

    log_info "Component build summary: $components_built built, $components_failed failed"

    # Step 6: Signing and notarization
    current_step=$((current_step + 1))
    log_progress "$current_step" "$total_steps" "Signing and Notarization"

    if [ "$build_success" = true ]; then
        log_info "Proceeding with signing and notarization..."
        if ! enhanced_signing; then
            build_success=false
            log_error "Signing and notarization failed"
        fi
    else
        log_warning "Skipping signing due to build failures"
    fi

    # Step 7: Generate report
    current_step=$((current_step + 1))
    log_progress "$current_step" "$total_steps" "Generating Build Report"
    generate_build_report

    # Final summary with comprehensive statistics
    local overall_duration=$(end_timer "$overall_start_time" "Complete Build Process")
    log_step "Build Summary"

    # Show certificate summary if available
    if [ "$(type -t get_certificate_summary 2>/dev/null)" = "function" ]; then
        get_certificate_summary
    fi

    # Count artifacts
    local pkg_count=0
    local app_count=0
    local total_size=0

    if [ -d "artifacts" ]; then
        pkg_count=$(find artifacts -name "*.pkg" 2>/dev/null | wc -l)
        app_count=$(find . -name "*.app" -type d 2>/dev/null | wc -l)
    fi

    log_info "Build Statistics:"
    log_info "  Total Duration: ${overall_duration}s"
    log_info "  Components Built: $components_built"
    log_info "  Components Failed: $components_failed"
    log_info "  Packages Generated: $pkg_count"
    log_info "  Applications Built: $app_count"
    log_info "  Log File: $LOG_FILE"

    if [ "$build_success" = true ]; then
        log_success "🎉 Complete build finished successfully!"

        # List generated packages with details
        if [ "$pkg_count" -gt 0 ]; then
            log_info "Generated packages:"
            find artifacts -name "*.pkg" 2>/dev/null | while read pkg; do
                if [ -f "$pkg" ]; then
                    local size=$(du -sh "$pkg" 2>/dev/null | cut -f1 || echo "unknown")
                    local pkg_name=$(basename "$pkg")
                    log_success "  $pkg_name ($size)"

                    # Check if package is signed
                    if pkgutil --check-signature "$pkg" >/dev/null 2>&1; then
                        log_info "    ✅ Package is signed"
                    else
                        log_warning "    ⚠️  Package is not signed"
                    fi
                fi
            done
        fi

        log_info "Next steps:"
        log_info "  1. Test installation: sudo installer -pkg artifacts/R2MIDI-*-$VERSION*.pkg -target /"
        log_info "  2. Launch applications from /Applications/"
        log_info "  3. Check build report: artifacts/BUILD_REPORT_$VERSION.md"
        log_info "  4. Review build log: $LOG_FILE"

        if [ "$SKIP_SIGNING" = false ] && [ "$SKIP_NOTARIZATION" = false ]; then
            log_success "Packages are signed and notarized for distribution"
        fi

        exit 0
    else
        log_error "Build completed with errors"
        log_error "Failed components: $components_failed"
        log_error "Check the logs above for details"
        log_error "Build log available at: $LOG_FILE"
        log_info "Partial build report: artifacts/BUILD_REPORT_$VERSION.md"

        exit 1
    fi
}

# Run main function
main "$@"
