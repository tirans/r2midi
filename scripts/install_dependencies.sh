#!/bin/bash
# Install correct dependencies for GitHub Secrets Manager

echo "🔧 Installing GitHub Secrets Manager Dependencies"
echo "================================================="
echo ""

cd /Users/tirane/Desktop/r2midi

# Check for Python
if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python"
else
    echo "❌ Python not found. Please install Python 3.8+"
    exit 1
fi

echo "✅ Python found: $($PYTHON_CMD --version)"
echo ""

# Uninstall old dependencies if they exist
echo "🧹 Removing old dependencies..."
$PYTHON_CMD -m pip uninstall cryptography -y --quiet 2>/dev/null || true
echo "✅ Cleaned up old dependencies"
echo ""

# Install correct dependencies
echo "📦 Installing correct dependencies..."
echo "• requests - GitHub API client"
echo "• PyNaCl - GitHub Secrets encryption (libsodium)"
echo ""

if $PYTHON_CMD -m pip install -r scripts/requirements.txt; then
    echo ""
    echo "✅ Dependencies installed successfully!"
else
    echo ""
    echo "❌ Failed to install dependencies automatically"
    echo "Try running manually:"
    echo "  $PYTHON_CMD -m pip install requests PyNaCl"
    exit 1
fi

echo ""
echo "🧪 Testing installation..."

# Test imports
if $PYTHON_CMD -c "import requests; import nacl.public; print('✅ All imports successful')" 2>/dev/null; then
    echo "✅ All dependencies working correctly"
else
    echo "❌ Import test failed"
    echo "Please try installing manually:"
    echo "  $PYTHON_CMD -m pip install requests PyNaCl"
    exit 1
fi

echo ""
echo "🎉 Setup complete! Dependencies are ready."
echo ""
echo "📋 You can now run:"
echo "  python scripts/setup_github_secrets.py          # Normal mode"
echo "  python scripts/setup_github_secrets.py --force  # Force mode"
echo "  ./scripts/quick_start.sh                        # Interactive setup"
echo ""
echo "🔧 The encryption issue has been fixed by switching from RSA to libsodium encryption"
