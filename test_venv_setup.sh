#!/bin/bash
# Test script to verify that build-all-local.sh automatically sets up virtual environments

set -euo pipefail

echo "🧪 Testing automatic virtual environment setup in build-all-local.sh"
echo "=================================================================="

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
echo "🚀 Testing build-all-local.sh with missing virtual environments..."
echo "   This should automatically run setup-virtual-environments.sh"
echo ""

# Run build-all-local.sh with --help to trigger environment check without full build
if ./build-all-local.sh --help > /dev/null 2>&1; then
    echo "❌ Test failed: build-all-local.sh --help should have failed due to missing virtual environments"
    exit 1
fi

echo "✅ Expected behavior: build-all-local.sh detected missing virtual environments"
echo ""

# Now test the actual environment check function by running just the environment check
echo "🔍 Testing environment check specifically..."

# Create a minimal test script that just runs the environment check
cat > test_env_check.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Source the build script to get access to its functions
source build-all-local.sh

# Override the main function to prevent full execution
main() {
    echo "Testing environment check only..."
    check_environment
    echo "Environment check completed successfully!"
}

# Don't run main automatically
EOF

chmod +x test_env_check.sh

echo "🧪 Running environment check test..."
if ./test_env_check.sh; then
    echo "✅ Environment check test passed!"
    
    # Verify that virtual environments were created
    if [ -d "venv_client" ] && [ -d "venv_server" ]; then
        echo "✅ Virtual environments were automatically created:"
        echo "  - venv_client: $(ls -la venv_client/bin/python 2>/dev/null && echo "✅" || echo "❌")"
        echo "  - venv_server: $(ls -la venv_server/bin/python 2>/dev/null && echo "✅" || echo "❌")"
    else
        echo "❌ Virtual environments were not created as expected"
        exit 1
    fi
else
    echo "❌ Environment check test failed"
    exit 1
fi

# Clean up test script
rm -f test_env_check.sh

echo ""
echo "🎉 All tests passed! The automatic virtual environment setup is working correctly."
echo "   build-all-local.sh will now automatically run setup-virtual-environments.sh"
echo "   when virtual environments are missing."