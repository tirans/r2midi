#!/bin/bash
# Make all scripts executable

echo "🔧 Making all GitHub secrets scripts executable..."

cd /Users/tirane/Desktop/r2midi

# Make Python scripts executable
chmod +x scripts/setup_github_secrets.py
chmod +x scripts/test_github_setup.py

# Make shell scripts executable  
chmod +x scripts/setup_complete_github_secrets.sh
chmod +x scripts/quick_start.sh
chmod +x scripts/make_executable.sh

echo "✅ All scripts are now executable"
echo ""
echo "📋 Available commands with force option:"
echo ""
echo "🚀 Interactive setup:"
echo "  ./scripts/quick_start.sh [--force]"
echo ""
echo "🔧 Complete automated setup:"
echo "  ./scripts/setup_complete_github_secrets.sh [--force]"
echo ""
echo "⚡ Direct secrets manager:"
echo "  python scripts/setup_github_secrets.py [--force]"
echo ""
echo "🧪 Test configuration (no changes):"
echo "  python scripts/test_github_setup.py"
echo ""
echo "📖 Help:"
echo "  ./scripts/quick_start.sh --help"
echo "  python scripts/setup_github_secrets.py --help"
echo ""
echo "🔥 Force mode examples:"
echo "  ./scripts/quick_start.sh --force                    # Interactive force update"
echo "  python scripts/setup_github_secrets.py -f          # Direct force update"
echo "  ./scripts/setup_complete_github_secrets.sh --force  # Complete force setup"
