#!/bin/bash
# test-pkg-preservation.sh - Test that the clean environment script preserves .pkg files

echo "🧪 Testing PKG file preservation in clean environment script"
echo ""

# Create test artifacts directory and files
echo "📁 Setting up test environment..."
mkdir -p artifacts
echo "dummy content" > artifacts/test-file.txt
echo "dummy pkg content" > artifacts/R2MIDI-Test-1.0.0.pkg
echo "dummy report" > artifacts/TEST_REPORT.md

echo "📊 Before cleanup:"
ls -la artifacts/

echo ""
echo "🧹 Running clean environment script..."
./clean-environment.sh

echo ""
echo "📊 After cleanup:"
if [ -d "artifacts" ]; then
    ls -la artifacts/
    if [ -f "artifacts/R2MIDI-Test-1.0.0.pkg" ]; then
        echo "✅ PKG file was preserved!"
    else
        echo "❌ PKG file was NOT preserved"
    fi
    
    if [ ! -f "artifacts/test-file.txt" ]; then
        echo "✅ Non-PKG files were cleaned"
    else
        echo "❌ Non-PKG files were NOT cleaned"
    fi
else
    echo "❌ Artifacts directory was completely removed"
fi

echo ""
echo "🧪 Testing complete cleanup (--no-preserve-packages)..."
echo "dummy pkg content" > artifacts/R2MIDI-Test-Complete-1.0.0.pkg 2>/dev/null || true
./clean-environment.sh --no-preserve-packages

if [ ! -d "artifacts" ] || [ ! -f "artifacts/R2MIDI-Test-Complete-1.0.0.pkg" ]; then
    echo "✅ Complete cleanup works correctly"
else
    echo "❌ Complete cleanup failed"
fi

echo ""
echo "🏁 Test completed!"
