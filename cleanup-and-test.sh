#!/bin/bash
# cleanup-and-test.sh - Clean up signing scripts and test the build system

set -euo pipefail

echo "🚀 R2MIDI Signing System Cleanup and Test"
echo "========================================="
echo ""

# Change to project directory
PROJECT_ROOT="/Users/tirane/Desktop/r2midi"
cd "$PROJECT_ROOT"

# Step 1: Run cleanup
echo "📋 Step 1: Running cleanup script..."
echo "-----------------------------------"

# Make cleanup script executable
chmod +x cleanup-signing-scripts.sh 2>/dev/null || true

# Create the cleanup script if it doesn't exist
if [ ! -f "cleanup-signing-scripts.sh" ]; then
    echo "Creating cleanup script..."
    cat > cleanup-signing-scripts.sh << 'CLEANUP_EOF'
#!/bin/bash
# cleanup-signing-scripts.sh - Clean up duplicate and unnecessary signing scripts

set -euo pipefail

echo "🧹 R2MIDI Signing Scripts Cleanup"
echo "================================="

# Function to safely remove files
remove_file() {
    local file="$1"
    if [ -f "$file" ]; then
        echo "  ❌ Removing: $file"
        rm -f "$file"
    else
        echo "  ⚠️  Not found: $file"
    fi
}

echo ""
echo "📋 Removing duplicate scripts..."

# Remove duplicate certificate setup script
remove_file "setup-certificates-enhanced.sh"

# Remove simple helper script
remove_file "setup-enhanced-signing.sh"

echo ""
echo "📋 Removing backup files..."

# Find and remove all backup files
find . -name "*.backup" -type f | while read backup_file; do
    remove_file "$backup_file"
done

# Remove specific backup files mentioned
remove_file "sign-and-notarize-macos-enhanced.sh.backup"
remove_file "build-and-sign-local.sh.backup"
remove_file "build-all-local-original.sh.backup"

echo ""
echo "📋 Making scripts executable..."

# Make all necessary scripts executable
chmod +x build-all-local.sh 2>/dev/null && echo "  ✅ build-all-local.sh"
chmod +x build-server-local.sh 2>/dev/null && echo "  ✅ build-server-local.sh"
chmod +x build-client-local.sh 2>/dev/null && echo "  ✅ build-client-local.sh"
chmod +x setup-local-certificates.sh 2>/dev/null && echo "  ✅ setup-local-certificates.sh"

# Make GitHub scripts executable
if [ -d ".github/scripts" ]; then
    find .github/scripts -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null
    echo "  ✅ Made all .github/scripts/*.sh executable"
fi

echo ""
echo "✅ Cleanup completed!"
CLEANUP_EOF
    chmod +x cleanup-signing-scripts.sh
fi

# Run cleanup
./cleanup-signing-scripts.sh

echo ""
echo "📋 Step 2: Verifying environment..."
echo "-----------------------------------"

# Check certificates
if [ -f "setup-local-certificates.sh" ]; then
    echo "Running certificate verification..."
    ./setup-local-certificates.sh --verify-only || {
        echo "❌ Certificate verification failed"
        echo "💡 Run: ./setup-local-certificates.sh"
        exit 1
    }
else
    echo "❌ setup-local-certificates.sh not found"
    exit 1
fi

echo ""
echo "📋 Step 3: Checking build prerequisites..."
echo "------------------------------------------"

# Check virtual environments
echo -n "Checking venv_server... "
if [ -d "venv_server" ]; then
    echo "✅"
else
    echo "❌"
    echo "💡 Run: ./setup-virtual-environments.sh"
fi

echo -n "Checking venv_client... "
if [ -d "venv_client" ]; then
    echo "✅"
else
    echo "❌"
    echo "💡 Run: ./setup-virtual-environments.sh"
fi

# Check for existing artifacts
echo ""
echo "📋 Step 4: Existing artifacts..."
echo "---------------------------------"

if [ -d "artifacts" ]; then
    echo "Found in artifacts/:"
    find artifacts -name "*.pkg" -o -name "*.dmg" | sort | while read artifact; do
        if [ -f "$artifact" ]; then
            local size=$(du -sh "$artifact" 2>/dev/null | cut -f1 || echo "unknown")
            echo "  📦 $(basename "$artifact") ($size)"
        fi
    done
else
    echo "No artifacts directory found"
fi

echo ""
echo "📋 Step 5: Test build commands..."
echo "----------------------------------"

echo ""
echo "Ready to test the build system!"
echo ""
echo "🔧 Test commands to run:"
echo ""
echo "1. Setup certificates (if not done):"
echo "   ./setup-local-certificates.sh"
echo ""
echo "2. Test build with new version:"
echo "   ./build-all-local.sh --version 0.1.202 --clean"
echo ""
echo "3. Quick development build:"
echo "   ./build-all-local.sh --version 0.1.202 --dev --no-notarize"
echo ""
echo "4. Check the results:"
echo "   ls -la artifacts/*0.1.202*"
echo "   cat artifacts/BUILD_REPORT_0.1.202.md"
echo ""
echo "📋 Verification commands:"
echo "   pkgutil --check-signature artifacts/*.pkg"
echo "   codesign --verify --deep \"build_server/dist/R2MIDI Server.app\""
echo ""

# Create a test script
cat > test-build.sh << 'TEST_EOF'
#!/bin/bash
# Quick test of the build system

VERSION="0.1.202"
echo "🧪 Testing R2MIDI build system with version $VERSION"
echo ""

# Source environment if available
if [ -f ".local_build_env" ]; then
    echo "📋 Sourcing build environment..."
    source .local_build_env
fi

# Run a test build
echo "🏗️ Running test build..."
echo "Command: ./build-all-local.sh --version $VERSION --dev --no-notarize"
echo ""

if ./build-all-local.sh --version $VERSION --dev --no-notarize; then
    echo ""
    echo "✅ Test build completed successfully!"
    echo ""
    echo "📦 Generated artifacts:"
    find artifacts -name "*$VERSION*" -type f | while read artifact; do
        echo "  ✅ $(basename "$artifact")"
    done
else
    echo ""
    echo "❌ Test build failed"
    exit 1
fi
TEST_EOF

chmod +x test-build.sh

echo "✅ Setup complete!"
echo ""
echo "💡 A test script has been created: ./test-build.sh"
echo "   Run it to test the build system with version 0.1.202"
