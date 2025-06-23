#!/bin/bash
# commit-signing-fixes.sh - Helper to commit all signing fixes

echo "📝 Preparing to commit signing fixes..."
echo ""

# Make this script executable
chmod +x commit-signing-fixes.sh

# Make all scripts executable locally
./make-signing-scripts-executable.sh

echo ""
echo "Files changed for signing fix:"
echo "=============================="
echo ""

# Key files changed
echo "Core cleaning script (FIXED with proper ditto flags):"
echo "  - scripts/bulletproof_clean_app_bundle.py"
echo ""

echo "GitHub Actions updates:"
echo "  - .github/workflows/build-macos.yml (make Python scripts executable)"
echo "  - .github/scripts/sign-and-notarize-macos.sh (better path resolution)"
echo "  - .github/scripts/emergency-clean-app.sh (new fallback cleaner)"
echo ""

echo "Helper scripts:"
echo "  - test-signing-environment.sh (diagnostic tool)"
echo "  - GITHUB_ACTIONS_SIGNING_FIX.md (documentation)"
echo ""

echo "Removed/deprecated:"
echo "  - scripts/deep_clean_app_bundle.py (moved to deprecated/)"
echo "  - scripts/fix_macos_signing.py (moved to deprecated/)"
echo ""

echo "Git status:"
echo "==========="
git status --short

echo ""
echo "Suggested commit message:"
echo "========================"
echo ""
cat << 'EOF'
fix: macOS code signing extended attributes issue

FIXED: The ditto command was preserving extended attributes by default

Key changes:
- Use `ditto --norsrc --noextattr --noacl` to exclude ALL metadata
- Always use `xattr -rc` (not -cr) for recursive clearing  
- Add path resolution and debugging for GitHub Actions
- Make Python scripts executable in workflow
- Add emergency shell-based cleaner as fallback
- Remove Python cache files that often have xattrs

The cleaning now actually removes ALL extended attributes, fixing the
persistent "resource fork, Finder information, or similar detritus not allowed" error.

Tested solutions:
- Proper ditto flags prevent xattr copying
- Multiple cleanup passes ensure complete removal
- Works in both local and GitHub Actions environments
EOF

echo ""
echo "To commit these changes:"
echo "  git add -A"
echo "  git commit -m \"fix: macOS code signing extended attributes issue\""
echo "  git push"
