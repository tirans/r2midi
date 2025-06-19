#!/bin/bash
# Clean up extra scripts created during development

echo "🧹 Cleaning up unnecessary scripts..."

cd /Users/tirane/Desktop/r2midi/scripts

# Remove extra scripts created today
rm -f setup_complete_github_secrets.sh
rm -f quick_start.sh
rm -f install_dependencies.sh  
rm -f test_encryption_fix.py
rm -f apply_fix.sh
rm -f test_github_setup.py
rm -f make_all_executable.sh
rm -f make_executable.sh
rm -f requirements.txt

echo "✅ Cleaned up extra scripts"
echo ""
echo "📋 Remaining scripts:"
echo "  setup_github_secrets.py  - Main script (auto-installs dependencies)"
echo "  setup_secrets.sh         - Simple bash wrapper"
echo ""
echo "🚀 Usage:"
echo "  python scripts/setup_github_secrets.py [--force]"
echo "  ./scripts/setup_secrets.sh [--force]"
