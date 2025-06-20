#!/bin/bash

# test-configure-build.sh - Test the configure-build script locally
# Usage: ./test-configure-build.sh

set -e

echo "🧪 Testing configure-build.sh script..."
echo ""

# Test function
test_configure_build() {
    local test_name="$1"
    local event_name="$2"
    local input_version="$3"
    local input_build_type="$4"
    local input_runner_type="$5"
    local default_build_type="$6"
    
    echo "📋 Test: $test_name"
    echo "  Parameters: event=$event_name, version=$input_version, build_type=$input_build_type, runner=$input_runner_type, default=$default_build_type"
    
    # Create temporary files for GitHub outputs
    temp_output=$(mktemp)
    temp_env=$(mktemp)
    
    export GITHUB_OUTPUT="$temp_output"
    export GITHUB_ENV="$temp_env"
    
    # Run the script
    echo "  🔧 Running configure-build.sh..."
    if ./.github/scripts/configure-build.sh "$event_name" "$input_version" "$input_build_type" "$input_runner_type" "$default_build_type"; then
        echo "  ✅ Script executed successfully"
        
        echo "  📤 GitHub Outputs:"
        if [ -f "$temp_output" ]; then
            cat "$temp_output" | sed 's/^/    /'
        fi
        
        echo "  🌍 GitHub Environment:"
        if [ -f "$temp_env" ]; then
            cat "$temp_env" | sed 's/^/    /'
        fi
    else
        echo "  ❌ Script failed"
    fi
    
    # Cleanup
    rm -f "$temp_output" "$temp_env"
    unset GITHUB_OUTPUT GITHUB_ENV
    
    echo ""
}

# Check if we're in the right directory
if [ ! -f ".github/scripts/configure-build.sh" ]; then
    echo "❌ Error: Must run from repository root (configure-build.sh not found)"
    exit 1
fi

if [ ! -f "pyproject.toml" ]; then
    echo "❌ Error: pyproject.toml not found in repository root"
    exit 1
fi

# Make sure script is executable
chmod +x .github/scripts/configure-build.sh

echo "🏠 Repository root confirmed"
echo "📦 pyproject.toml found"
echo ""

# Run tests
test_configure_build "Push trigger with production default" "push" "" "" "self-hosted" "production"
test_configure_build "Workflow dispatch with dev build" "workflow_dispatch" "" "dev" "self-hosted" "production"
test_configure_build "Workflow call with specific version" "workflow_call" "1.2.3" "staging" "macos-13" "production"
test_configure_build "Default parameters" "" "" "" "" ""

echo "🎉 All tests completed!"
