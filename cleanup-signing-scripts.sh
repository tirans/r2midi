#!/bin/bash
# cleanup-signing-scripts.sh - Clean up duplicate and unnecessary signing scripts

set -euo pipefail

echo "🧹 R2MIDI Signing Scripts Cleanup"
echo "================================="

# Change to project directory
cd /Users/tirane/Desktop/r2midi

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

# Function to safely remove directories
remove_dir() {
    local dir="$1"
    if [ -d "$dir" ]; then
        echo "  ❌ Removing directory: $dir"
        rm -rf "$dir"
    else
        echo "  ⚠️  Directory not found: $dir"
    fi
}

echo ""
echo "📋 Step 1: Removing duplicate scripts..."
echo "----------------------------------------"

# Remove duplicate certificate setup script
remove_file "setup-certificates-enhanced.sh"

# Remove simple helper script (functionality can be in main script)
remove_file "setup-enhanced-signing.sh"

echo ""
echo "📋 Step 2: Removing backup files..."
echo "-----------------------------------"

# Find and remove all backup files
find . -name "*.backup" -type f | while read backup_file; do
    remove_file "$backup_file"
done

# Remove specific backup files mentioned
remove_file "sign-and-notarize-macos-enhanced.sh.backup"
remove_file "build-and-sign-local.sh.backup"
remove_file "build-all-local-original.sh.backup"

echo ""
echo "📋 Step 3: Cleaning up build artifacts..."
echo "-----------------------------------------"

# Remove .bak files
find . -name "*.bak" -type f | while read bak_file; do
    remove_file "$bak_file"
done

echo ""
echo "📋 Step 4: Making scripts executable..."
echo "---------------------------------------"

# Make all necessary scripts executable
chmod +x build-all-local.sh 2>/dev/null && echo "  ✅ build-all-local.sh"
chmod +x build-server-local.sh 2>/dev/null && echo "  ✅ build-server-local.sh"
chmod +x build-client-local.sh 2>/dev/null && echo "  ✅ build-client-local.sh"
chmod +x setup-local-certificates.sh 2>/dev/null && echo "  ✅ setup-local-certificates.sh"
chmod +x setup-virtual-environments.sh 2>/dev/null && echo "  ✅ setup-virtual-environments.sh"
chmod +x cleanup-and-test.sh 2>/dev/null && echo "  ✅ cleanup-and-test.sh"

# Make GitHub scripts executable
if [ -d ".github/scripts" ]; then
    echo ""
    echo "  Making .github/scripts executable:"
    find .github/scripts -name "*.sh" -type f | while read script; do
        chmod +x "$script" 2>/dev/null && echo "    ✅ $(basename "$script")"
    done
fi

echo ""
echo "📋 Step 5: Verifying final structure..."
echo "---------------------------------------"

echo ""
echo "Main build scripts:"
[ -f "build-all-local.sh" ] && echo "  ✅ build-all-local.sh"
[ -f "build-server-local.sh" ] && echo "  ✅ build-server-local.sh"
[ -f "build-client-local.sh" ] && echo "  ✅ build-client-local.sh"
[ -f "setup-local-certificates.sh" ] && echo "  ✅ setup-local-certificates.sh"

echo ""
echo "GitHub Actions scripts:"
if [ -d ".github/scripts" ]; then
    ls -1 .github/scripts/*.sh 2>/dev/null | head -10 | while read script; do
        echo "  ✅ $(basename "$script")"
    done
fi

echo ""
echo "✅ Cleanup completed!"
echo ""
echo "📋 Summary:"
echo "  - Removed duplicate scripts"
echo "  - Cleaned up backup files"
echo "  - Made all scripts executable"
echo ""
echo "💡 Next steps:"
echo "  1. Run: ./cleanup-and-test.sh"
echo "  2. Test build: ./build-all-local.sh --version 0.1.202 --clean"
echo "  3. Check results: ls -la artifacts/*0.1.202*"
