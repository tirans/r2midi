#!/bin/bash
set -euo pipefail

# Prepare platform-specific build artifacts
# Usage: prepare-platform-artifacts.sh <platform> <version>

PLATFORM="${1:-}"
VERSION="${2:-}"

if [ -z "$PLATFORM" ] || [ -z "$VERSION" ]; then
    echo "❌ Error: Missing required arguments"
    echo "Usage: prepare-platform-artifacts.sh <platform> <version>"
    exit 1
fi

echo "📦 Preparing $PLATFORM artifacts for version $VERSION..."

# Create artifacts directory
mkdir -p build_artifacts

# Platform-specific packaging
case "$PLATFORM" in
    linux)
        echo "🐧 Packaging Linux builds..."
        
        # Copy .deb packages if they exist
        if find dist/ -name "*.deb" 2>/dev/null | grep -q .; then
            echo "📦 Found .deb packages"
            find dist/ -name "*.deb" -exec cp {} build_artifacts/ \;
        fi
        
        # Create tar.gz archives for portable versions
        if [ -d "build/server/linux/system" ]; then
            echo "📦 Creating Server tar.gz..."
            tar -czf "build_artifacts/R2MIDI-Server-linux-v${VERSION}.tar.gz" \
                -C build/server/linux/system .
        fi
        
        if [ -d "build/r2midi-client/linux/system" ]; then
            echo "📦 Creating Client tar.gz..."
            tar -czf "build_artifacts/R2MIDI-Client-linux-v${VERSION}.tar.gz" \
                -C build/r2midi-client/linux/system .
        fi
        ;;
        
    windows)
        echo "🪟 Packaging Windows builds..."
        
        # Use appropriate compression tool
        if command -v powershell >/dev/null 2>&1; then
            COMPRESS_CMD="powershell"
        elif command -v zip >/dev/null 2>&1; then
            COMPRESS_CMD="zip"
        else
            COMPRESS_CMD="tar"
        fi
        
        echo "Using compression command: $COMPRESS_CMD"
        
        # Package Server
        if [ -d "build/server/windows/app" ]; then
            echo "📦 Packaging R2MIDI Server..."
            cd build/server/windows/app
            
            case "$COMPRESS_CMD" in
                powershell)
                    powershell -NoProfile -ExecutionPolicy Bypass -Command \
                        "Compress-Archive -Path '.\*' -DestinationPath '${GITHUB_WORKSPACE}/build_artifacts/R2MIDI-Server-windows-v${VERSION}.zip' -Force"
                    ;;
                zip)
                    zip -r "$GITHUB_WORKSPACE/build_artifacts/R2MIDI-Server-windows-v${VERSION}.zip" *
                    ;;
                tar)
                    tar -czf "$GITHUB_WORKSPACE/build_artifacts/R2MIDI-Server-windows-v${VERSION}.tar.gz" *
                    ;;
            esac
            
            cd "$GITHUB_WORKSPACE"
            echo "✅ Server packaging complete"
        fi
        
        # Package Client
        if [ -d "build/r2midi-client/windows/app" ]; then
            echo "📦 Packaging R2MIDI Client..."
            cd build/r2midi-client/windows/app
            
            case "$COMPRESS_CMD" in
                powershell)
                    powershell -NoProfile -ExecutionPolicy Bypass -Command \
                        "Compress-Archive -Path '.\*' -DestinationPath '${GITHUB_WORKSPACE}/build_artifacts/R2MIDI-Client-windows-v${VERSION}.zip' -Force"
                    ;;
                zip)
                    zip -r "$GITHUB_WORKSPACE/build_artifacts/R2MIDI-Client-windows-v${VERSION}.zip" *
                    ;;
                tar)
                    tar -czf "$GITHUB_WORKSPACE/build_artifacts/R2MIDI-Client-windows-v${VERSION}.tar.gz" *
                    ;;
            esac
            
            cd "$GITHUB_WORKSPACE"
            echo "✅ Client packaging complete"
        fi
        
        # Also check for .msi installers
        if find dist/ -name "*.msi" 2>/dev/null | grep -q .; then
            echo "📦 Found .msi installers"
            find dist/ -name "*.msi" -exec cp {} build_artifacts/ \;
        fi
        ;;
        
    macos)
        echo "🍎 Packaging macOS builds..."
        
        # Copy .dmg and .pkg files
        if find dist/ -name "*.dmg" -o -name "*.pkg" 2>/dev/null | grep -q .; then
            echo "📦 Found macOS installers"
            find dist/ -name "*.dmg" -o -name "*.pkg" -exec cp {} build_artifacts/ \;
        fi
        
        # Also create .app bundles if needed
        if [ -d "build/server/macos/app" ]; then
            echo "📦 Creating Server .app bundle..."
            cd build/server/macos/app
            tar -czf "$GITHUB_WORKSPACE/build_artifacts/R2MIDI-Server-macos-v${VERSION}-app.tar.gz" *.app
            cd "$GITHUB_WORKSPACE"
        fi
        
        if [ -d "build/r2midi-client/macos/app" ]; then
            echo "📦 Creating Client .app bundle..."
            cd build/r2midi-client/macos/app
            tar -czf "$GITHUB_WORKSPACE/build_artifacts/R2MIDI-Client-macos-v${VERSION}-app.tar.gz" *.app
            cd "$GITHUB_WORKSPACE"
        fi
        ;;
        
    *)
        echo "❌ Error: Unknown platform '$PLATFORM'"
        exit 1
        ;;
esac

# List final artifacts
echo ""
echo "📦 Final artifacts in build_artifacts/:"
if [ -d build_artifacts ] && [ "$(ls -A build_artifacts)" ]; then
    ls -la build_artifacts/
    
    # Calculate total size
    TOTAL_SIZE=$(du -sh build_artifacts | cut -f1)
    echo ""
    echo "📊 Total size: $TOTAL_SIZE"
else
    echo "⚠️ No artifacts found!"
    exit 1
fi

echo ""
echo "✅ Artifact preparation complete!"
