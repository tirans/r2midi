#!/bin/bash
# Make all new scripts executable and test the encryption fix

echo "🔧 Applying GitHub Secrets Encryption Fix"
echo "=========================================="
echo ""

cd /Users/tirane/Desktop/r2midi

# Make new scripts executable
echo "📁 Making scripts executable..."
chmod +x scripts/install_dependencies.sh
chmod +x scripts/test_encryption_fix.py
chmod +x scripts/setup_complete_github_secrets.sh
chmod +x scripts/setup_github_secrets.py
chmod +x scripts/test_github_setup.py
echo "✅ All scripts are now executable"
echo ""

# Run the dependency installer
echo "🔧 Installing correct dependencies..."
if ./scripts/install_dependencies.sh; then
    echo ""
    echo "✅ Dependencies installed successfully"
else
    echo ""
    echo "❌ Dependency installation failed"
    exit 1
fi

echo ""
echo "🧪 Testing the encryption fix..."
if python scripts/test_encryption_fix.py; then
    echo ""
    echo "🎉 ENCRYPTION FIX SUCCESSFUL!"
    echo ""
    echo "🚀 Your GitHub Secrets Manager is now ready to use:"
    echo ""
    echo "📋 Available commands:"
    echo "  python scripts/setup_github_secrets.py --force  # Force update all secrets"
    echo "  python scripts/setup_github_secrets.py          # Normal idempotent mode"
    echo "  ./scripts/quick_start.sh --force                # Interactive force mode"
    echo "  ./scripts/setup_complete_github_secrets.sh -f   # Complete force setup"
    echo ""
    echo "💡 Recommendation: Use force mode to update all secrets with the fixed encryption:"
    echo "  python scripts/setup_github_secrets.py --force"
else
    echo ""
    echo "❌ Encryption test failed"
    echo "Please check the error messages above"
    exit 1
fi
