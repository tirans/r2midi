# macOS Code Signing Fix Summary

## Problem
The macOS code signing was failing with the error:
```
resource fork, Finder information, or similar detritus not allowed
```

This happens because files in the app bundles have extended attributes (xattrs), resource forks, or Finder metadata that Apple's codesign tool rejects.

## Root Cause
- PyInstaller/Briefcase creates app bundles with extended attributes
- Standard cleanup methods (`xattr -cr`) are not thorough enough
- Extended attributes persist even after multiple cleanup attempts
- Python.framework and other embedded frameworks are particularly problematic

## Solution Implemented

### 1. Deep Clean Script (`scripts/deep_clean_app_bundle.py`)
- Performs nuclear-level cleanup of app bundles
- Removes ALL metadata files (.DS_Store, ._, __MACOSX, etc.)
- Strips extended attributes using multiple methods
- Special handling for frameworks
- Can rebuild app bundle from scratch if needed

### 2. Integration Scripts
- `scripts/clean-app-bundles.sh` - Wrapper to clean all app bundles
- `scripts/fix_macos_signing_issue.py` - Patches build scripts
- `.github/scripts/modules/deep-clean-utils.sh` - Module for CI/CD
- `fix-signing.sh` - Quick fix implementation script

### 3. Build Process Updates
- Modified signing script to use deep cleaning before code signing
- Created hooks for Briefcase post-build cleanup
- Integrated into both local and GitHub Actions workflows

## How to Use

### Quick Fix (Recommended)
```bash
chmod +x fix-signing.sh
./fix-signing.sh
./build-all-local.sh --clean --version 0.1.207
```

### Manual Cleanup
```bash
# Clean specific app bundles
python3 scripts/deep_clean_app_bundle.py "build_client/dist/R2MIDI Client.app"
python3 scripts/deep_clean_app_bundle.py "build_server/dist/R2MIDI Server.app"

# Then build normally
./build-all-local.sh --version 0.1.207
```

### For CI/CD
The GitHub Actions workflow will automatically use the deep cleaning process.

## What the Fix Does

1. **Before Signing**: Runs deep clean on app bundles
2. **Deep Clean Process**:
   - Removes all metadata files recursively
   - Strips ALL extended attributes
   - Cleans frameworks specially
   - Rebuilds app bundle if needed (nuclear option)
3. **Verification**: Checks that no extended attributes remain
4. **Signing**: Proceeds with clean app bundle

## Expected Results

After applying this fix:
- No more "resource fork" errors during signing
- Clean app bundles with 0 extended attributes
- Successful code signing and notarization
- Apps that pass Gatekeeper validation

## Troubleshooting

If you still see errors:

1. **Verify cleanup worked**:
   ```bash
   find "build_client/dist/R2MIDI Client.app" -exec xattr -l {} \; | wc -l
   # Should output 0
   ```

2. **Force rebuild**:
   ```bash
   python3 scripts/deep_clean_app_bundle.py --rebuild "path/to/app.app"
   ```

3. **Check certificates**:
   ```bash
   security find-identity -v -p codesigning | grep "Developer ID"
   ```

4. **Enable verbose logging**:
   ```bash
   LOG_LEVEL=0 ./build-all-local.sh --version 0.1.207
   ```

## Technical Details

The fix addresses the core issue by:
- Using Python's file operations which don't preserve xattrs
- Rebuilding app bundles in a clean temporary directory
- Multiple fallback methods to ensure cleanup
- Special handling for framework bundles
- Verification after each cleanup step

This solution has been tested to handle even the most stubborn extended attributes that resist standard cleanup methods.
