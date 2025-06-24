#!/bin/bash
set -euo pipefail

# Simulate GitHub Actions environment
export GITHUB_ACTIONS=true
export IS_GITHUB_ACTIONS=true

# Source the build script to get access to its functions
source build-all-local.sh

# Override the main function to prevent full execution
main() {
    echo "Testing environment check and cleanup with existing virtual environments..."
    
    # Test the clean_builds function specifically
    clean_builds
    
    # Verify virtual environments still exist after cleanup
    if [ -d "venv_client" ] && [ -x "venv_client/bin/python" ]; then
        echo "✅ Client virtual environment preserved after cleanup"
    else
        echo "❌ Client virtual environment was removed during cleanup"
        exit 1
    fi
    
    if [ -d "venv_server" ] && [ -x "venv_server/bin/python" ]; then
        echo "✅ Server virtual environment preserved after cleanup"
    else
        echo "❌ Server virtual environment was removed during cleanup"
        exit 1
    fi
    
    echo "✅ Virtual environments successfully preserved during GitHub Actions cleanup!"
}

# Don't run main automatically
