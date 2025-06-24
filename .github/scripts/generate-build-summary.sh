#!/bin/bash
set -euo pipefail
# Generate build summary report
# Usage: generate-build-summary.sh <platform> <build_type> <version> <signing_mode>

PLATFORM="${1:-unknown}"
BUILD_TYPE="${2:-production}"
VERSION="${3:-1.0.0}"
SIGNING_MODE="${4:-unsigned}"

echo "📋 Generating build summary for $PLATFORM ($BUILD_TYPE, $VERSION, $SIGNING_MODE)..."

# Create artifacts directory if it doesn't exist
mkdir -p artifacts

# Function to get file size in human readable format
get_file_size() {
    local file="$1"
    if [ -f "$file" ]; then
        ls -lh "$file" | awk '{print $5}'
    else
        echo "N/A"
    fi
}

# Function to get file checksum
get_file_checksum() {
    local file="$1"
    if [ -f "$file" ] && command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    else
        echo "N/A"
    fi
}

# Function to check build status
check_build_status() {
    local component="$1"
    local dist_dir="$2"
    
    if [ -d "$dist_dir" ] && [ "$(ls -A "$dist_dir" 2>/dev/null)" ]; then
        echo "✅ SUCCESS"
        return 0
    else
        echo "❌ FAILED"
        return 1
    fi
}

# Function to list build artifacts
list_build_artifacts() {
    local dist_dir="$1"
    local prefix="$2"
    
    if [ -d "$dist_dir" ]; then
        echo "${prefix}Build Artifacts:"
        find "$dist_dir" -type f -name "*" | while read -r file; do
            local size=$(get_file_size "$file")
            local checksum=$(get_file_checksum "$file")
            echo "${prefix}  - $(basename "$file") ($size)"
            if [ "$checksum" != "N/A" ]; then
                echo "${prefix}    SHA256: $checksum"
            fi
        done
    else
        echo "${prefix}No build artifacts found"
    fi
}

# Generate main build summary
generate_main_summary() {
    local summary_file="artifacts/BUILD_SUMMARY_${PLATFORM}_${VERSION}.md"
    
    cat > "$summary_file" << EOF
# Build Summary Report

## Build Information
- **Platform**: $PLATFORM
- **Build Type**: $BUILD_TYPE
- **Version**: $VERSION
- **Signing Mode**: $SIGNING_MODE
- **Build Date**: $(date)
- **Build Host**: $(hostname)
- **Build User**: $(whoami)

## Environment Information
- **OS**: $(uname -s)
- **Architecture**: $(uname -m)
- **Python Version**: $(python --version 2>&1 || echo "Not available")
- **Git Commit**: $(git rev-parse HEAD 2>/dev/null || echo "Not available")
- **Git Branch**: $(git branch --show-current 2>/dev/null || echo "Not available")

## Build Status

EOF

    # Check client build status
    local client_status=$(check_build_status "Client" "r2midi_client/dist")
    echo "### R2MIDI Client: $client_status" >> "$summary_file"
    echo "" >> "$summary_file"
    list_build_artifacts "r2midi_client/dist" "" >> "$summary_file"
    echo "" >> "$summary_file"
    
    # Check server build status
    local server_status_1=$(check_build_status "Server" "dist")
    local server_status_2=$(check_build_status "Server" "server/dist")
    
    if [ "$server_status_1" = "✅ SUCCESS" ] || [ "$server_status_2" = "✅ SUCCESS" ]; then
        echo "### R2MIDI Server: ✅ SUCCESS" >> "$summary_file"
    else
        echo "### R2MIDI Server: ❌ FAILED" >> "$summary_file"
    fi
    echo "" >> "$summary_file"
    
    if [ -d "dist" ]; then
        list_build_artifacts "dist" "" >> "$summary_file"
    elif [ -d "server/dist" ]; then
        list_build_artifacts "server/dist" "" >> "$summary_file"
    else
        echo "No server build artifacts found" >> "$summary_file"
    fi
    echo "" >> "$summary_file"
    
    # Check packaging artifacts
    if [ -d "artifacts" ] && [ "$(ls -A artifacts/ 2>/dev/null | grep -v BUILD_SUMMARY)" ]; then
        echo "## Package Artifacts" >> "$summary_file"
        echo "" >> "$summary_file"
        find artifacts -maxdepth 1 -type f ! -name "BUILD_SUMMARY*" | while read -r file; do
            local size=$(get_file_size "$file")
            local checksum=$(get_file_checksum "$file")
            echo "- $(basename "$file") ($size)" >> "$summary_file"
            if [ "$checksum" != "N/A" ]; then
                echo "  - SHA256: $checksum" >> "$summary_file"
            fi
        done
        echo "" >> "$summary_file"
    fi
    
    # Add build logs if available
    if [ -f "build_summary.txt" ]; then
        echo "## Build Log Summary" >> "$summary_file"
        echo "" >> "$summary_file"
        echo "\`\`\`" >> "$summary_file"
        cat "build_summary.txt" >> "$summary_file"
        echo "\`\`\`" >> "$summary_file"
        echo "" >> "$summary_file"
    fi
    
    # Add validation reports if available
    if [ -f "build_environment_report.txt" ]; then
        echo "## Build Environment Report" >> "$summary_file"
        echo "" >> "$summary_file"
        echo "\`\`\`" >> "$summary_file"
        cat "build_environment_report.txt" >> "$summary_file"
        echo "\`\`\`" >> "$summary_file"
        echo "" >> "$summary_file"
    fi
    
    # Overall build result
    echo "## Overall Result" >> "$summary_file"
    echo "" >> "$summary_file"
    
    if [ "$client_status" = "✅ SUCCESS" ] && ([ "$server_status_1" = "✅ SUCCESS" ] || [ "$server_status_2" = "✅ SUCCESS" ]); then
        echo "🎉 **BUILD SUCCESSFUL** - All components built successfully!" >> "$summary_file"
        echo "" >> "$summary_file"
        echo "The build completed without errors and all artifacts are ready for distribution." >> "$summary_file"
    else
        echo "💥 **BUILD FAILED** - Some components failed to build!" >> "$summary_file"
        echo "" >> "$summary_file"
        echo "Please check the build logs above for details on what went wrong." >> "$summary_file"
    fi
    
    echo "✅ Build summary generated: $summary_file"
}

# Generate GitHub Actions summary
generate_github_summary() {
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        echo "📋 Updating GitHub Actions step summary..."
        
        echo "## 🏗️ Build Summary ($PLATFORM)" >> "$GITHUB_STEP_SUMMARY"
        echo "" >> "$GITHUB_STEP_SUMMARY"
        echo "| Component | Status | Artifacts |" >> "$GITHUB_STEP_SUMMARY"
        echo "|-----------|--------|-----------|" >> "$GITHUB_STEP_SUMMARY"
        
        # Client status
        local client_status=$(check_build_status "Client" "r2midi_client/dist")
        local client_artifacts="N/A"
        if [ -d "r2midi_client/dist" ]; then
            client_artifacts=$(find r2midi_client/dist -type f | wc -l)
        fi
        echo "| R2MIDI Client | $client_status | $client_artifacts files |" >> "$GITHUB_STEP_SUMMARY"
        
        # Server status
        local server_status_1=$(check_build_status "Server" "dist")
        local server_status_2=$(check_build_status "Server" "server/dist")
        local server_artifacts="N/A"
        
        if [ "$server_status_1" = "✅ SUCCESS" ] || [ "$server_status_2" = "✅ SUCCESS" ]; then
            local server_status="✅ SUCCESS"
            if [ -d "dist" ]; then
                server_artifacts=$(find dist -type f | wc -l)
            elif [ -d "server/dist" ]; then
                server_artifacts=$(find server/dist -type f | wc -l)
            fi
        else
            local server_status="❌ FAILED"
        fi
        echo "| R2MIDI Server | $server_status | $server_artifacts files |" >> "$GITHUB_STEP_SUMMARY"
        
        echo "" >> "$GITHUB_STEP_SUMMARY"
        echo "**Build Details:**" >> "$GITHUB_STEP_SUMMARY"
        echo "- Platform: $PLATFORM" >> "$GITHUB_STEP_SUMMARY"
        echo "- Version: $VERSION" >> "$GITHUB_STEP_SUMMARY"
        echo "- Build Type: $BUILD_TYPE" >> "$GITHUB_STEP_SUMMARY"
        echo "- Signing: $SIGNING_MODE" >> "$GITHUB_STEP_SUMMARY"
        echo "" >> "$GITHUB_STEP_SUMMARY"
    fi
}

# Generate JSON summary for automation
generate_json_summary() {
    local json_file="artifacts/build_summary_${PLATFORM}.json"
    
    # Check build statuses
    local client_success=false
    local server_success=false
    
    if check_build_status "Client" "r2midi_client/dist" >/dev/null; then
        client_success=true
    fi
    
    if check_build_status "Server" "dist" >/dev/null || check_build_status "Server" "server/dist" >/dev/null; then
        server_success=true
    fi
    
    cat > "$json_file" << EOF
{
  "platform": "$PLATFORM",
  "buildType": "$BUILD_TYPE",
  "version": "$VERSION",
  "signingMode": "$SIGNING_MODE",
  "buildDate": "$(date -u '+%Y-%m-%d %H:%M:%S UTC')",
  "buildHost": "$(hostname)",
  "gitCommit": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')",
  "gitBranch": "$(git branch --show-current 2>/dev/null || echo 'unknown')",
  "components": {
    "client": {
      "success": $client_success,
      "artifactsPath": "r2midi_client/dist"
    },
    "server": {
      "success": $server_success,
      "artifactsPath": "$([ -d "dist" ] && echo "dist" || echo "server/dist")"
    }
  },
  "overallSuccess": $([ "$client_success" = true ] && [ "$server_success" = true ] && echo true || echo false)
}
EOF
    
    echo "✅ JSON summary generated: $json_file"
}

# Main function
main() {
    echo "🚀 Starting build summary generation..."
    
    # Generate different types of summaries
    generate_main_summary
    generate_github_summary
    generate_json_summary
    
    # Create a simple text summary for quick reference
    local quick_summary="artifacts/quick_summary_${PLATFORM}.txt"
    cat > "$quick_summary" << EOF
R2MIDI Build Summary - $PLATFORM
================================
Version: $VERSION
Build Type: $BUILD_TYPE
Date: $(date)

Client: $(check_build_status "Client" "r2midi_client/dist")
Server: $(if check_build_status "Server" "dist" >/dev/null || check_build_status "Server" "server/dist" >/dev/null; then echo "✅ SUCCESS"; else echo "❌ FAILED"; fi)

Artifacts: $(find artifacts -maxdepth 1 -type f ! -name "*summary*" | wc -l) files
EOF
    
    echo "✅ Quick summary generated: $quick_summary"
    
    # List all generated summaries
    echo ""
    echo "📋 Generated summary files:"
    find artifacts -name "*summary*" -o -name "BUILD_SUMMARY*" | while read -r file; do
        echo "  - $file"
    done
    
    echo ""
    echo "🎉 Build summary generation completed!"
}

# Run main function
main "$@"