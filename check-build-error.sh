#!/bin/bash
# check-build-error.sh - Check what's causing the build failure

echo "🔍 Checking Build Error"
echo "======================="
echo ""

# Check if virtual environments exist
echo "📋 Virtual Environments:"
for venv in venv_server venv_client; do
    if [ -d "$venv" ]; then
        echo "  ✅ $venv exists"
        # Check if it has Python
        if [ -f "$venv/bin/python" ]; then
            echo "     ✅ Python found"
        else
            echo "     ❌ Python NOT found in $venv"
        fi
    else
        echo "  ❌ $venv NOT FOUND"
    fi
done

echo ""
echo "📋 Certificate Environment:"
if [ -f ".local_build_env" ]; then
    echo "  ✅ .local_build_env exists"
    # Check if we can source it
    if source .local_build_env 2>/dev/null; then
        echo "  ✅ Environment can be sourced"
    else
        echo "  ❌ Error sourcing environment"
    fi
else
    echo "  ❌ .local_build_env NOT FOUND"
fi

echo ""
echo "📋 Certificate Files:"
cert_dir="apple_credentials/certificates"
for cert in app_cert.p12 installer_cert.p12; do
    if [ -f "$cert_dir/$cert" ]; then
        echo "  ✅ $cert exists"
    else
        echo "  ❌ $cert NOT FOUND"
    fi
done

echo ""
echo "📋 Testing Certificate Import:"
# Try to list identities in the login keychain
echo "  Checking login keychain for Developer ID certificates..."
cert_count=$(security find-identity -v -p codesigning | grep -c "Developer ID Application" || echo "0")
if [ "$cert_count" -gt 0 ]; then
    echo "  ✅ Found $cert_count Developer ID certificate(s) in keychain"
else
    echo "  ⚠️ No Developer ID certificates found in default keychain"
fi

echo ""
echo "📋 Checking Build Script:"
# Check if the build script has the right structure
if [ -f "build-all-local.sh" ]; then
    # Check for the main function
    if grep -q "^main()" build-all-local.sh; then
        echo "  ✅ Main function found in build script"
    else
        echo "  ❌ Main function NOT found in build script"
    fi
    
    # Check if it's calling setup_local_certificates correctly
    if grep -q "setup_local_certificates" build-all-local.sh; then
        echo "  ✅ Certificate setup function found"
    else
        echo "  ❌ Certificate setup function NOT found"
    fi
fi

echo ""
echo "📋 Running minimal test:"
echo "  Trying to run build script with just help..."
if ./build-all-local.sh --help >/dev/null 2>&1; then
    echo "  ✅ Build script --help works"
else
    echo "  ❌ Build script --help failed"
fi

echo ""
echo "📋 Checking for error in certificate setup:"
# The build seems to fail right after certificate setup
# Let's check if there's an issue with the certificate environment
if [ -f ".cert_environment" ]; then
    echo "  ⚠️ Found .cert_environment file (from CI setup?)"
    echo "  This might conflict with local setup"
    
    # Check if it references a temp keychain that doesn't exist
    if grep -q "TEMP_KEYCHAIN=" .cert_environment; then
        TEMP_KEYCHAIN=$(grep "TEMP_KEYCHAIN=" .cert_environment | cut -d'"' -f2)
        echo "  Checking keychain: $TEMP_KEYCHAIN"
        if security show-keychain-info "$TEMP_KEYCHAIN" >/dev/null 2>&1; then
            echo "  ✅ Keychain exists"
        else
            echo "  ❌ Keychain does NOT exist - this is likely the problem!"
            echo ""
            echo "  🔧 Fix: Remove the stale .cert_environment file:"
            echo "     rm .cert_environment"
        fi
    fi
else
    echo "  ✅ No .cert_environment file (good for local builds)"
fi

echo ""
echo "💡 Likely issue:"
if [ -f ".cert_environment" ]; then
    echo "  The build is trying to use a CI certificate environment (.cert_environment)"
    echo "  that references a temporary keychain that no longer exists."
    echo ""
    echo "  Solution:"
    echo "  rm .cert_environment"
    echo "  ./build-all-local.sh --version 0.1.202 --dev --no-notarize"
fi
