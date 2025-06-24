#!/bin/bash
set -euo pipefail
# Package Linux applications for distribution
# Usage: package-linux-apps.sh <version> <build_type>

VERSION="${1:-1.0.0}"
BUILD_TYPE="${2:-production}"
echo "📦 Packaging Linux applications (version: $VERSION, type: $BUILD_TYPE)..."

# Create artifacts directory
mkdir -p artifacts

# Function to package client application
package_client_app() {
    echo "📱 Packaging R2MIDI Client for Linux..."
    
    if [ ! -d "r2midi_client/dist" ]; then
        echo "❌ Error: Client build outputs not found"
        return 1
    fi
    
    cd r2midi_client/dist
    
    # Find the built application
    local app_dir=$(find . -name "*.AppDir" -type d | head -1)
    local appimage=$(find . -name "*.AppImage" -type f | head -1)
    local tarball=$(find . -name "*.tar.gz" -type f | head -1)
    
    if [ -n "$appimage" ]; then
        echo "✅ Found AppImage: $appimage"
        cp "$appimage" "../../artifacts/R2MIDI-Client-${VERSION}-linux.AppImage"
        chmod +x "../../artifacts/R2MIDI-Client-${VERSION}-linux.AppImage"
    elif [ -n "$app_dir" ]; then
        echo "✅ Found AppDir: $app_dir"
        # Create tarball from AppDir
        tar -czf "../../artifacts/R2MIDI-Client-${VERSION}-linux.tar.gz" "$app_dir"
    elif [ -n "$tarball" ]; then
        echo "✅ Found tarball: $tarball"
        cp "$tarball" "../../artifacts/R2MIDI-Client-${VERSION}-linux.tar.gz"
    else
        echo "❌ No suitable client package found"
        cd ../..
        return 1
    fi
    
    cd ../..
    echo "✅ Client packaging complete"
}

# Function to package server application
package_server_app() {
    echo "🖥️ Packaging R2MIDI Server for Linux..."
    
    local server_dist_dir=""
    if [ -d "dist" ]; then
        server_dist_dir="dist"
    elif [ -d "server/dist" ]; then
        server_dist_dir="server/dist"
    else
        echo "❌ Error: Server build outputs not found"
        return 1
    fi
    
    cd "$server_dist_dir"
    
    # Find the built application
    local app_dir=$(find . -name "*.AppDir" -type d | head -1)
    local appimage=$(find . -name "*.AppImage" -type f | head -1)
    local tarball=$(find . -name "*.tar.gz" -type f | head -1)
    
    if [ -n "$appimage" ]; then
        echo "✅ Found AppImage: $appimage"
        if [ "$server_dist_dir" = "server/dist" ]; then
            cp "$appimage" "../../artifacts/R2MIDI-Server-${VERSION}-linux.AppImage"
            chmod +x "../../artifacts/R2MIDI-Server-${VERSION}-linux.AppImage"
        else
            cp "$appimage" "../artifacts/R2MIDI-Server-${VERSION}-linux.AppImage"
            chmod +x "../artifacts/R2MIDI-Server-${VERSION}-linux.AppImage"
        fi
    elif [ -n "$app_dir" ]; then
        echo "✅ Found AppDir: $app_dir"
        # Create tarball from AppDir
        if [ "$server_dist_dir" = "server/dist" ]; then
            tar -czf "../../artifacts/R2MIDI-Server-${VERSION}-linux.tar.gz" "$app_dir"
        else
            tar -czf "../artifacts/R2MIDI-Server-${VERSION}-linux.tar.gz" "$app_dir"
        fi
    elif [ -n "$tarball" ]; then
        echo "✅ Found tarball: $tarball"
        if [ "$server_dist_dir" = "server/dist" ]; then
            cp "$tarball" "../../artifacts/R2MIDI-Server-${VERSION}-linux.tar.gz"
        else
            cp "$tarball" "../artifacts/R2MIDI-Server-${VERSION}-linux.tar.gz"
        fi
    else
        echo "❌ No suitable server package found"
        cd - >/dev/null
        return 1
    fi
    
    cd - >/dev/null
    echo "✅ Server packaging complete"
}

# Function to create combined package
create_combined_package() {
    echo "📦 Creating combined Linux package..."
    
    # Create a directory for the combined package
    local combined_dir="artifacts/R2MIDI-${VERSION}-linux"
    mkdir -p "$combined_dir"
    
    # Copy individual packages
    if [ -f "artifacts/R2MIDI-Client-${VERSION}-linux.AppImage" ]; then
        cp "artifacts/R2MIDI-Client-${VERSION}-linux.AppImage" "$combined_dir/"
    elif [ -f "artifacts/R2MIDI-Client-${VERSION}-linux.tar.gz" ]; then
        cd "$combined_dir"
        tar -xzf "../R2MIDI-Client-${VERSION}-linux.tar.gz"
        cd - >/dev/null
    fi
    
    if [ -f "artifacts/R2MIDI-Server-${VERSION}-linux.AppImage" ]; then
        cp "artifacts/R2MIDI-Server-${VERSION}-linux.AppImage" "$combined_dir/"
    elif [ -f "artifacts/R2MIDI-Server-${VERSION}-linux.tar.gz" ]; then
        cd "$combined_dir"
        tar -xzf "../R2MIDI-Server-${VERSION}-linux.tar.gz"
        cd - >/dev/null
    fi
    
    # Create installation script
    cat > "$combined_dir/install.sh" << 'EOF'
#!/bin/bash
echo "🚀 Installing R2MIDI for Linux..."

# Make AppImages executable if they exist
if [ -f "R2MIDI-Client-*.AppImage" ]; then
    chmod +x R2MIDI-Client-*.AppImage
    echo "✅ Client AppImage is ready to run"
fi

if [ -f "R2MIDI-Server-*.AppImage" ]; then
    chmod +x R2MIDI-Server-*.AppImage
    echo "✅ Server AppImage is ready to run"
fi

echo "📋 Installation complete!"
echo "You can now run the applications directly from this directory."
EOF
    
    chmod +x "$combined_dir/install.sh"
    
    # Create README
    cat > "$combined_dir/README.md" << EOF
# R2MIDI Linux Distribution

This package contains the R2MIDI Client and Server applications for Linux.

## Installation

Run the installation script:
\`\`\`bash
./install.sh
\`\`\`

## Running the Applications

### Client
If you have an AppImage:
\`\`\`bash
./R2MIDI-Client-${VERSION}-linux.AppImage
\`\`\`

### Server
If you have an AppImage:
\`\`\`bash
./R2MIDI-Server-${VERSION}-linux.AppImage
\`\`\`

## System Requirements

- Linux x86_64
- GLIBC 2.17 or later
- Audio system (ALSA/PulseAudio)

## Support

For support and documentation, visit: https://github.com/tirans/r2midi
EOF
    
    # Create final tarball
    cd artifacts
    tar -czf "R2MIDI-${VERSION}-linux-complete.tar.gz" "R2MIDI-${VERSION}-linux"
    cd ..
    
    echo "✅ Combined package created: artifacts/R2MIDI-${VERSION}-linux-complete.tar.gz"
}

# Function to create package manifest
create_package_manifest() {
    echo "📋 Creating package manifest..."
    
    cat > artifacts/linux-package-manifest.txt << EOF
# Linux Package Manifest
Version: $VERSION
Build Type: $BUILD_TYPE
Platform: Linux
Build Date: $(date)

## Package Contents
EOF
    
    cd artifacts
    for file in *; do
        if [ -f "$file" ]; then
            local size=$(ls -lh "$file" | awk '{print $5}')
            local checksum=$(sha256sum "$file" | awk '{print $1}')
            echo "- $file ($size) - SHA256: $checksum" >> linux-package-manifest.txt
        fi
    done
    cd ..
    
    echo "✅ Package manifest created: artifacts/linux-package-manifest.txt"
}

# Main packaging process
main() {
    echo "🚀 Starting Linux packaging process..."
    
    # Package individual applications
    local packaging_success=true
    
    if package_client_app; then
        echo "✅ Client packaging successful"
    else
        echo "❌ Client packaging failed"
        packaging_success=false
    fi
    
    if package_server_app; then
        echo "✅ Server packaging successful"
    else
        echo "❌ Server packaging failed"
        packaging_success=false
    fi
    
    # Create combined package if both succeeded
    if [ "$packaging_success" = true ]; then
        create_combined_package
    else
        echo "⚠️ Skipping combined package due to individual packaging failures"
    fi
    
    # Create manifest
    create_package_manifest
    
    # List final artifacts
    echo "📦 Final Linux packages:"
    ls -la artifacts/
    
    if [ "$packaging_success" = true ]; then
        echo "🎉 Linux packaging completed successfully!"
        exit 0
    else
        echo "💥 Linux packaging completed with errors!"
        exit 1
    fi
}

# Run main function
main "$@"