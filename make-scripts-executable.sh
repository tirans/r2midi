#!/bin/bash

# make-scripts-executable.sh - Make all build scripts executable

cd "$(dirname "${BASH_SOURCE[0]}")"

echo "Making scripts executable..."

# Make scripts executable
chmod +x scripts/common-certificate-setup.sh
chmod +x build-client-local.sh
chmod +x build-server-local.sh
chmod +x test-certificate-setup.sh

echo "✅ All scripts are now executable"

# List the scripts with their permissions
echo ""
echo "Script permissions:"
ls -la scripts/common-certificate-setup.sh
ls -la build-client-local.sh
ls -la build-server-local.sh
ls -la test-certificate-setup.sh
