#!/bin/bash
# test-signing-environment.sh - Test script to diagnose signing issues

echo "🔍 Testing Signing Environment"
echo "=============================="
echo ""

echo "1. Current directory:"
pwd
echo ""

echo "2. Repository structure:"
ls -la
echo ""

echo "3. Scripts directory:"
if [ -d scripts ]; then
    echo "Found scripts directory:"
    ls -la scripts/
else
    echo "❌ Scripts directory not found!"
fi
echo ""

echo "4. GitHub scripts directory:"
if [ -d .github/scripts ]; then
    echo "Found .github/scripts directory:"
    ls -la .github/scripts/
else
    echo "❌ .github/scripts directory not found!"
fi
echo ""

echo "5. Looking for bulletproof cleaner:"
if [ -f scripts/bulletproof_clean_app_bundle.py ]; then
    echo "✅ Found bulletproof_clean_app_bundle.py"
    echo "File details:"
    ls -la scripts/bulletproof_clean_app_bundle.py
    echo "First 10 lines:"
    head -10 scripts/bulletproof_clean_app_bundle.py
else
    echo "❌ bulletproof_clean_app_bundle.py not found!"
fi
echo ""

echo "6. App bundles found:"
find . -name "*.app" -type d 2>/dev/null | while read app; do
    echo "  - $app"
    xattr_count=$(find "$app" -exec xattr -l {} \; 2>/dev/null | wc -l)
    echo "    Extended attributes: $xattr_count"
done
echo ""

echo "7. Python environment:"
which python3
python3 --version
echo ""

echo "8. Available cleaning tools:"
echo -n "  xattr: "; which xattr || echo "not found"
echo -n "  ditto: "; which ditto || echo "not found"
echo ""

echo "9. Testing ditto with proper flags:"
if command -v ditto >/dev/null 2>&1; then
    echo "  Testing: ditto --norsrc --noextattr --noacl"
    # Create test file with xattr
    touch /tmp/test_xattr_file
    xattr -w com.apple.test "test value" /tmp/test_xattr_file 2>/dev/null || true
    
    # Try to copy without xattrs
    if ditto --norsrc --noextattr --noacl /tmp/test_xattr_file /tmp/test_clean_file 2>/dev/null; then
        echo "  ✅ Ditto supports required flags"
        
        # Check if xattrs were removed
        if xattr -l /tmp/test_clean_file 2>/dev/null | grep -q "com.apple.test"; then
            echo "  ⚠️  But xattrs were still copied!"
        else
            echo "  ✅ And successfully removes xattrs"
        fi
    else
        echo "  ❌ Ditto doesn't support required flags on this system"
    fi
    
    # Cleanup
    rm -f /tmp/test_xattr_file /tmp/test_clean_file 2>/dev/null
else
    echo "  ❌ ditto command not found!"
fi
echo ""

echo "10. Environment variables:"
echo "  GITHUB_ACTIONS: ${GITHUB_ACTIONS:-not set}"
echo "  CI: ${CI:-not set}"
echo "  RUNNER_OS: ${RUNNER_OS:-not set}"
echo ""

echo "✅ Environment test complete"
