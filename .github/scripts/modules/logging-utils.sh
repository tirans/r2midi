#!/bin/bash

# logging-utils.sh - Centralized logging utilities
# Provides consistent logging functions with timestamps, colors, and different log levels

# Color codes for terminal output
# Guard against multiple sourcing
if [ -z "${LOGGING_UTILS_LOADED:-}" ]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly WHITE='\033[1;37m'
    readonly NC='\033[0m' # No Color
    readonly LOGGING_UTILS_LOADED=1
fi

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARNING=2
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_CRITICAL=4

# Default log level (can be overridden by environment variable)
LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

# Log file (optional)
LOG_FILE=${LOG_FILE:-}

# Function to get timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to get ISO timestamp for file names
get_iso_timestamp() {
    date '+%Y%m%d_%H%M%S'
}

# Core logging function
write_log() {
    local level="$1"
    local level_num="$2"
    local color="$3"
    local icon="$4"
    local message="$5"

    # Check if we should log this level
    if [ "$level_num" -lt "$LOG_LEVEL" ]; then
        return 0
    fi

    local timestamp=$(get_timestamp)
    local formatted_message="[$timestamp] $icon $message"

    # Output to console with color
    if [ -t 1 ]; then  # Check if stdout is a terminal
        echo -e "${color}${formatted_message}${NC}"
    else
        echo "$formatted_message"
    fi

    # Output to log file if specified
    if [ -n "$LOG_FILE" ]; then
        echo "$formatted_message" >> "$LOG_FILE"
    fi
}

# Debug logging
log_debug() {
    write_log "DEBUG" "$LOG_LEVEL_DEBUG" "$PURPLE" "🔍" "$1"
}

# Info logging
log_info() {
    write_log "INFO" "$LOG_LEVEL_INFO" "$BLUE" "ℹ️ " "$1"
}

# Success logging
log_success() {
    write_log "SUCCESS" "$LOG_LEVEL_INFO" "$GREEN" "✅" "$1"
}

# Warning logging
log_warning() {
    write_log "WARNING" "$LOG_LEVEL_WARNING" "$YELLOW" "⚠️ " "$1"
}

# Error logging
log_error() {
    write_log "ERROR" "$LOG_LEVEL_ERROR" "$RED" "❌" "$1"
}

# Critical logging
log_critical() {
    write_log "CRITICAL" "$LOG_LEVEL_CRITICAL" "$RED" "🚨" "$1"
}

# Step logging (for major operations)
log_step() {
    local message="$1"
    local separator_length=60

    echo ""
    write_log "STEP" "$LOG_LEVEL_INFO" "$CYAN" "🔄" "$message"
    echo "$(printf '=%.0s' $(seq 1 $separator_length))"
}

# Progress logging
log_progress() {
    local current="$1"
    local total="$2"
    local message="$3"

    local percentage=$((current * 100 / total))
    write_log "PROGRESS" "$LOG_LEVEL_INFO" "$BLUE" "📊" "[$current/$total] ($percentage%) $message"
}

# Command logging (logs the command being executed)
log_command() {
    local command="$1"
    write_log "COMMAND" "$LOG_LEVEL_DEBUG" "$PURPLE" "🔧" "Executing: $command"
}

# Result logging (logs command results)
log_result() {
    local exit_code="$1"
    local command="$2"

    if [ "$exit_code" -eq 0 ]; then
        log_success "Command succeeded: $command"
    else
        log_error "Command failed (exit code: $exit_code): $command"
    fi
}

# File operation logging
log_file_op() {
    local operation="$1"
    local file_path="$2"
    local details="${3:-}"

    local message="$operation: $file_path"
    if [ -n "$details" ]; then
        message="$message ($details)"
    fi

    write_log "FILE_OP" "$LOG_LEVEL_INFO" "$CYAN" "📁" "$message"
}

# Network operation logging
log_network() {
    local operation="$1"
    local endpoint="$2"
    local details="${3:-}"

    local message="$operation: $endpoint"
    if [ -n "$details" ]; then
        message="$message ($details)"
    fi

    write_log "NETWORK" "$LOG_LEVEL_INFO" "$BLUE" "🌐" "$message"
}

# Security operation logging
log_security() {
    local operation="$1"
    local details="$2"

    write_log "SECURITY" "$LOG_LEVEL_INFO" "$YELLOW" "🔐" "$operation: $details"
}

# Performance logging
log_performance() {
    local operation="$1"
    local duration="$2"
    local details="${3:-}"

    local message="$operation completed in ${duration}s"
    if [ -n "$details" ]; then
        message="$message ($details)"
    fi

    write_log "PERFORMANCE" "$LOG_LEVEL_INFO" "$GREEN" "⏱️ " "$message"
}

# Function to start timing an operation
start_timer() {
    echo $(date +%s)
}

# Function to end timing and log performance
end_timer() {
    local start_time="$1"
    local operation="$2"
    local details="${3:-}"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_performance "$operation" "$duration" "$details"
    echo "$duration"
}

# Function to set log level from string
set_log_level() {
    local level_string="$1"

    case "${level_string^^}" in
        "DEBUG")
            LOG_LEVEL=$LOG_LEVEL_DEBUG
            ;;
        "INFO")
            LOG_LEVEL=$LOG_LEVEL_INFO
            ;;
        "WARNING"|"WARN")
            LOG_LEVEL=$LOG_LEVEL_WARNING
            ;;
        "ERROR")
            LOG_LEVEL=$LOG_LEVEL_ERROR
            ;;
        "CRITICAL"|"CRIT")
            LOG_LEVEL=$LOG_LEVEL_CRITICAL
            ;;
        *)
            log_warning "Unknown log level: $level_string, keeping current level"
            ;;
    esac

    log_info "Log level set to: $level_string"
}

# Function to set log file
set_log_file() {
    local file_path="$1"
    local create_dir="${2:-true}"

    # Create directory if it doesn't exist
    if [ "$create_dir" = "true" ]; then
        local dir_path=$(dirname "$file_path")
        if [ ! -d "$dir_path" ]; then
            mkdir -p "$dir_path"
        fi
    fi

    LOG_FILE="$file_path"
    log_info "Log file set to: $LOG_FILE"

    # Write header to log file
    {
        echo "========================================"
        echo "Log started at: $(get_timestamp)"
        echo "Script: ${0:-unknown}"
        echo "PID: $$"
        echo "User: $(whoami)"
        echo "Working Directory: $(pwd)"
        echo "========================================"
    } >> "$LOG_FILE"
}

# Function to create a log file with automatic naming
create_auto_log_file() {
    local base_name="${1:-build}"
    local log_dir="${2:-logs}"

    # Create logs directory if it doesn't exist
    mkdir -p "$log_dir"

    # Generate log file name with timestamp
    local timestamp=$(get_iso_timestamp)
    local log_file="$log_dir/${base_name}_${timestamp}.log"

    set_log_file "$log_file"
    echo "$log_file"
}

# Function to log system information
log_system_info() {
    log_step "System Information"
    log_info "Operating System: $(uname -s) $(uname -r)"
    log_info "Architecture: $(uname -m)"
    log_info "Hostname: $(hostname)"
    log_info "User: $(whoami)"
    log_info "Working Directory: $(pwd)"
    log_info "Shell: $SHELL"
    log_info "PATH: $PATH"

    # macOS specific information
    if [ "$(uname)" = "Darwin" ]; then
        local macos_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
        local build_version=$(sw_vers -buildVersion 2>/dev/null || echo "unknown")
        log_info "macOS Version: $macos_version (Build: $build_version)"

        # Xcode information
        if command -v xcodebuild >/dev/null 2>&1; then
            local xcode_version=$(xcodebuild -version 2>/dev/null | head -1 || echo "unknown")
            log_info "Xcode: $xcode_version"
        fi
    fi

    # Environment variables of interest
    local env_vars=("GITHUB_ACTIONS" "CI" "APPLE_ID" "APPLE_TEAM_ID" "BUILD_TYPE")
    for var in "${env_vars[@]}"; do
        if [ -n "${!var:-}" ]; then
            if [[ "$var" == *"PASSWORD"* ]] || [[ "$var" == *"SECRET"* ]]; then
                log_info "$var: [REDACTED]"
            else
                log_info "$var: ${!var}"
            fi
        fi
    done
}

# Function to log environment summary
log_environment() {
    local env_type="${1:-unknown}"

    log_step "Environment: $env_type"

    case "$env_type" in
        "github")
            log_info "Running in GitHub Actions"
            log_info "Repository: ${GITHUB_REPOSITORY:-unknown}"
            log_info "Workflow: ${GITHUB_WORKFLOW:-unknown}"
            log_info "Run ID: ${GITHUB_RUN_ID:-unknown}"
            log_info "Actor: ${GITHUB_ACTOR:-unknown}"
            ;;
        "local")
            log_info "Running in local development environment"
            ;;
        *)
            log_info "Environment type: $env_type"
            ;;
    esac
}

# Function to create a summary report
create_summary_report() {
    local operation="$1"
    local status="$2"
    local details="${3:-}"
    local output_file="${4:-}"

    local timestamp=$(get_timestamp)
    local summary="
========================================
$operation Summary Report
========================================
Status: $status
Timestamp: $timestamp
Details: $details
========================================
"

    if [ "$status" = "SUCCESS" ]; then
        log_success "$operation completed successfully"
    else
        log_error "$operation failed: $details"
    fi

    if [ -n "$output_file" ]; then
        echo "$summary" > "$output_file"
        log_info "Summary report written to: $output_file"
    fi

    echo "$summary"
}

# Function to log with custom icon and color
log_custom() {
    local icon="$1"
    local color="$2"
    local message="$3"
    local level_num="${4:-$LOG_LEVEL_INFO}"

    write_log "CUSTOM" "$level_num" "$color" "$icon" "$message"
}

# Function to log a separator
log_separator() {
    local char="${1:--}"
    local length="${2:-60}"

    echo "$(printf "${char}%.0s" $(seq 1 $length))"
}

# Function to log a banner
log_banner() {
    local message="$1"
    local char="${2:-=}"
    local padding="${3:-2}"

    local message_length=${#message}
    local total_length=$((message_length + padding * 2))

    log_separator "$char" "$total_length"
    printf "%*s%s%*s\n" $padding "" "$message" $padding ""
    log_separator "$char" "$total_length"
}

# Export all logging functions
export -f get_timestamp
export -f get_iso_timestamp
export -f write_log
export -f log_debug
export -f log_info
export -f log_success
export -f log_warning
export -f log_error
export -f log_critical
export -f log_step
export -f log_progress
export -f log_command
export -f log_result
export -f log_file_op
export -f log_network
export -f log_security
export -f log_performance
export -f start_timer
export -f end_timer
export -f set_log_level
export -f set_log_file
export -f create_auto_log_file
export -f log_system_info
export -f log_environment
export -f create_summary_report
export -f log_custom
export -f log_separator
export -f log_banner

# Export log level constants
export LOG_LEVEL_DEBUG
export LOG_LEVEL_INFO
export LOG_LEVEL_WARNING
export LOG_LEVEL_ERROR
export LOG_LEVEL_CRITICAL
