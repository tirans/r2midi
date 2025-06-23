#!/bin/bash
# Make all signing-related scripts executable

chmod +x fix-signing.sh
chmod +x clean-for-signing.sh
chmod +x emergency-fix-python-framework.sh
chmod +x SIGNING_SOLUTION_GUIDE.sh
chmod +x scripts/bulletproof_clean_app_bundle.py
chmod +x scripts/clean-app-bundles.sh
chmod +x scripts/fix_macos_signing_issue.py

echo "✅ All signing scripts are now executable"
echo ""
echo "Run ./SIGNING_SOLUTION_GUIDE.sh for instructions"
