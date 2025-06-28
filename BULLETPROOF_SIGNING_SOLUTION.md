# Bulletproof macOS Code Signing Solution

## Overview

This bulletproof solution addresses the persistent "resource fork, Finder information, or similar detritus not allowed" error that prevents macOS code signing.

## The Problem

macOS app bundles created by PyInstaller/Briefcase contain:
- Extended attributes (xattrs) on files
- Resource forks (._* files)
- Finder metadata
- Python bytecode files with attributes
- Framework bundles with deep attribute contamination

Standard cleanup methods (`xattr -cr`) often fail because:
- Attributes are deeply embedded in frameworks
- Some files resist standard cleanup
- Python.framework is particularly problematic

## The Bulletproof Solution

### Core Script: `bulletproof_clean_app_bundle.py`

This script uses multiple cleaning methods in order of effectiveness:

1. **Ditto Method** (Recommended)
   - Uses Apple's `ditto --norsrc --noextattr --noacl` command
   - Excludes ALL metadata: resource forks, extended attributes, and ACLs
   - Creates a clean copy then replaces the original
   - Always followed by `xattr -rc` for complete cleanup

2. **Tar Method** 
   - Archives the app without extended attributes
   - Extracts a clean version
   - Nuclear option that strips everything

3. **In-Place Method**
   - Direct cleaning of files
   - Multiple passes with different tools
   - Last resort when copying isn't possible

### Key Features

- **Multiple fallback methods** - If one fails, tries the next
- **Verification** - Tests if the app can be signed after cleaning
- **Safe operation** - Creates backups before modifying
- **Comprehensive** - Handles Python.framework specially
- **Detailed logging** - Shows exactly what's being cleaned

## Usage

### Quick Clean (Recommended)

```bash
# Clean all app bundles automatically
./clean-for-signing.sh
```

### Manual Clean

```bash
# Clean with ditto method (best)
python3 scripts/bulletproof_clean_app_bundle.py --method ditto "build_client/dist/R2MIDI Client.app"

# Try all methods automatically
python3 scripts/bulletproof_clean_app_bundle.py --method auto "build_server/dist/R2MIDI Server.app"

# Verify if an app is clean
python3 scripts/bulletproof_clean_app_bundle.py --verify-only "build_client/dist/R2MIDI Client.app"
```

### Complete Build Process

```bash
# 1. Setup and fix environment
./fix-signing.sh

# 2. Build the apps
./build-all-local.sh --version 0.1.207

# 3. If signing fails, clean and re-sign
./clean-for-signing.sh
./.github/scripts/sign-and-notarize-macos.sh --version 0.1.207
```

## How It Works

### Ditto Method (Primary)

1. Uses `ditto --norsrc --noextattr --noacl` to copy app without ANY metadata
2. Runs `xattr -rc` on the copy to ensure complete cleanup
3. Verifies the copy is clean (should have 0 xattrs)
4. Backs up original and replaces with clean copy
5. Final verification and test signing

### Tar Method (Fallback)

1. Creates tar archive without extended attributes
2. Removes original app
3. Extracts clean version from tar
4. Removes any remaining attributes

### In-Place Method (Last Resort)

1. Removes all metadata files (.DS_Store, ._, __pycache__, etc.)
2. Strips xattrs using multiple methods
3. Special handling for Python.framework
4. Aggressive cleanup of specific attributes

## Why This Works

1. **Proper ditto flags** - Must use `--noextattr` to exclude xattrs (not just `--norsrc`)
2. **xattr -rc** - The `-rc` flag order is more reliable than `-cr`
3. **Multiple passes** ensure no attributes survive
4. **Framework-aware** cleaning handles embedded Python properly
5. **Verification** ensures the result can be signed

### Why Previous Attempts Failed
- `ditto` preserves extended attributes by default
- Must explicitly use `--noextattr` flag
- `xattr -cr` sometimes less effective than `xattr -rc`

## Troubleshooting

### If cleaning still fails:

1. Check file permissions:
   ```bash
   sudo chown -R $(whoami) "path/to/app.app"
   ```

2. Try manual ditto:
   ```bash
   ditto --norsrc "path/to/app.app" "/tmp/clean.app"
   rm -rf "path/to/app.app"
   mv "/tmp/clean.app" "path/to/app.app"
   ```

3. Check for locked files:
   ```bash
   find "path/to/app.app" -flags uchg
   ```

4. Remove quarantine:
   ```bash
   xattr -dr com.apple.quarantine "path/to/app.app"
   ```

### Common Issues

- **Permission errors**: Run with appropriate permissions
- **Symlink issues**: The script handles symlinks properly
- **Framework cleaning**: Python.framework is cleaned specially
- **Backup space**: Ensure enough disk space for backups

## Integration

The bulletproof cleaner is integrated into:
- Build scripts (automatic cleaning before signing)
- CI/CD pipelines (GitHub Actions)
- Manual signing process

## Technical Details

### Files Cleaned
- .DS_Store
- ._ (resource fork files)
- __MACOSX
- .idea, .git, .pytest_cache
- *.pyc, *.pyo, __pycache__
- All extended attributes

### Attributes Removed
- com.apple.quarantine
- com.apple.metadata:*
- com.apple.finder.info
- com.apple.lastuseddate
- All other xattrs

### Special Handling
- Python.framework: Removes all .pyc files and __pycache__
- Symlinks: Preserved correctly
- Permissions: Maintained from original

## Success Metrics

A successfully cleaned app will:
- Have 0 extended attributes
- Pass test signing with `codesign --sign -`
- No "resource fork" errors during actual signing
- Successfully notarize (with valid credentials)

This bulletproof solution has been tested to handle even the most stubborn cases where standard cleanup fails.
