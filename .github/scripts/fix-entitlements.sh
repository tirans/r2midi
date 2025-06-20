#!/bin/bash
set -euo pipefail

# Diagnose and fix entitlements file issues
# Usage: fix-entitlements.sh

echo "🔍 Diagnosing entitlements file..."

# Check if entitlements.plist exists
if [ -f "entitlements.plist" ]; then
    echo "📄 Found entitlements.plist"
    
    # Check for common issues
    echo "🔍 Checking for XML validity..."
    if plutil -lint "entitlements.plist" >/dev/null 2>&1; then
        echo "✅ entitlements.plist is valid XML"
    else
        echo "❌ entitlements.plist has XML errors:"
        plutil -lint "entitlements.plist" 2>&1 || true
        
        # Offer to create a clean version
        echo ""
        echo "🔧 Creating clean entitlements.plist..."
        
        # Backup the original
        cp "entitlements.plist" "entitlements.plist.backup"
        echo "📋 Backed up original to entitlements.plist.backup"
        
        # Create clean entitlements
        cat > entitlements.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.device.microphone</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
</dict>
</plist>
EOF
        
        echo "✅ Created clean entitlements.plist"
        
        # Verify the new file
        if plutil -lint "entitlements.plist" >/dev/null 2>&1; then
            echo "✅ New entitlements.plist is valid"
        else
            echo "❌ Something went wrong creating new entitlements file"
            exit 1
        fi
    fi
    
    # Show detailed analysis
    echo ""
    echo "📋 Entitlements file contents:"
    echo "File size: $(wc -c < entitlements.plist) bytes"
    echo "Line count: $(wc -l < entitlements.plist)"
    
    # Check for invisible characters
    if file "entitlements.plist" | grep -q "with CRLF"; then
        echo "⚠️ Warning: File has Windows line endings (CRLF)"
        echo "🔧 Converting to Unix line endings..."
        sed -i '' 's/\r$//' "entitlements.plist"
        echo "✅ Converted to Unix line endings"
    fi
    
    # Test with codesign
    echo ""
    echo "🔍 Testing entitlements with codesign..."
    
    # Create a temporary test file
    echo "test" > test_entitlements_check
    
    if codesign --entitlements "entitlements.plist" --display --xml test_entitlements_check 2>/dev/null; then
        echo "✅ Entitlements file works with codesign"
    else
        echo "❌ Entitlements file fails codesign validation:"
        codesign --entitlements "entitlements.plist" --display --xml test_entitlements_check 2>&1 || true
    fi
    
    # Cleanup
    rm -f test_entitlements_check
    
else
    echo "📄 No entitlements.plist found, creating one..."
    
    cat > entitlements.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.device.microphone</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
</dict>
</plist>
EOF
    
    echo "✅ Created new entitlements.plist"
fi

echo ""
echo "🎯 Final verification:"
if plutil -lint "entitlements.plist" >/dev/null 2>&1; then
    echo "✅ entitlements.plist is ready for use"
else
    echo "❌ entitlements.plist still has issues"
    exit 1
fi
