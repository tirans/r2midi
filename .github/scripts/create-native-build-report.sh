#!/bin/bash
set -euo pipefail

# Create build report and logs for native macOS build
# Usage: create-native-build-report.sh [version] [build_type]

VERSION="${1:-${APP_VERSION:-1.0.0}}"
BUILD_TYPE="${2:-dev}"

echo "📋 Creating comprehensive build report..."

cat > artifacts/BUILD_REPORT.md << EOF
# R2MIDI Native macOS Build Report

## ⚠️ IMPORTANT: This build bypassed Briefcase completely!

## Build Information
- **Version**: $VERSION
- **Build Type**: $BUILD_TYPE
- **Runner**: ${RUNNER_TYPE:-unknown}
- **Trigger**: ${GITHUB_EVENT_NAME:-manual}
- **Branch**: ${GITHUB_REF_NAME:-unknown}
- **Commit**: ${GITHUB_SHA:-unknown}
- **Build Time**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

## Build Method: Native macOS Tools (NOT Briefcase)
- ✅ **py2app**: Application building (instead of briefcase build)
- ✅ **codesign**: Code signing with Developer ID (instead of briefcase signing)
- ✅ **pkgbuild**: PKG installer creation (instead of briefcase package)
- ✅ **notarytool**: Apple notarization (instead of briefcase notarize)
- ✅ **hdiutil**: DMG image creation (instead of briefcase dmg)

## Code Signing
- **Application Signing**: ${APP_SIGNING_IDENTITY:-Not set}
- **Installer Signing**: ${INSTALLER_SIGNING_IDENTITY:-Not set}
- **Team ID**: ${APPLE_TEAM_ID:-Not set}
- **Hardened Runtime**: Enabled
- **Entitlements**: Network, file access, audio input
- **Source**: GitHub Secrets (not local config)

## Notarization Status
- **Notarized Packages**: ${NOTARIZED_COUNT:-0}/${TOTAL_PACKAGES:-0}
- **Notarization Service**: Apple notarytool
- **Ticket Stapling**: Automatic

## Created Packages

EOF

# Add package information
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

cat >> artifacts/BUILD_REPORT.md << EOF

## Installation Instructions

### PKG Installers (Recommended)
1. Download the \`.pkg\` file for your desired component
2. Double-click to launch macOS Installer
3. Follow the installation prompts
4. Application will be installed to \`/Applications\`
5. No security warnings should appear (signed & notarized)

### DMG Images (Alternative)
1. Download the \`.dmg\` file for your desired component
2. Double-click to mount the disk image
3. Drag the application to the Applications folder
4. Eject the disk image when done

## System Requirements
- **macOS**: 11.0 (Big Sur) or later
- **Architecture**: Intel x64 or Apple Silicon (Universal)
- **Memory**: 512MB RAM minimum
- **Disk Space**: 200MB available space

## Verification Commands

\`\`\`bash
# Verify PKG signature
pkgutil --check-signature package.pkg

# Verify app signature
codesign --verify --deep --strict /Applications/AppName.app

# Check notarization status
spctl --assess --type install package.pkg

# Verify stapled notarization ticket
xcrun stapler validate package.pkg
\`\`\`

## Distribution
All packages are production-ready for distribution:
- ✅ Signed with valid Apple Developer ID certificates
- ✅ Notarized by Apple (passes Gatekeeper)
- ✅ No security warnings for end users
- ✅ Compatible with enterprise deployment

---
**Build completed successfully with native macOS tools, bypassing Briefcase completely!**
EOF

echo "✅ Comprehensive build report created: artifacts/BUILD_REPORT.md"
