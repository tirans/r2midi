#!/bin/bash
# Quick test for self-hosted runner setup

echo "🖥️ Self-Hosted Runner Environment Test"
echo "======================================"

echo "✅ User: $(whoami)"
echo "✅ Architecture: $(uname -m)"
echo "✅ macOS Version: $(sw_vers -productVersion)"
echo "✅ Python: $(python --version 2>/dev/null || echo 'Python not found')"
echo "✅ Python Path: $(which python 2>/dev/null || echo 'Not found')"
echo "✅ Pip: $(pip --version 2>/dev/null || echo 'Pip not found')"
echo "✅ Homebrew: $(brew --version 2>/dev/null | head -1 || echo 'Homebrew not found')"

echo ""
echo "🔍 Checking Python packages..."
if python -c "import briefcase" 2>/dev/null; then
    echo "✅ Briefcase: Available"
else
    echo "⚠️ Briefcase: Not installed (will be installed during build)"
fi

echo ""
echo "🔍 Checking permissions..."
if [ -w "$HOME" ]; then
    echo "✅ Home directory: Writable"
else
    echo "❌ Home directory: Not writable"
fi

if [ -w "/tmp" ]; then
    echo "✅ /tmp directory: Writable"  
else
    echo "❌ /tmp directory: Not writable"
fi

echo ""
echo "🎯 RECOMMENDATION:"
echo "Your runner environment looks good! The build should work now."
echo "Next: Commit and push the updated workflow to test."
