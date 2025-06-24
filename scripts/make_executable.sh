#!/bin/bash
# Make scripts executable

echo "🔧 Making scripts executable..."

cd /Users/tirane/Desktop/r2midi

chmod +x scripts/setup_complete_github_secrets.sh
chmod +x scripts/test_github_setup.py
chmod +x scripts/setup_github_secrets.py

echo "✅ Scripts are now executable"
echo ""
echo "📋 Available commands:"
echo "  ./scripts/setup_complete_github_secrets.sh  - Complete automated setup"
echo "  python scripts/test_github_setup.py         - Test configuration"
echo "  python scripts/setup_github_secrets.py      - Main secrets manager"
