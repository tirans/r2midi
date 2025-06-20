#!/bin/bash

echo "Making all GitHub scripts executable..."

# List of scripts to make executable
scripts=(
    "configure-build.sh"
    "setup-python-environment.sh"
    "install-dependencies.sh"
    "setup-apple-certificates.sh"
    "build-server-app.sh"
    "build-client-app.sh"
    "sign-apps.sh"
    "create-pkg-installers.sh"
    "create-dmg-installers.sh"
    "notarize-packages.sh"
    "create-build-report.sh"
    "cleanup-build.sh"
    "make-scripts-executable.sh"
)

for script in "${scripts[@]}"; do
    script_path="/Users/tirane/Desktop/r2midi/.github/scripts/$script"
    if [ -f "$script_path" ]; then
        chmod +x "$script_path"
        echo "✅ Made executable: $script"
    else
        echo "❌ Not found: $script"
    fi
done

echo "Done!"
