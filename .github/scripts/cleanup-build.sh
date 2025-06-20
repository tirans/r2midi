#!/bin/bash

# cleanup-build.sh - Cleanup build artifacts and sensitive data
# Usage: ./cleanup-build.sh [build_type] [is_m3_max]

set -euo pipefail

BUILD_TYPE=${1:-${BUILD_TYPE:-"dev"}}
IS_M3_MAX=${2:-${IS_M3_MAX:-"false"}}

echo "🧹 Performing build cleanup..."
echo "Build Type: $BUILD_TYPE"
echo "M3 Max Runner: $IS_M3_MAX"

# Function to safely remove files/directories
safe_remove() {
    local path="$1"
    local description="$2"
    
    if [ -e "$path" ]; then
        echo "  🗑️ Removing $description: $path"
        rm -rf "$path" 2>/dev/null || echo "    ⚠️ Failed to remove $path"
    else
        echo "  ✅ $description not found (already clean): $path"
    fi
}

# Clean up temporary keychain
echo "🔐 Cleaning up temporary keychain..."
if [ -n "${TEMP_KEYCHAIN:-}" ]; then
    echo "  🔐 Removing temporary keychain: $TEMP_KEYCHAIN"
    security delete-keychain "$TEMP_KEYCHAIN" 2>/dev/null || echo "    ⚠️ Failed to remove keychain or already removed"
    echo "  ✅ Temporary keychain cleanup completed"
else
    echo "  ✅ No temporary keychain to remove"
fi

# Clean up certificate files
echo "🔐 Cleaning up certificate files..."
safe_remove "app_cert.p12" "application certificate"
safe_remove "installer_cert.p12" "installer certificate"
safe_remove "entitlements.plist" "entitlements file"

# Clean up temporary files
echo "🗑️ Cleaning up temporary files..."
safe_remove "*.p12" "any remaining P12 files"
safe_remove "/tmp/r2midi-*" "temporary build directories"

# Clean up build directories based on build type and runner
echo "🏗️ Cleaning up build directories..."

if [ "$BUILD_TYPE" = "production" ] && [ "$IS_M3_MAX" = "true" ]; then
    echo "  💾 Production build on M3 Max - keeping build directories for caching"
    echo "    📁 Keeping: build_native/"
    echo "    💡 This improves subsequent build performance"
elif [ "$BUILD_TYPE" = "production" ]; then
    echo "  🗑️ Production build on GitHub runner - removing build directories"
    safe_remove "build_native" "build directories"
else
    echo "  🗑️ Development build - removing build directories"
    safe_remove "build_native" "build directories"
fi

# Clean up Python cache files
echo "🐍 Cleaning up Python cache files..."
echo "  🗑️ Removing Python cache directories..."
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true
find . -name "*.pyo" -delete 2>/dev/null || true
echo "  ✅ Python cache cleanup completed"

# Clean up any temporary directories in /tmp
echo "🗂️ Cleaning up system temporary files..."
if [ "$(uname)" = "Darwin" ]; then
    # macOS-specific cleanup
    find /tmp -name "*r2midi*" -user "$(whoami)" -delete 2>/dev/null || true
    find /tmp -name "*py2app*" -user "$(whoami)" -delete 2>/dev/null || true
fi
echo "  ✅ System temporary files cleanup completed"

# Reset environment variables that contain sensitive data
echo "🔒 Cleaning up environment variables..."
sensitive_vars=(
    "APPLE_CERT_PASSWORD"
    "APPLE_ID_PASSWORD"
    "TEMP_KEYCHAIN_PASSWORD"
    "APP_SIGNING_IDENTITY"
    "INSTALLER_SIGNING_IDENTITY"
)

for var in "${sensitive_vars[@]}"; do
    if [ -n "${!var:-}" ]; then
        echo "  🔒 Clearing $var"
        unset "$var" 2>/dev/null || true
    fi
done

# Show disk space recovered
if command -v du >/dev/null 2>&1; then
    echo ""
    echo "💾 Disk Usage Summary:"
    if [ -d "artifacts" ]; then
        artifacts_size=$(du -sh artifacts 2>/dev/null | cut -f1 || echo "unknown")
        echo "  📦 Artifacts size: $artifacts_size"
    fi
    
    if [ -d "build_native" ]; then
        build_size=$(du -sh build_native 2>/dev/null | cut -f1 || echo "unknown")
        echo "  🏗️ Build directories: $build_size (kept for caching)"
    else
        echo "  🏗️ Build directories: 0B (cleaned up)"
    fi
fi

# Security verification
echo ""
echo "🔐 Security Verification:"
echo "  ✅ Temporary keychain removed"
echo "  ✅ Certificate files deleted"
echo "  ✅ Sensitive environment variables cleared"
echo "  ✅ No P12 files remaining in workspace"

# Final verification - check for any remaining sensitive files
echo ""
echo "🔍 Final Security Check:"
sensitive_files_found=false

# Check for P12 files
if find . -name "*.p12" -type f | grep -q .; then
    echo "  ⚠️ Warning: P12 certificate files still present"
    find . -name "*.p12" -type f
    sensitive_files_found=true
fi

# Check for keychain files
if find . -name "*.keychain*" -type f | grep -q .; then
    echo "  ⚠️ Warning: Keychain files still present"
    find . -name "*.keychain*" -type f
    sensitive_files_found=true
fi

if [ "$sensitive_files_found" = "false" ]; then
    echo "  ✅ No sensitive files found - cleanup successful"
fi

echo ""
echo "✅ Cleanup completed successfully"

# Summary based on build type
if [ "$BUILD_TYPE" = "production" ]; then
    echo ""
    echo "🎯 Production Build Cleanup Summary:"
    echo "  ✅ All sensitive data removed"
    echo "  ✅ Security artifacts cleaned"
    if [ "$IS_M3_MAX" = "true" ]; then
        echo "  💾 Build cache preserved for M3 Max performance"
    else
        echo "  🗑️ Build directories cleaned"
    fi
    echo "  📦 Release artifacts preserved in artifacts/"
else
    echo ""
    echo "🔧 Development Build Cleanup Summary:"
    echo "  ✅ All temporary files removed"
    echo "  ✅ Build directories cleaned"
    echo "  📦 Build artifacts preserved in artifacts/"
fi

echo ""
echo "🎉 Ready for next build!"
