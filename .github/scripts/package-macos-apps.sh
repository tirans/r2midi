#!/bin/bash
set -euo pipefail

# Package macOS applications into distribution-ready formats
# Usage: package-macos-apps.sh <version> <build_type>

VERSION="${1:-1.0.0}"
BUILD_TYPE="${2:-production}"

echo "🍎 Packaging macOS applications..."
echo "Version: $VERSION"
echo "Build Type: $BUILD_TYPE"

# Ensure artifacts directory exists
mkdir -p artifacts

# Function to organize and verify signed files
organize_signed_files() {
    echo "🔍 Organizing signed files from artifacts..."
    
    # The sign-and-notarize script should have already placed files in artifacts/
    # We just need to verify and possibly rename them
    
    if [ -d "artifacts" ]; then
        find artifacts/ -name "*.dmg" -o -name "*.pkg" | while read file; do
            if [ -f "$file" ]; then
                local filename=$(basename "$file")
                echo "📦 Found signed file: $filename"
                
                # Verify the file is properly signed and notarized
                if [[ "$filename" == *.dmg ]]; then
                    echo "🔍 Verifying DMG: $filename"
                    
                    # Check code signature
                    if codesign --verify --deep --strict "$file" 2>/dev/null; then
                        echo "  ✅ DMG signature valid"
                    else
                        echo "  ⚠️ DMG signature verification failed"
                    fi
                    
                    # Check Gatekeeper assessment
                    if spctl --assess --type install "$file" 2>/dev/null; then
                        echo "  ✅ DMG passes Gatekeeper assessment"
                    else
                        echo "  ⚠️ DMG fails Gatekeeper assessment"
                    fi
                    
                elif [[ "$filename" == *.pkg ]]; then
                    echo "🔍 Verifying PKG: $filename"
                    
                    # Check PKG signature
                    if pkgutil --check-signature "$file" 2>/dev/null | grep -q "signed"; then
                        echo "  ✅ PKG signature valid"
                    else
                        echo "  ⚠️ PKG signature verification failed"
                    fi
                    
                    # Check Gatekeeper assessment
                    if spctl --assess --type install "$file" 2>/dev/null; then
                        echo "  ✅ PKG passes Gatekeeper assessment"
                    else
                        echo "  ⚠️ PKG fails Gatekeeper assessment"
                    fi
                fi
                
                # Check notarization stapling
                if xcrun stapler validate "$file" 2>/dev/null; then
                    echo "  ✅ Notarization ticket stapled"
                else
                    echo "  ⚠️ No notarization ticket found"
                fi
            fi
        done
    fi
}

# Function to create a universal distribution package
create_universal_package() {
    echo "🌍 Creating universal distribution package..."
    
    local server_dmg=""
    local client_dmg=""
    local found_dmgs=()
    
    # Find individual DMG files
    if [ -d "artifacts" ]; then
        while IFS= read -r -d '' dmg; do
            found_dmgs+=("$dmg")
            if [[ "$(basename "$dmg")" == *"server"* ]] || [[ "$(basename "$dmg")" == *"Server"* ]]; then
                server_dmg="$dmg"
            elif [[ "$(basename "$dmg")" == *"client"* ]] || [[ "$(basename "$dmg")" == *"Client"* ]]; then
                client_dmg="$dmg"
            fi
        done < <(find artifacts/ -name "*.dmg" -print0)
    fi
    
    echo "Found ${#found_dmgs[@]} DMG files"
    [ -n "$server_dmg" ] && echo "Server DMG: $(basename "$server_dmg")"
    [ -n "$client_dmg" ] && echo "Client DMG: $(basename "$client_dmg")"
    
    # Create a distribution bundle if we have multiple apps
    if [ ${#found_dmgs[@]} -gt 1 ]; then
        local bundle_name="R2MIDI-Complete-${VERSION}-macOS"
        local bundle_dir="artifacts/${bundle_name}"
        
        echo "📦 Creating complete distribution bundle: $bundle_name"
        mkdir -p "$bundle_dir"
        
        # Copy all DMGs to the bundle
        for dmg in "${found_dmgs[@]}"; do
            cp "$dmg" "$bundle_dir/"
        done
        
        # Copy PKGs if they exist
        find artifacts/ -name "*.pkg" -exec cp {} "$bundle_dir/" \;
        
        # Create installation guide
        cat > "$bundle_dir/INSTALLATION_GUIDE.md" << EOF
# R2MIDI Installation Guide

Version: $VERSION
Build Type: $BUILD_TYPE
Platform: macOS (Signed & Notarized)

## What's Included

This package contains the complete R2MIDI suite:

EOF

        # List included files
        find "$bundle_dir" -name "*.dmg" -o -name "*.pkg" | while read file; do
            local filename=$(basename "$file")
            local size=$(du -h "$file" | cut -f1)
            echo "- **$filename** ($size)" >> "$bundle_dir/INSTALLATION_GUIDE.md"
            
            # Add description based on filename
            if [[ "$filename" == *"server"* ]] || [[ "$filename" == *"Server"* ]]; then
                echo "  - R2MIDI Server application (run this first)" >> "$bundle_dir/INSTALLATION_GUIDE.md"
            elif [[ "$filename" == *"client"* ]] || [[ "$filename" == *"Client"* ]]; then
                echo "  - R2MIDI Client application (connects to server)" >> "$bundle_dir/INSTALLATION_GUIDE.md"
            fi
        done

        cat >> "$bundle_dir/INSTALLATION_GUIDE.md" << EOF

## Installation Instructions

### Method 1: DMG Installation (Recommended)
1. Open each .dmg file by double-clicking
2. Drag the application to your Applications folder
3. Eject the disk image when done

### Method 2: PKG Installation (Automated)
1. Double-click the .pkg file
2. Follow the installer prompts
3. The application will be installed to /Applications

## Running R2MIDI

1. **Start the Server first**: Launch R2MIDI Server from Applications
2. **Start the Client**: Launch R2MIDI Client from Applications
3. The client will automatically connect to the local server

## System Requirements

- macOS 11.0 (Big Sur) or later
- Apple Silicon (M1/M2/M3) or Intel processor
- Administrator privileges for initial installation

## Security Information

- All applications are signed with Apple Developer ID
- All applications are notarized by Apple
- Safe to run with default macOS security settings
- No additional security warnings should appear

## Troubleshooting

### "App is damaged and can't be opened"
This usually means the download was corrupted. Try downloading again.

### "App can't be opened because it's from an unidentified developer"
This shouldn't happen with properly notarized apps. If it does:
1. Right-click the app and select "Open"
2. Click "Open" in the security dialog

### Connection Issues
1. Ensure both Server and Client are running
2. Check firewall settings allow R2MIDI connections
3. Restart both applications if needed

## Support

- GitHub: https://github.com/tirans/r2midi
- Issues: https://github.com/tirans/r2midi/issues
- Documentation: https://github.com/tirans/r2midi/wiki

---
Generated on $(date -u '+%Y-%m-%d %H:%M:%S UTC')
EOF

        # Create a ZIP archive of the complete bundle
        local zip_name="${bundle_name}.zip"
        echo "🗜️ Creating ZIP archive: $zip_name"
        (cd artifacts && zip -r "$zip_name" "$(basename "$bundle_dir")")
        
        echo "✅ Created universal package: artifacts/$zip_name"
    fi
}

# Function to create checksums for all packages
create_checksums() {
    echo "🔒 Creating checksums for all packages..."
    
    if [ -d "artifacts" ] && [ "$(ls -A artifacts/)" ]; then
        (cd artifacts && find . -name "*.dmg" -o -name "*.pkg" -o -name "*.zip" | while read file; do
            if [ -f "$file" ]; then
                echo "🔸 Creating checksum for $(basename "$file")..."
                shasum -a 256 "$file" >> CHECKSUMS.txt
            fi
        done)
        
        if [ -f "artifacts/CHECKSUMS.txt" ]; then
            echo "✅ Created checksums file: artifacts/CHECKSUMS.txt"
        fi
    fi
}

# Function to generate final package manifest
generate_manifest() {
    echo "📋 Generating package manifest..."
    
    cat > artifacts/PACKAGE_MANIFEST.txt << EOF
R2MIDI macOS Package Manifest
============================

Version: $VERSION
Build Type: $BUILD_TYPE
Platform: macOS (Signed & Notarized)
Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

Package Details:
- Code Signing: Apple Developer ID Application
- Installer Signing: Apple Developer ID Installer (PKG only)
- Notarization: Apple Notary Service with stapling
- Compatibility: macOS 11.0+ (Big Sur or later)
- Architecture: Universal (Apple Silicon + Intel)

Distribution Files:
EOF

    # List all distribution files with details
    if [ -d "artifacts" ]; then
        find artifacts/ -name "*.dmg" -o -name "*.pkg" -o -name "*.zip" | sort | while read file; do
            if [ -f "$file" ]; then
                local filename=$(basename "$file")
                local size=$(du -h "$file" | cut -f1)
                local modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$file")
                
                echo "📦 $filename ($size) - $modified" >> artifacts/PACKAGE_MANIFEST.txt
                
                # Add technical details
                if [[ "$filename" == *.dmg ]]; then
                    echo "   Type: Disk Image (drag-and-drop installer)" >> artifacts/PACKAGE_MANIFEST.txt
                    if codesign --verify --deep --strict "$file" 2>/dev/null; then
                        echo "   Status: Signed ✅" >> artifacts/PACKAGE_MANIFEST.txt
                    else
                        echo "   Status: Unsigned ❌" >> artifacts/PACKAGE_MANIFEST.txt
                    fi
                elif [[ "$filename" == *.pkg ]]; then
                    echo "   Type: Package Installer (automated installation)" >> artifacts/PACKAGE_MANIFEST.txt
                    if pkgutil --check-signature "$file" 2>/dev/null | grep -q "signed"; then
                        echo "   Status: Signed ✅" >> artifacts/PACKAGE_MANIFEST.txt
                    else
                        echo "   Status: Unsigned ❌" >> artifacts/PACKAGE_MANIFEST.txt
                    fi
                elif [[ "$filename" == *.zip ]]; then
                    echo "   Type: Archive (complete distribution bundle)" >> artifacts/PACKAGE_MANIFEST.txt
                    echo "   Status: Compressed bundle ✅" >> artifacts/PACKAGE_MANIFEST.txt
                fi
                
                # Add notarization status
                if xcrun stapler validate "$file" 2>/dev/null; then
                    echo "   Notarization: Stapled ✅" >> artifacts/PACKAGE_MANIFEST.txt
                elif [[ "$filename" == *.zip ]]; then
                    echo "   Notarization: N/A (archive)" >> artifacts/PACKAGE_MANIFEST.txt
                else
                    echo "   Notarization: Not stapled ❌" >> artifacts/PACKAGE_MANIFEST.txt
                fi
                
                echo "" >> artifacts/PACKAGE_MANIFEST.txt
            fi
        done
    fi

    # Add checksum information if available
    if [ -f "artifacts/CHECKSUMS.txt" ]; then
        echo "SHA256 Checksums:" >> artifacts/PACKAGE_MANIFEST.txt
        echo "=================" >> artifacts/PACKAGE_MANIFEST.txt
        cat artifacts/CHECKSUMS.txt >> artifacts/PACKAGE_MANIFEST.txt
    fi
    
    echo "✅ Package manifest created: artifacts/PACKAGE_MANIFEST.txt"
}

# Main packaging workflow
echo "🚀 Starting macOS packaging workflow..."

# Step 1: Organize and verify existing signed files
organize_signed_files

# Step 2: Create universal distribution package if applicable
create_universal_package

# Step 3: Create checksums for all packages
create_checksums

# Step 4: Generate final manifest
generate_manifest

# Final summary
echo ""
echo "✅ macOS packaging complete!"
echo ""

if [ -d "artifacts" ] && [ "$(ls -A artifacts/)" ]; then
    echo "📦 Created packages:"
    find artifacts/ -name "*.dmg" -o -name "*.pkg" -o -name "*.zip" | sort | while read file; do
        if [ -f "$file" ]; then
            local size=$(du -h "$file" | cut -f1)
            echo "  - $(basename "$file") ($size)"
        fi
    done
    
    echo ""
    echo "📋 Documentation files:"
    find artifacts/ -name "*.txt" -o -name "*.md" | sort | while read file; do
        if [ -f "$file" ]; then
            echo "  - $(basename "$file")"
        fi
    done
else
    echo "❌ No packages were created"
    exit 1
fi

echo ""
echo "📋 All files ready in artifacts/ directory"
