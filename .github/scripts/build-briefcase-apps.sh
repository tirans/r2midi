#!/bin/bash
set -euo pipefail

# Build R2MIDI applications using Briefcase
# Usage: build-briefcase-apps.sh <platform> <signing_mode>
# Example: build-briefcase-apps.sh macos signed

PLATFORM="${1:-linux}"
SIGNING_MODE="${2:-unsigned}"

echo "🚀 Building R2MIDI applications for $PLATFORM (${SIGNING_MODE})"

# Validate inputs
case "$PLATFORM" in
    linux|windows|macos)
        ;;
    *)
        echo "❌ Error: Unsupported platform '$PLATFORM'"
        echo "Supported platforms: linux, windows, macos"
        exit 1
        ;;
esac

case "$SIGNING_MODE" in
    signed|unsigned)
        ;;
    *)
        echo "❌ Error: Invalid signing mode '$SIGNING_MODE'"
        echo "Supported modes: signed, unsigned"
        exit 1
        ;;
esac

# Set up environment
export PYTHONPATH="${PWD}:${PYTHONPATH:-}"

# Create build directory
mkdir -p build

# Function to build an app with Briefcase
build_app() {
    local app_name="$1"
    local platform="$2"
    local signing_mode="$3"

    echo "📦 Building $app_name for $platform..."

    # Determine the project directory and app name for briefcase
    local project_dir=""
    local briefcase_app_name=""

    case "$app_name" in
        server)
            project_dir="server"
            briefcase_app_name="server"
            ;;
        r2midi-client)
            project_dir="r2midi_client"
            briefcase_app_name="r2midi-client"
            ;;
        *)
            echo "❌ Unknown app name: $app_name"
            exit 1
            ;;
    esac

    # Save current directory
    local original_dir=$(pwd)

    # Change to the project directory
    cd "$project_dir"

    # Clean previous builds if they exist
    if [ -d "build" ]; then
        echo "🧹 Cleaning previous build for $app_name..."
        rm -rf "build"
    fi

    # Platform-specific build commands
    case "$platform" in
        linux)
            echo "🐧 Building Linux application..."
            briefcase build linux system -a "$briefcase_app_name"
            if [ $? -eq 0 ]; then
                briefcase package linux system -a "$briefcase_app_name"
            fi
            ;;
        windows)
            echo "🪟 Building Windows application..."
            briefcase build windows app -a "$briefcase_app_name"
            if [ $? -eq 0 ]; then
                briefcase package windows app -a "$briefcase_app_name"
            fi
            ;;
        macos)
            echo "🍎 Building macOS application..."
            if [ "$signing_mode" = "signed" ]; then
                # For signed builds, we'll handle signing separately
                # First build without signing
                briefcase build macos app -a "$briefcase_app_name"
                if [ $? -eq 0 ]; then
                    echo "✅ Built $app_name successfully (signing will be handled separately)"
                fi
            else
                # Unsigned build
                briefcase build macos app -a "$briefcase_app_name"
                if [ $? -eq 0 ]; then
                    briefcase package macos app -a "$briefcase_app_name"
                fi
            fi
            ;;
    esac

    local build_result=$?

    # Return to original directory
    cd "$original_dir"

    if [ $build_result -eq 0 ]; then
        echo "✅ Successfully built $app_name"
    else
        echo "❌ Failed to build $app_name"
        exit 1
    fi
}

# Build both applications
echo "🔧 Building R2MIDI Server..."
build_app "server" "$PLATFORM" "$SIGNING_MODE"

echo "🔧 Building R2MIDI Client..."
build_app "r2midi-client" "$PLATFORM" "$SIGNING_MODE"

# Create artifacts directory and copy build outputs
echo "📋 Organizing build artifacts..."
mkdir -p artifacts

case "$PLATFORM" in
    linux)
        # Copy Linux artifacts from both server and client directories
        find server/dist/ -name "*.deb" -exec cp {} artifacts/ \; 2>/dev/null || true
        find server/dist/ -name "*.tar.gz" -exec cp {} artifacts/ \; 2>/dev/null || true
        find server/dist/ -name "*.AppImage" -exec cp {} artifacts/ \; 2>/dev/null || true
        find r2midi_client/dist/ -name "*.deb" -exec cp {} artifacts/ \; 2>/dev/null || true
        find r2midi_client/dist/ -name "*.tar.gz" -exec cp {} artifacts/ \; 2>/dev/null || true
        find r2midi_client/dist/ -name "*.AppImage" -exec cp {} artifacts/ \; 2>/dev/null || true
        ;;
    windows)
        # Copy Windows artifacts from both server and client directories
        find server/dist/ -name "*.msi" -exec cp {} artifacts/ \; 2>/dev/null || true
        find server/dist/ -name "*.zip" -exec cp {} artifacts/ \; 2>/dev/null || true
        find r2midi_client/dist/ -name "*.msi" -exec cp {} artifacts/ \; 2>/dev/null || true
        find r2midi_client/dist/ -name "*.zip" -exec cp {} artifacts/ \; 2>/dev/null || true
        ;;
    macos)
        # Copy macOS artifacts (apps for further processing)
        if [ -d "server/dist" ]; then
            cp -r server/dist/* artifacts/ 2>/dev/null || true
        fi
        if [ -d "r2midi_client/dist" ]; then
            cp -r r2midi_client/dist/* artifacts/ 2>/dev/null || true
        fi
        # Copy any packages that were created
        find server/dist/ -name "*.dmg" -exec cp {} artifacts/ \; 2>/dev/null || true
        find server/dist/ -name "*.pkg" -exec cp {} artifacts/ \; 2>/dev/null || true
        find r2midi_client/dist/ -name "*.dmg" -exec cp {} artifacts/ \; 2>/dev/null || true
        find r2midi_client/dist/ -name "*.pkg" -exec cp {} artifacts/ \; 2>/dev/null || true
        ;;
esac

# Generate build information
cat > artifacts/BUILD_INFO.txt << EOF
R2MIDI Build Information
========================

Platform: $PLATFORM
Signing Mode: $SIGNING_MODE
Build Tool: Briefcase
Build Time: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Python Version: $(python --version)
Briefcase Version: $(briefcase --version 2>/dev/null || echo "Unknown")

Applications Built:
- R2MIDI Server
- R2MIDI Client

Artifacts:
EOF

# List artifacts
if [ -d "artifacts" ] && [ "$(ls -A artifacts/)" ]; then
    find artifacts/ -type f -not -name "BUILD_INFO.txt" | sort | while read file; do
        if [ -f "$file" ]; then
            size=$(du -h "$file" | cut -f1)
            echo "  - $(basename "$file") ($size)" >> artifacts/BUILD_INFO.txt
        fi
    done
else
    echo "  - No artifacts generated" >> artifacts/BUILD_INFO.txt
fi

echo "✅ Build complete! Artifacts available in artifacts/ directory"
echo "📋 Build summary:"
cat artifacts/BUILD_INFO.txt
