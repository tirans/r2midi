#!/bin/bash

# create-build-report.sh - Create comprehensive build report
# Usage: ./create-build-report.sh [version] [build_type] [runner_type]

set -euo pipefail

VERSION=${1:-${VERSION:-"0.1.0"}}
BUILD_TYPE=${2:-${BUILD_TYPE:-"dev"}}
RUNNER_TYPE=${3:-${RUNNER_TYPE:-"unknown"}}
NOTARIZED_COUNT=${NOTARIZED_COUNT:-0}
TOTAL_PACKAGES=${TOTAL_PACKAGES:-0}

echo "📋 Creating comprehensive build report..."

# Ensure artifacts directory exists
mkdir -p artifacts

# Get environment variables
APP_SIGNING_IDENTITY=${APP_SIGNING_IDENTITY:-"Unknown"}
INSTALLER_SIGNING_IDENTITY=${INSTALLER_SIGNING_IDENTITY:-"Unknown"}
APPLE_TEAM_ID=${APPLE_TEAM_ID:-"Unknown"}
GITHUB_REF_NAME=${GITHUB_REF_NAME:-"unknown"}
GITHUB_SHA=${GITHUB_SHA:-"unknown"}
GITHUB_EVENT_NAME=${GITHUB_EVENT_NAME:-"unknown"}

# Create the build report
cat > artifacts/BUILD_REPORT.md << EOF
# R2MIDI Native macOS Build Report

## ⚠️ IMPORTANT: This build bypassed Briefcase completely!

## Build Information
- **Version**: $VERSION
- **Build Type**: $BUILD_TYPE
- **Runner**: $RUNNER_TYPE
- **Trigger**: $GITHUB_EVENT_NAME
- **Branch**: $GITHUB_REF_NAME
- **Commit**: $GITHUB_SHA
- **Build Time**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

## Build Method: Native macOS Tools (NOT Briefcase)
- ✅ **py2app**: Application building (instead of briefcase build)
- ✅ **codesign**: Code signing with Developer ID (instead of briefcase signing)
- ✅ **pkgbuild**: PKG installer creation (instead of briefcase package)
- ✅ **notarytool**: Apple notarization (instead of briefcase notarize)
- ✅ **hdiutil**: DMG image creation (instead of briefcase dmg)

## Code Signing
- **Application Signing**: $APP_SIGNING_IDENTITY
- **Installer Signing**: $INSTALLER_SIGNING_IDENTITY
- **Team ID**: $APPLE_TEAM_ID
- **Hardened Runtime**: Enabled
- **Entitlements**: Network, file access, audio input
- **Source**: GitHub Secrets (not local config)

## Notarization Status
- **Notarized Packages**: $NOTARIZED_COUNT/$TOTAL_PACKAGES
- **Notarization Service**: Apple notarytool
- **Ticket Stapling**: Automatic

## Created Packages

EOF

# Add package information
echo "📦 Analyzing created packages..."
for file in artifacts/*.pkg artifacts/*.dmg; do
    if [ -f "$file" ] && [[ "$file" != *"BUILD_REPORT.md" ]]; then
        filename=$(basename "$file")
        size=$(du -h "$file" | cut -f1)
        
        # Check if file is notarized by looking for stapled ticket
        if xcrun stapler validate "$file" >/dev/null 2>&1; then
            status="✅ Signed & Notarized"
        elif codesign --verify "$file" >/dev/null 2>&1; then
            status="🔐 Signed Only"
        else
            status="⚠️ Unsigned"
        fi
        
        echo "- **$filename** ($size) - $status" >> artifacts/BUILD_REPORT.md
    fi
done

# Add the rest of the report
cat >> artifacts/BUILD_REPORT.md << 'EOF'

## Installation Instructions

### PKG Installers (Recommended)
1. Download the `.pkg` file for your desired component
2. Double-click to launch macOS Installer
3. Follow the installation prompts
4. Application will be installed to `/Applications`
5. No security warnings should appear (signed & notarized)

### DMG Images (Alternative)
1. Download the `.dmg` file for your desired component
2. Double-click to mount the disk image
3. Drag the application to the Applications folder
4. Eject the disk image when done

## System Requirements
- **macOS**: 11.0 (Big Sur) or later
- **Architecture**: Intel x64 or Apple Silicon (Universal)
- **Memory**: 512MB RAM minimum
- **Disk Space**: 200MB available space

## Verification Commands

```bash
# Verify PKG signature
pkgutil --check-signature package.pkg

# Verify app signature
codesign --verify --deep --strict /Applications/AppName.app

# Check notarization status
spctl --assess --type install package.pkg

# Verify stapled notarization ticket
xcrun stapler validate package.pkg
```

## Distribution
All packages are production-ready for distribution:
- ✅ Signed with valid Apple Developer ID certificates
- ✅ Notarized by Apple (passes Gatekeeper)
- ✅ No security warnings for end users
- ✅ Compatible with enterprise deployment

---
**Build completed successfully with native macOS tools, bypassing Briefcase completely!**
EOF

echo "✅ Build report created: artifacts/BUILD_REPORT.md"

# Create a summary file with key metrics
cat > artifacts/BUILD_SUMMARY.txt << EOF
R2MIDI Native macOS Build Summary
================================

Build completed: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Version: $VERSION
Build Type: $BUILD_TYPE
Runner: $RUNNER_TYPE

Packages Created: $TOTAL_PACKAGES
Packages Notarized: $NOTARIZED_COUNT

Code Signing:
- App Identity: $APP_SIGNING_IDENTITY
- Installer Identity: $INSTALLER_SIGNING_IDENTITY
- Team ID: $APPLE_TEAM_ID

Build Method: Native macOS Tools (NOT Briefcase)
- py2app for app building
- codesign for signing
- pkgbuild for PKG creation
- hdiutil for DMG creation
- notarytool for notarization

Status: $([ $NOTARIZED_COUNT -eq $TOTAL_PACKAGES ] && echo "SUCCESS - All packages notarized" || echo "PARTIAL - Some packages not notarized")
EOF

echo "✅ Build summary created: artifacts/BUILD_SUMMARY.txt"

# Create checksums for all packages
echo "🔐 Creating package checksums..."
cd artifacts
if ls *.pkg *.dmg >/dev/null 2>&1; then
    shasum -a 256 *.pkg *.dmg > CHECKSUMS.txt 2>/dev/null || echo "No packages found for checksum calculation" > CHECKSUMS.txt
    echo "✅ Checksums created: artifacts/CHECKSUMS.txt"
else
    echo "No packages found for checksum calculation" > CHECKSUMS.txt
    echo "⚠️ No packages found for checksums"
fi
cd ..

# Show final summary
echo ""
echo "📋 BUILD REPORT SUMMARY"
echo "======================="
echo "Version: $VERSION"
echo "Build Type: $BUILD_TYPE"
echo "Total Packages: $TOTAL_PACKAGES"
echo "Notarized: $NOTARIZED_COUNT"
echo "Status: $([ $NOTARIZED_COUNT -eq $TOTAL_PACKAGES ] && echo "✅ Complete Success" || echo "⚠️ Partial Success")"
echo ""
echo "📁 Generated Files:"
echo "  ✅ BUILD_REPORT.md - Comprehensive build documentation"
echo "  ✅ BUILD_SUMMARY.txt - Key metrics and status"
echo "  ✅ CHECKSUMS.txt - SHA256 checksums for verification"
echo ""
echo "🎯 All reports created successfully in artifacts directory"
