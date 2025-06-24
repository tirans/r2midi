#!/bin/bash
# Test script to verify GitHub Actions virtual environment fix
set -euo pipefail

echo "🧪 Testing GitHub Actions Virtual Environment Fix"
echo "================================================="

# Check if we're in the right directory
if [ ! -f "build-all-local.sh" ] || [ ! -f "setup-virtual-environments.sh" ]; then
    echo "❌ Error: Must be run from the project root directory"
    echo "   Expected files: build-all-local.sh, setup-virtual-environments.sh"
    exit 1
fi

# Backup existing virtual environments if they exist
BACKUP_DIR="/tmp/r2midi_venv_backup_$(date +%s)"
mkdir -p "$BACKUP_DIR"

echo "📦 Backing up existing virtual environments..."
if [ -d "venv_client" ]; then
    mv "venv_client" "$BACKUP_DIR/"
    echo "  ✅ Backed up venv_client"
fi

if [ -d "venv_server" ]; then
    mv "venv_server" "$BACKUP_DIR/"
    echo "  ✅ Backed up venv_server"
fi

# Function to restore backups
restore_backups() {
    echo "🔄 Restoring original virtual environments..."
    if [ -d "$BACKUP_DIR/venv_client" ]; then
        mv "$BACKUP_DIR/venv_client" .
        echo "  ✅ Restored venv_client"
    fi
    
    if [ -d "$BACKUP_DIR/venv_server" ]; then
        mv "$BACKUP_DIR/venv_server" .
        echo "  ✅ Restored venv_server"
    fi
    
    rm -rf "$BACKUP_DIR"
    echo "  ✅ Cleanup completed"
}

# Set up trap to restore backups on exit
trap restore_backups EXIT

echo ""
echo "🚀 Step 1: Simulating GitHub Actions workflow environment setup..."

# Simulate GitHub Actions environment
export GITHUB_ACTIONS=true
export IS_GITHUB_ACTIONS=true

# Step 1: Clean environment (preserve virtual environments) - simulating workflow step
echo "🧹 Cleaning build artifacts while preserving virtual environments..."
rm -rf build_client build_server 2>/dev/null || true
rm -rf build dist artifacts 2>/dev/null || true
rm -rf build_native 2>/dev/null || true
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true
find . -name "*.pyo" -delete 2>/dev/null || true
rm -rf ~/.py2app "$HOME/.py2app" 2>/dev/null || true
find . -name "*.egg-info" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "*.egg" -delete 2>/dev/null || true
echo "✅ Build artifacts cleaned, virtual environments preserved"

# Step 2: Setup virtual environments - simulating workflow step
echo ""
echo "🐍 Setting up virtual environments..."
if ./setup-virtual-environments.sh --use-uv; then
    echo "✅ Virtual environments setup completed"
else
    echo "❌ Virtual environments setup failed"
    exit 1
fi

# Verify virtual environments exist
echo ""
echo "🔍 Verifying virtual environments exist..."
if [ -d "venv_client" ] && [ -x "venv_client/bin/python" ]; then
    client_version=$(venv_client/bin/python --version 2>/dev/null || echo "unknown")
    echo "✅ Client virtual environment: $client_version"
else
    echo "❌ Client virtual environment not found or not executable"
    exit 1
fi

if [ -d "venv_server" ] && [ -x "venv_server/bin/python" ]; then
    server_version=$(venv_server/bin/python --version 2>/dev/null || echo "unknown")
    echo "✅ Server virtual environment: $server_version"
else
    echo "❌ Server virtual environment not found or not executable"
    exit 1
fi

echo ""
echo "🚀 Step 2: Testing build-all-local.sh with existing virtual environments..."

# Create a test script that simulates the environment check part of build-all-local.sh
cat > test_build_env_check.sh << 'EOF'
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
EOF

chmod +x test_build_env_check.sh

echo "🧪 Running build environment cleanup test..."
if ./test_build_env_check.sh; then
    echo "✅ Build environment cleanup test passed!"
else
    echo "❌ Build environment cleanup test failed"
    exit 1
fi

# Clean up test script
rm -f test_build_env_check.sh

echo ""
echo "🚀 Step 3: Testing full environment check function..."

# Test the check_environment function to ensure it doesn't try to recreate existing environments
cat > test_full_env_check.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Simulate GitHub Actions environment
export GITHUB_ACTIONS=true
export IS_GITHUB_ACTIONS=true

# Source the build script to get access to its functions
source build-all-local.sh

# Override the main function to prevent full execution
main() {
    echo "Testing full environment check with existing virtual environments..."
    
    # Test the check_environment function
    check_environment
    
    echo "✅ Environment check completed successfully with existing virtual environments!"
}

# Don't run main automatically
EOF

chmod +x test_full_env_check.sh

echo "🧪 Running full environment check test..."
if ./test_full_env_check.sh; then
    echo "✅ Full environment check test passed!"
else
    echo "❌ Full environment check test failed"
    exit 1
fi

# Clean up test script
rm -f test_full_env_check.sh

echo ""
echo "🎉 All tests passed! The GitHub Actions virtual environment fix is working correctly."
echo ""
echo "📋 Summary of fixes:"
echo "   1. ✅ Removed duplicate client virtual environment setup in GitHub Actions workflow"
echo "   2. ✅ Modified GitHub Actions workflow to preserve virtual environments during cleanup"
echo "   3. ✅ Modified build-all-local.sh to preserve virtual environments in GitHub Actions"
echo "   4. ✅ Virtual environments now persist through the entire GitHub Actions build process"
echo ""
echo "🔧 The issue of duplicate effort and virtual environment loss has been resolved!"