#!/bin/bash
set -euo pipefail
# Package Windows applications for distribution
# Usage: package-windows-apps.sh <version> <build_type>

VERSION="${1:-1.0.0}"
BUILD_TYPE="${2:-production}"
echo "📦 Packaging Windows applications (version: $VERSION, type: $BUILD_TYPE)..."

# Create artifacts directory
mkdir -p artifacts

# Function to package client application
package_client_app() {
    echo "📱 Packaging R2MIDI Client for Windows..."
    
    if [ ! -d "r2midi_client/dist" ]; then
        echo "❌ Error: Client build outputs not found"
        return 1
    fi
    
    cd r2midi_client/dist
    
    # Find the built application
    local msi_file=$(find . -name "*.msi" -type f | head -1)
    local exe_file=$(find . -name "*.exe" -type f | head -1)
    local zip_file=$(find . -name "*.zip" -type f | head -1)
    local app_dir=$(find . -name "*.app" -type d | head -1)
    
    if [ -n "$msi_file" ]; then
        echo "✅ Found MSI installer: $msi_file"
        cp "$msi_file" "../../artifacts/R2MIDI-Client-${VERSION}-windows.msi"
    elif [ -n "$exe_file" ]; then
        echo "✅ Found EXE installer: $exe_file"
        cp "$exe_file" "../../artifacts/R2MIDI-Client-${VERSION}-windows.exe"
    elif [ -n "$zip_file" ]; then
        echo "✅ Found ZIP package: $zip_file"
        cp "$zip_file" "../../artifacts/R2MIDI-Client-${VERSION}-windows.zip"
    elif [ -n "$app_dir" ]; then
        echo "✅ Found app directory: $app_dir"
        # Create ZIP from app directory
        powershell -Command "Compress-Archive -Path '$app_dir' -DestinationPath '../../artifacts/R2MIDI-Client-${VERSION}-windows.zip'" 2>/dev/null || \
        zip -r "../../artifacts/R2MIDI-Client-${VERSION}-windows.zip" "$app_dir"
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
    echo "🖥️ Packaging R2MIDI Server for Windows..."
    
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
    local msi_file=$(find . -name "*.msi" -type f | head -1)
    local exe_file=$(find . -name "*.exe" -type f | head -1)
    local zip_file=$(find . -name "*.zip" -type f | head -1)
    local app_dir=$(find . -name "*.app" -type d | head -1)
    
    if [ -n "$msi_file" ]; then
        echo "✅ Found MSI installer: $msi_file"
        if [ "$server_dist_dir" = "server/dist" ]; then
            cp "$msi_file" "../../artifacts/R2MIDI-Server-${VERSION}-windows.msi"
        else
            cp "$msi_file" "../artifacts/R2MIDI-Server-${VERSION}-windows.msi"
        fi
    elif [ -n "$exe_file" ]; then
        echo "✅ Found EXE installer: $exe_file"
        if [ "$server_dist_dir" = "server/dist" ]; then
            cp "$exe_file" "../../artifacts/R2MIDI-Server-${VERSION}-windows.exe"
        else
            cp "$exe_file" "../artifacts/R2MIDI-Server-${VERSION}-windows.exe"
        fi
    elif [ -n "$zip_file" ]; then
        echo "✅ Found ZIP package: $zip_file"
        if [ "$server_dist_dir" = "server/dist" ]; then
            cp "$zip_file" "../../artifacts/R2MIDI-Server-${VERSION}-windows.zip"
        else
            cp "$zip_file" "../artifacts/R2MIDI-Server-${VERSION}-windows.zip"
        fi
    elif [ -n "$app_dir" ]; then
        echo "✅ Found app directory: $app_dir"
        # Create ZIP from app directory
        if [ "$server_dist_dir" = "server/dist" ]; then
            powershell -Command "Compress-Archive -Path '$app_dir' -DestinationPath '../../artifacts/R2MIDI-Server-${VERSION}-windows.zip'" 2>/dev/null || \
            zip -r "../../artifacts/R2MIDI-Server-${VERSION}-windows.zip" "$app_dir"
        else
            powershell -Command "Compress-Archive -Path '$app_dir' -DestinationPath '../artifacts/R2MIDI-Server-${VERSION}-windows.zip'" 2>/dev/null || \
            zip -r "../artifacts/R2MIDI-Server-${VERSION}-windows.zip" "$app_dir"
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
    echo "📦 Creating combined Windows package..."
    
    # Create a directory for the combined package
    local combined_dir="artifacts/R2MIDI-${VERSION}-windows"
    mkdir -p "$combined_dir"
    
    # Copy individual packages
    for file in artifacts/R2MIDI-Client-${VERSION}-windows.*; do
        if [ -f "$file" ]; then
            cp "$file" "$combined_dir/"
        fi
    done
    
    for file in artifacts/R2MIDI-Server-${VERSION}-windows.*; do
        if [ -f "$file" ]; then
            cp "$file" "$combined_dir/"
        fi
    done
    
    # Create installation script (batch file)
    cat > "$combined_dir/install.bat" << 'EOF'
@echo off
echo Installing R2MIDI for Windows...

REM Check for MSI installers and run them
if exist "R2MIDI-Client-*-windows.msi" (
    echo Installing R2MIDI Client...
    for %%f in (R2MIDI-Client-*-windows.msi) do (
        msiexec /i "%%f" /quiet
    )
)

if exist "R2MIDI-Server-*-windows.msi" (
    echo Installing R2MIDI Server...
    for %%f in (R2MIDI-Server-*-windows.msi) do (
        msiexec /i "%%f" /quiet
    )
)

REM Check for EXE installers and run them
if exist "R2MIDI-Client-*-windows.exe" (
    echo Installing R2MIDI Client...
    for %%f in (R2MIDI-Client-*-windows.exe) do (
        "%%f" /S
    )
)

if exist "R2MIDI-Server-*-windows.exe" (
    echo Installing R2MIDI Server...
    for %%f in (R2MIDI-Server-*-windows.exe) do (
        "%%f" /S
    )
)

echo Installation complete!
pause
EOF
    
    # Create PowerShell installation script
    cat > "$combined_dir/install.ps1" << 'EOF'
Write-Host "Installing R2MIDI for Windows..." -ForegroundColor Green

# Install MSI packages
Get-ChildItem -Name "R2MIDI-Client-*-windows.msi" | ForEach-Object {
    Write-Host "Installing R2MIDI Client..." -ForegroundColor Yellow
    Start-Process msiexec -ArgumentList "/i", $_, "/quiet" -Wait
}

Get-ChildItem -Name "R2MIDI-Server-*-windows.msi" | ForEach-Object {
    Write-Host "Installing R2MIDI Server..." -ForegroundColor Yellow
    Start-Process msiexec -ArgumentList "/i", $_, "/quiet" -Wait
}

# Install EXE packages
Get-ChildItem -Name "R2MIDI-Client-*-windows.exe" | ForEach-Object {
    Write-Host "Installing R2MIDI Client..." -ForegroundColor Yellow
    Start-Process $_ -ArgumentList "/S" -Wait
}

Get-ChildItem -Name "R2MIDI-Server-*-windows.exe" | ForEach-Object {
    Write-Host "Installing R2MIDI Server..." -ForegroundColor Yellow
    Start-Process $_ -ArgumentList "/S" -Wait
}

Write-Host "Installation complete!" -ForegroundColor Green
Read-Host "Press Enter to continue..."
EOF
    
    # Create README
    cat > "$combined_dir/README.md" << EOF
# R2MIDI Windows Distribution

This package contains the R2MIDI Client and Server applications for Windows.

## Installation

### Option 1: Automatic Installation
Run the installation script as Administrator:
\`\`\`batch
install.bat
\`\`\`

Or using PowerShell:
\`\`\`powershell
.\install.ps1
\`\`\`

### Option 2: Manual Installation
1. Install the Client: Double-click \`R2MIDI-Client-${VERSION}-windows.msi\` or \`R2MIDI-Client-${VERSION}-windows.exe\`
2. Install the Server: Double-click \`R2MIDI-Server-${VERSION}-windows.msi\` or \`R2MIDI-Server-${VERSION}-windows.exe\`

### Option 3: Portable Installation
If you have ZIP files, extract them to your desired location and run the applications directly.

## System Requirements

- Windows 10 or later (64-bit)
- .NET Framework 4.7.2 or later
- Audio system with MIDI support

## Support

For support and documentation, visit: https://github.com/tirans/r2midi
EOF
    
    # Create final ZIP package
    cd artifacts
    if command -v powershell >/dev/null 2>&1; then
        powershell -Command "Compress-Archive -Path 'R2MIDI-${VERSION}-windows' -DestinationPath 'R2MIDI-${VERSION}-windows-complete.zip'" 2>/dev/null
    else
        zip -r "R2MIDI-${VERSION}-windows-complete.zip" "R2MIDI-${VERSION}-windows"
    fi
    cd ..
    
    echo "✅ Combined package created: artifacts/R2MIDI-${VERSION}-windows-complete.zip"
}

# Function to create package manifest
create_package_manifest() {
    echo "📋 Creating package manifest..."
    
    cat > artifacts/windows-package-manifest.txt << EOF
# Windows Package Manifest
Version: $VERSION
Build Type: $BUILD_TYPE
Platform: Windows
Build Date: $(date)

## Package Contents
EOF
    
    cd artifacts
    for file in *; do
        if [ -f "$file" ]; then
            local size=$(ls -lh "$file" | awk '{print $5}')
            if command -v sha256sum >/dev/null 2>&1; then
                local checksum=$(sha256sum "$file" | awk '{print $1}')
                echo "- $file ($size) - SHA256: $checksum" >> windows-package-manifest.txt
            else
                echo "- $file ($size)" >> windows-package-manifest.txt
            fi
        fi
    done
    cd ..
    
    echo "✅ Package manifest created: artifacts/windows-package-manifest.txt"
}

# Main packaging process
main() {
    echo "🚀 Starting Windows packaging process..."
    
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
    echo "📦 Final Windows packages:"
    ls -la artifacts/
    
    if [ "$packaging_success" = true ]; then
        echo "🎉 Windows packaging completed successfully!"
        exit 0
    else
        echo "💥 Windows packaging completed with errors!"
        exit 1
    fi
}

# Run main function
main "$@"