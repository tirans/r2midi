#!/bin/bash

# build-utils.sh - Build utilities and resilience functions
# Provides common build operations, retry logic, and error handling

# Source logging utilities
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
if [ -f "$SCRIPT_DIR/logging-utils.sh" ]; then
    source "$SCRIPT_DIR/logging-utils.sh"
else
    # Fallback logging functions
    log_info() { echo "ℹ️  $1"; }
    log_success() { echo "✅ $1"; }
    log_warning() { echo "⚠️  $1"; }
    log_error() { echo "❌ $1"; }
    log_step() { echo ""; echo "🔄 $1"; echo "$(printf '=%.0s' {1..50})"; }
fi

# Default retry settings
DEFAULT_RETRY_COUNT=3
DEFAULT_RETRY_DELAY=5
DEFAULT_TIMEOUT=300

# Function to execute command with retry logic and detailed logging
execute_with_retry() {
    local command="$1"
    local operation_name="${2:-Command}"
    local max_attempts="${3:-$DEFAULT_RETRY_COUNT}"
    local delay="${4:-$DEFAULT_RETRY_DELAY}"
    local timeout="${5:-$DEFAULT_TIMEOUT}"
    
    log_step "Executing: $operation_name"
    log_command "$command"
    
    local start_time=$(start_timer)
    
    for attempt in $(seq 1 $max_attempts); do
        log_info "Attempt $attempt/$max_attempts for: $operation_name"
        
        # Execute command with timeout
        local exit_code=0
        if command -v timeout >/dev/null 2>&1; then
            timeout "$timeout" bash -c "$command" || exit_code=$?
        else
            # Fallback for systems without timeout command
            eval "$command" || exit_code=$?
        fi
        
        if [ $exit_code -eq 0 ]; then
            local duration=$(end_timer "$start_time" "$operation_name")
            log_success "$operation_name completed successfully in ${duration}s"
            return 0
        else
            log_warning "$operation_name failed (attempt $attempt/$max_attempts) - Exit code: $exit_code"
            
            if [ $attempt -lt $max_attempts ]; then
                log_info "Waiting ${delay}s before retry..."
                sleep $delay
                delay=$((delay * 2))  # Exponential backoff
            else
                local duration=$(end_timer "$start_time" "$operation_name")
                log_error "$operation_name failed after $max_attempts attempts in ${duration}s"
                return $exit_code
            fi
        fi
    done
}

# Function to check system requirements
check_system_requirements() {
    local required_tools=("$@")
    
    log_step "Checking System Requirements"
    
    local missing_tools=()
    local available_tools=()
    
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            available_tools+=("$tool")
            local version=$(get_tool_version "$tool")
            log_success "$tool is available${version:+ ($version)}"
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
        return 1
    fi
    
    log_success "All required tools are available"
    return 0
}

# Function to get tool version
get_tool_version() {
    local tool="$1"
    
    case "$tool" in
        "python3")
            python3 --version 2>/dev/null | cut -d' ' -f2 || echo ""
            ;;
        "codesign"|"security"|"pkgbuild"|"productsign")
            # These tools don't have standard version flags
            echo ""
            ;;
        "xcrun")
            xcrun --version 2>/dev/null | head -1 || echo ""
            ;;
        *)
            "$tool" --version 2>/dev/null | head -1 || echo ""
            ;;
    esac
}

# Function to verify file integrity
verify_file_integrity() {
    local file_path="$1"
    local expected_size="${2:-}"
    local expected_checksum="${3:-}"
    
    log_info "Verifying file integrity: $(basename "$file_path")"
    
    if [ ! -f "$file_path" ]; then
        log_error "File does not exist: $file_path"
        return 1
    fi
    
    # Check file size
    local actual_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo "0")
    log_info "File size: $actual_size bytes"
    
    if [ -n "$expected_size" ] && [ "$actual_size" != "$expected_size" ]; then
        log_error "File size mismatch. Expected: $expected_size, Actual: $actual_size"
        return 1
    fi
    
    # Check checksum if provided
    if [ -n "$expected_checksum" ]; then
        local actual_checksum=$(shasum -a 256 "$file_path" | cut -d' ' -f1)
        log_info "File checksum: $actual_checksum"
        
        if [ "$actual_checksum" != "$expected_checksum" ]; then
            log_error "Checksum mismatch. Expected: $expected_checksum, Actual: $actual_checksum"
            return 1
        fi
    fi
    
    log_success "File integrity verified: $(basename "$file_path")"
    return 0
}

# Function to create backup of important files
create_backup() {
    local source_path="$1"
    local backup_dir="${2:-backups}"
    local backup_name="${3:-}"
    
    if [ ! -e "$source_path" ]; then
        log_error "Source path does not exist: $source_path"
        return 1
    fi
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Generate backup name if not provided
    if [ -z "$backup_name" ]; then
        local timestamp=$(get_iso_timestamp)
        backup_name="$(basename "$source_path")_backup_$timestamp"
    fi
    
    local backup_path="$backup_dir/$backup_name"
    
    log_info "Creating backup: $source_path -> $backup_path"
    
    if [ -d "$source_path" ]; then
        if cp -R "$source_path" "$backup_path"; then
            log_success "Directory backup created: $backup_path"
        else
            log_error "Failed to create directory backup"
            return 1
        fi
    else
        if cp "$source_path" "$backup_path"; then
            log_success "File backup created: $backup_path"
        else
            log_error "Failed to create file backup"
            return 1
        fi
    fi
    
    echo "$backup_path"
    return 0
}

# Function to clean build directories safely
clean_build_directories() {
    local directories=("$@")
    
    log_step "Cleaning Build Directories"
    
    for dir in "${directories[@]}"; do
        if [ -d "$dir" ]; then
            log_info "Cleaning directory: $dir"
            
            # Safety check - don't delete if it looks like a system directory
            if [[ "$dir" =~ ^(/|/usr|/bin|/sbin|/etc|/var|/tmp)$ ]]; then
                log_error "Refusing to clean system directory: $dir"
                continue
            fi
            
            # Create backup before cleaning if directory contains important files
            if find "$dir" -name "*.app" -o -name "*.pkg" -o -name "*.dmg" | head -1 | grep -q .; then
                log_info "Directory contains build artifacts, creating backup..."
                create_backup "$dir" "backups/pre-clean" >/dev/null
            fi
            
            if rm -rf "$dir"/*; then
                log_success "Cleaned directory: $dir"
            else
                log_warning "Failed to clean directory: $dir"
            fi
        else
            log_info "Directory does not exist (skipping): $dir"
        fi
    done
}

# Function to validate build environment
validate_build_environment() {
    local env_type="${1:-local}"
    
    log_step "Validating Build Environment: $env_type"
    
    # Check operating system
    if [ "$(uname)" != "Darwin" ]; then
        log_error "This build system requires macOS"
        return 1
    fi
    
    local macos_version=$(sw_vers -productVersion)
    log_info "macOS Version: $macos_version"
    
    # Check minimum macOS version (10.15 for notarization)
    local major_version=$(echo "$macos_version" | cut -d. -f1)
    local minor_version=$(echo "$macos_version" | cut -d. -f2)
    
    if [ "$major_version" -lt 10 ] || ([ "$major_version" -eq 10 ] && [ "$minor_version" -lt 15 ]); then
        log_warning "macOS 10.15+ recommended for full notarization support"
    fi
    
    # Environment-specific checks
    case "$env_type" in
        "github")
            log_info "Validating GitHub Actions environment..."
            
            # Check required environment variables
            local required_vars=("GITHUB_ACTIONS" "GITHUB_WORKSPACE")
            for var in "${required_vars[@]}"; do
                if [ -z "${!var:-}" ]; then
                    log_error "Required environment variable not set: $var"
                    return 1
                fi
            done
            
            log_success "GitHub Actions environment validated"
            ;;
            
        "local")
            log_info "Validating local development environment..."
            
            # Check for virtual environments
            local venv_dirs=("venv_client" "venv_server")
            for venv in "${venv_dirs[@]}"; do
                if [ ! -d "$venv" ]; then
                    log_warning "Virtual environment not found: $venv"
                fi
            done
            
            log_success "Local development environment validated"
            ;;
    esac
    
    return 0
}

# Function to monitor disk space
monitor_disk_space() {
    local min_free_gb="${1:-5}"
    local path="${2:-.}"
    
    log_info "Monitoring disk space for: $path"
    
    # Get available space in GB
    local available_space
    if command -v df >/dev/null 2>&1; then
        # macOS/Linux df command
        available_space=$(df -g "$path" 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
    else
        available_space="0"
    fi
    
    log_info "Available disk space: ${available_space}GB"
    
    if [ "$available_space" -lt "$min_free_gb" ]; then
        log_warning "Low disk space: ${available_space}GB available (minimum: ${min_free_gb}GB)"
        return 1
    fi
    
    log_success "Sufficient disk space available"
    return 0
}

# Function to create build manifest
create_build_manifest() {
    local version="$1"
    local build_type="$2"
    local output_file="${3:-build_manifest.json}"
    
    log_info "Creating build manifest: $output_file"
    
    local timestamp=$(get_timestamp)
    local iso_timestamp=$(get_iso_timestamp)
    local build_host=$(hostname)
    local build_user=$(whoami)
    local build_dir=$(pwd)
    
    # Collect system information
    local os_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    local architecture=$(uname -m)
    
    # Collect tool versions
    local python_version=$(python3 --version 2>/dev/null | cut -d' ' -f2 || echo "unknown")
    local xcode_version=$(xcodebuild -version 2>/dev/null | head -1 | cut -d' ' -f2 || echo "unknown")
    
    cat > "$output_file" << EOF
{
  "build_info": {
    "version": "$version",
    "build_type": "$build_type",
    "timestamp": "$timestamp",
    "iso_timestamp": "$iso_timestamp",
    "build_host": "$build_host",
    "build_user": "$build_user",
    "build_directory": "$build_dir"
  },
  "system_info": {
    "os": "macOS",
    "os_version": "$os_version",
    "architecture": "$architecture",
    "python_version": "$python_version",
    "xcode_version": "$xcode_version"
  },
  "environment": {
    "github_actions": "${GITHUB_ACTIONS:-false}",
    "ci": "${CI:-false}",
    "runner_os": "${RUNNER_OS:-}",
    "github_repository": "${GITHUB_REPOSITORY:-}",
    "github_ref": "${GITHUB_REF:-}",
    "github_sha": "${GITHUB_SHA:-}"
  },
  "artifacts": []
}
EOF
    
    log_success "Build manifest created: $output_file"
    return 0
}

# Function to add artifact to manifest
add_artifact_to_manifest() {
    local manifest_file="$1"
    local artifact_path="$2"
    local artifact_type="$3"
    local signed="${4:-false}"
    local notarized="${5:-false}"
    
    if [ ! -f "$manifest_file" ]; then
        log_error "Manifest file not found: $manifest_file"
        return 1
    fi
    
    if [ ! -e "$artifact_path" ]; then
        log_error "Artifact not found: $artifact_path"
        return 1
    fi
    
    local artifact_name=$(basename "$artifact_path")
    local artifact_size=$(stat -f%z "$artifact_path" 2>/dev/null || stat -c%s "$artifact_path" 2>/dev/null || echo "0")
    local artifact_checksum=$(shasum -a 256 "$artifact_path" | cut -d' ' -f1)
    
    log_info "Adding artifact to manifest: $artifact_name"
    
    # Create temporary file with updated manifest
    local temp_file=$(mktemp)
    
    # Use Python to update JSON (more reliable than shell manipulation)
    python3 << EOF
import json
import sys

try:
    with open('$manifest_file', 'r') as f:
        manifest = json.load(f)
    
    artifact = {
        "name": "$artifact_name",
        "path": "$artifact_path",
        "type": "$artifact_type",
        "size": $artifact_size,
        "checksum": "$artifact_checksum",
        "signed": $signed,
        "notarized": $notarized
    }
    
    manifest["artifacts"].append(artifact)
    
    with open('$temp_file', 'w') as f:
        json.dump(manifest, f, indent=2)
    
    print("Artifact added successfully")
except Exception as e:
    print(f"Error updating manifest: {e}")
    sys.exit(1)
EOF
    
    if [ $? -eq 0 ]; then
        mv "$temp_file" "$manifest_file"
        log_success "Artifact added to manifest: $artifact_name"
        return 0
    else
        rm -f "$temp_file"
        log_error "Failed to add artifact to manifest"
        return 1
    fi
}

# Function to validate artifacts
validate_artifacts() {
    local manifest_file="$1"
    
    if [ ! -f "$manifest_file" ]; then
        log_error "Manifest file not found: $manifest_file"
        return 1
    fi
    
    log_step "Validating Build Artifacts"
    
    # Use Python to parse and validate
    python3 << EOF
import json
import os
import hashlib
import sys

def calculate_checksum(file_path):
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

try:
    with open('$manifest_file', 'r') as f:
        manifest = json.load(f)
    
    artifacts = manifest.get('artifacts', [])
    if not artifacts:
        print("No artifacts found in manifest")
        sys.exit(0)
    
    all_valid = True
    
    for artifact in artifacts:
        name = artifact['name']
        path = artifact['path']
        expected_size = artifact['size']
        expected_checksum = artifact['checksum']
        
        print(f"Validating: {name}")
        
        if not os.path.exists(path):
            print(f"  ERROR: File not found: {path}")
            all_valid = False
            continue
        
        actual_size = os.path.getsize(path)
        if actual_size != expected_size:
            print(f"  ERROR: Size mismatch. Expected: {expected_size}, Actual: {actual_size}")
            all_valid = False
            continue
        
        actual_checksum = calculate_checksum(path)
        if actual_checksum != expected_checksum:
            print(f"  ERROR: Checksum mismatch. Expected: {expected_checksum}, Actual: {actual_checksum}")
            all_valid = False
            continue
        
        print(f"  SUCCESS: {name} validated")
    
    if all_valid:
        print("All artifacts validated successfully")
        sys.exit(0)
    else:
        print("Some artifacts failed validation")
        sys.exit(1)

except Exception as e:
    print(f"Error validating artifacts: {e}")
    sys.exit(1)
EOF
    
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        log_success "All artifacts validated successfully"
        return 0
    else
        log_error "Artifact validation failed"
        return 1
    fi
}

# Function to setup build environment
setup_build_environment() {
    local build_type="${1:-local}"
    local version="${2:-1.0.0}"
    
    log_step "Setting Up Build Environment"
    
    # Create necessary directories
    local build_dirs=("artifacts" "logs" "backups")
    for dir in "${build_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_info "Created directory: $dir"
        fi
    done
    
    # Setup logging
    local log_file=$(create_auto_log_file "build_${build_type}" "logs")
    log_info "Build log: $log_file"
    
    # Create build manifest
    create_build_manifest "$version" "$build_type" "artifacts/build_manifest.json"
    
    # Log system information
    log_system_info
    
    # Validate environment
    validate_build_environment "$build_type"
    
    # Monitor disk space
    monitor_disk_space 5
    
    log_success "Build environment setup completed"
    return 0
}

# Export all functions
export -f execute_with_retry
export -f check_system_requirements
export -f get_tool_version
export -f verify_file_integrity
export -f create_backup
export -f clean_build_directories
export -f validate_build_environment
export -f monitor_disk_space
export -f create_build_manifest
export -f add_artifact_to_manifest
export -f validate_artifacts
export -f setup_build_environment