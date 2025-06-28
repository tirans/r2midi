#!/bin/bash
set -euo pipefail

# Execute the make scripts executable script
echo "🔧 Making all build scripts executable..."

# Main build scripts
chmod +x build-all-local.sh
chmod +x build-server-local.sh  
chmod +x build-client-local.sh
chmod +x make-scripts-executable.sh
chmod +x test-simplified-build.sh

# GitHub Actions scripts
chmod +x .github/scripts/sign-notarize.sh 2>/dev/null || true

# Python scripts
chmod +x scripts/build-pkg-with-macos-builder.py 2>/dev/null || true

# Other utility scripts
chmod +x scripts/keychain-free-build.sh 2>/dev/null || true
chmod +x clean-environment.sh 2>/dev/null || true
chmod +x setup-virtual-environments.sh 2>/dev/null || true

echo "✅ All scripts are now executable"
echo "🚀 You can now run: ./test-simplified-build.sh"
