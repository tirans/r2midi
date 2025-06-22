#!/bin/bash
# diagnose-build.sh - Diagnose why build appears to only check certificates

set -euo pipefail

echo "🔍 R2MIDI Build Diagnostics"
echo "==========================="
echo ""

VERSION="${1:-0.1.201}"
echo "Checking version: $VERSION"
echo ""

# Check if build script exists and is executable
echo "📋 Build Script Status:"
if [ -f "build-all-local.sh" ]; then
    echo "  ✅ build-all-local.sh exists"
    if [ -x "build-all-local.sh" ]; then
        echo "  ✅ build-all-local.sh is executable"
    else
        echo "  ❌ build-all-local.sh is NOT executable"
        echo "     Fix: chmod +x build-all-local.sh"
    fi
else
    echo "  ❌ build-all-local.sh NOT FOUND"
fi

echo ""
echo "📋 Existing Artifacts for version $VERSION:"
if [ -d "artifacts" ]; then
    found_artifacts=false
    while IFS= read -r artifact; do
        if [[ "$(basename "$artifact")" == *"$VERSION"* ]]; then
            found_artifacts=true
            size=$(du -sh "$artifact" 2>/dev/null | cut -f1 || echo "unknown")
            created=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$artifact" 2>/dev/null || echo "unknown")
            echo "  📦 $(basename "$artifact")"
            echo "     Size: $size"
            echo "     Created: $created"
        fi
    done < <(find artifacts -name "*.pkg" -o -name "*.dmg" 2>/dev/null)
    
    if [ "$found_artifacts" = false ]; then
        echo "  ℹ️ No artifacts found for version $VERSION"
    fi
else
    echo "  ℹ️ No artifacts directory"
fi

echo ""
echo "📋 Build Directories:"
for dir in build_server build_client; do
    if [ -d "$dir" ]; then
        echo "  ✅ $dir exists"
        if [ -d "$dir/dist" ]; then
            app_found=false
            while IFS= read -r app; do
                app_found=true
                echo "     📱 $(basename "$app")"
            done < <(find "$dir/dist" -name "*.app" -type d 2>/dev/null)
            
            if [ "$app_found" = false ]; then
                echo "     ⚠️ No .app bundle found"
            fi
        else
            echo "     ⚠️ No dist directory"
        fi
    else
        echo "  ❌ $dir NOT FOUND"
    fi
done

echo ""
echo "📋 Virtual Environments:"
for venv in venv_server venv_client; do
    if [ -d "$venv" ]; then
        echo "  ✅ $venv exists"
    else
        echo "  ❌ $venv NOT FOUND"
        echo "     Fix: ./setup-virtual-environments.sh"
    fi
done

echo ""
echo "📋 Certificate Status:"
if [ -f ".local_build_env" ]; then
    echo "  ✅ .local_build_env exists"
    source .local_build_env 2>/dev/null || echo "     ⚠️ Could not source environment"
else
    echo "  ❌ .local_build_env NOT FOUND"
    echo "     Fix: ./setup-local-certificates.sh"
fi

# Check if certificates are in keychain
echo ""
echo "📋 Keychain Certificates:"
cert_count=$(security find-identity -v -p codesigning | grep -c "Developer ID Application" || echo "0")
if [ "$cert_count" -gt 0 ]; then
    echo "  ✅ Found $cert_count Developer ID certificate(s)"
else
    echo "  ❌ No Developer ID certificates found"
fi

echo ""
echo "🔍 Diagnosis:"
echo "-------------"

# Analyze the situation
if [ -f "artifacts/R2MIDI-Server-$VERSION-indi.pkg" ] && [ -f "artifacts/R2MIDI-Client-$VERSION-indi.pkg" ]; then
    echo "✅ Packages for version $VERSION already exist!"
    echo ""
    echo "This is likely why the build script appears to only check certificates."
    echo "The script may be skipping the build because artifacts already exist."
    echo ""
    echo "Solutions:"
    echo "1. Use --clean flag to force rebuild:"
    echo "   ./build-all-local.sh --version $VERSION --clean"
    echo ""
    echo "2. Build with a new version number:"
    echo "   ./build-all-local.sh --version 0.1.202"
    echo ""
    echo "3. Manually remove existing artifacts:"
    echo "   rm artifacts/*$VERSION*"
    echo "   ./build-all-local.sh --version $VERSION"
else
    echo "❌ Packages for version $VERSION do NOT exist."
    echo ""
    echo "The build should create new packages. Possible issues:"
    
    if [ ! -d "venv_server" ] || [ ! -d "venv_client" ]; then
        echo "- Virtual environments missing"
    fi
    
    if [ ! -f ".local_build_env" ]; then
        echo "- Certificate environment not configured"
    fi
    
    if [ "$cert_count" -eq 0 ]; then
        echo "- No Developer ID certificates in keychain"
    fi
fi

echo ""
echo "📋 Test Commands:"
echo "-----------------"
echo "# Check what the build script will do:"
echo "./build-all-local.sh --version $VERSION --help"
echo ""
echo "# Force a clean rebuild:"
echo "./build-all-local.sh --version $VERSION --clean"
echo ""
echo "# Try a development build (faster):"
echo "./build-all-local.sh --version $VERSION --dev --no-notarize"
echo ""
echo "# Check build script output in detail:"
echo "bash -x ./build-all-local.sh --version $VERSION 2>&1 | head -50"
