#!/bin/bash
set -euo pipefail

# Package Windows applications into distribution-ready formats
# Usage: package-windows-apps.sh <version> <build_type>

VERSION="${1:-1.0.0}"
BUILD_TYPE="${2:-production}"

echo "🪟 Packaging Windows applications..."
echo "Version: $VERSION"
echo "Build Type: $BUILD_TYPE"

# Ensure artifacts directory exists
mkdir -p artifacts

# Function to create a ZIP package from a directory
create_zip_package() {
    local source_dir="$1"
    local app_name="$2"
    local zip_name="R2MIDI-${app_name}-${VERSION}-Windows.zip"
    
    echo "📦 Creating ZIP package: $zip_name"
    
    if [ -d "$source_dir" ]; then
        # Create a temporary directory with proper structure
        local temp_dir=$(mktemp -d)
        local package_dir="$temp_dir/R2MIDI-${app_name}-${VERSION}"
        
        mkdir -p "$package_dir"
        cp -r "$source_dir"/* "$package_dir/"
        
        # Add README and license files
        if [ -f "README.md" ]; then
            cp README.md "$package_dir/"
        fi
        if [ -f "LICENSE" ]; then
            cp LICENSE "$package_dir/"
        fi
        
        # Create installation instructions
        cat > "$package_dir/INSTALL.txt" << EOF
R2MIDI ${app_name} Installation Instructions
============================================

Version: $VERSION
Platform: Windows
Package Type: Portable Application

Installation:
1. Extract this ZIP file to your desired location
2. Run the executable file to start the application
3. No additional installation required

System Requirements:
- Windows 10 or later (64-bit)
- No administrator privileges required for portable installation

Support:
- GitHub: https://github.com/tirans/r2midi
- Issues: https://github.com/tirans/r2midi/issues

Note: This is an unsigned application. Windows may show security warnings.
You can safely ignore these warnings for this open-source application.
EOF
        
        # Create the ZIP file - Use PowerShell on Windows
        if command -v powershell >/dev/null 2>&1; then
            echo "📦 Using PowerShell Compress-Archive..."
            powershell -Command "Compress-Archive -Path '$temp_dir/R2MIDI-${app_name}-${VERSION}' -DestinationPath '${zip_name}'"
        elif command -v zip >/dev/null 2>&1; then
            echo "📦 Using zip command..."
            (cd "$temp_dir" && zip -r "${zip_name}" "R2MIDI-${app_name}-${VERSION}")
            mv "$temp_dir/${zip_name}" ./
        else
            echo "⚠️ Warning: No zip utility found, creating tar.gz instead..."
            (cd "$temp_dir" && tar -czf "${zip_name%.zip}.tar.gz" "R2MIDI-${app_name}-${VERSION}")
            mv "$temp_dir/${zip_name%.zip}.tar.gz" ./
        fi
        
        # Move to artifacts directory if zip was created successfully
        if [ -f "${zip_name}" ]; then
            mv "${zip_name}" artifacts/
        elif [ -f "${zip_name%.zip}.tar.gz" ]; then
            mv "${zip_name%.zip}.tar.gz" artifacts/
        fi
        
        # Cleanup
        rm -rf "$temp_dir"
        
        echo "✅ Created package: artifacts/$zip_name"
        return 0
    else
        echo "❌ Source directory not found: $source_dir"
        return 1
    fi
}

# Function to find and package MSI files
package_msi_files() {
    echo "🔍 Looking for MSI installer packages..."
    
    find dist/ -name "*.msi" | while read msi_file; do
        if [ -f "$msi_file" ]; then
            local msi_name=$(basename "$msi_file")
            local new_name=$(echo "$msi_name" | sed "s/\.msi$/-${VERSION}.msi/")
            
            echo "📦 Processing MSI: $msi_name -> $new_name"
            cp "$msi_file" "artifacts/$new_name"
            
            echo "✅ Packaged MSI: artifacts/$new_name"
        fi
    done
}

# Process different application types
echo "🔍 Looking for built Windows applications..."

# Package Server application
if [ -d "dist/server" ]; then
    echo "📦 Packaging R2MIDI Server..."
    create_zip_package "dist/server" "Server"
else
    echo "⚠️ Server application not found in dist/server"
fi

# Package Client application  
if [ -d "dist/r2midi-client" ]; then
    echo "📦 Packaging R2MIDI Client..."
    create_zip_package "dist/r2midi-client" "Client"
else
    echo "⚠️ Client application not found in dist/r2midi-client"
fi

# Package any MSI files
package_msi_files

# Create a combined package for convenience
if [ -d "dist/server" ] && [ -d "dist/r2midi-client" ]; then
    echo "📦 Creating combined package..."
    
    local combined_zip="R2MIDI-Complete-${VERSION}-Windows.zip"
    local temp_dir=$(mktemp -d)
    local package_dir="$temp_dir/R2MIDI-Complete-${VERSION}"
    
    mkdir -p "$package_dir/Server"
    mkdir -p "$package_dir/Client"
    
    cp -r dist/server/* "$package_dir/Server/"
    cp -r dist/r2midi-client/* "$package_dir/Client/"
    
    # Add documentation
    if [ -f "README.md" ]; then
        cp README.md "$package_dir/"
    fi
    if [ -f "LICENSE" ]; then
        cp LICENSE "$package_dir/"
    fi
    
    # Create combined installation instructions
    cat > "$package_dir/INSTALL.txt" << EOF
R2MIDI Complete Package Installation Instructions
=================================================

Version: $VERSION
Platform: Windows
Package Type: Complete Portable Applications

This package contains both the R2MIDI Server and Client applications.

Installation:
1. Extract this ZIP file to your desired location
2. Run applications from their respective folders:
   - Server: Server/server.exe (or similar)
   - Client: Client/r2midi-client.exe (or similar)

Usage:
1. Start the Server application first
2. Then start the Client application
3. The Client will connect to the local Server

System Requirements:
- Windows 10 or later (64-bit)
- No administrator privileges required for portable installation

Support:
- GitHub: https://github.com/tirans/r2midi
- Issues: https://github.com/tirans/r2midi/issues

Note: These are unsigned applications. Windows may show security warnings.
You can safely ignore these warnings for this open-source application.
EOF
    
    # Create the combined ZIP
    if command -v powershell >/dev/null 2>&1; then
        echo "📦 Using PowerShell for combined package..."
        powershell -Command "Compress-Archive -Path '$temp_dir/R2MIDI-Complete-${VERSION}' -DestinationPath '$combined_zip'"
    elif command -v zip >/dev/null 2>&1; then
        echo "📦 Using zip for combined package..."
        (cd "$temp_dir" && zip -r "$combined_zip" "R2MIDI-Complete-${VERSION}")
        mv "$temp_dir/$combined_zip" ./
    else
        echo "⚠️ Creating tar.gz for combined package..."
        (cd "$temp_dir" && tar -czf "${combined_zip%.zip}.tar.gz" "R2MIDI-Complete-${VERSION}")
        mv "$temp_dir/${combined_zip%.zip}.tar.gz" ./
        combined_zip="${combined_zip%.zip}.tar.gz"
    fi
    
    # Move to artifacts directory
    if [ -f "$combined_zip" ]; then
        mv "$combined_zip" artifacts/
        echo "✅ Created combined package: artifacts/$combined_zip"
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
fi

# Generate package information
cat > artifacts/WINDOWS_PACKAGES.txt << EOF
Windows Package Information
===========================

Version: $VERSION
Build Type: $BUILD_TYPE
Platform: Windows (unsigned)
Package Tool: Custom packaging script
Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

Package Types:
- ZIP: Portable applications (no installation required)
- MSI: Windows installer packages (if available)

Created Packages:
EOF

# List all created packages
if [ -d "artifacts" ] && [ "$(ls -A artifacts/)" ]; then
    find artifacts/ -name "*.zip" -o -name "*.msi" | sort | while read file; do
        if [ -f "$file" ]; then
            size=$(du -h "$file" | cut -f1)
            echo "  - $(basename "$file") ($size)" >> artifacts/WINDOWS_PACKAGES.txt
        fi
    done
else
    echo "  - No packages generated" >> artifacts/WINDOWS_PACKAGES.txt
fi

echo ""
echo "✅ Windows packaging complete!"
echo "📋 Package summary:"
cat artifacts/WINDOWS_PACKAGES.txt