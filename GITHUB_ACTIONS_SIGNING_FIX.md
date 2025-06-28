# GitHub Actions Signing Fix

## The Problem

Your GitHub Actions workflow on the self-hosted runner couldn't find the `bulletproof_clean_app_bundle.py` script, causing it to fall back to the old cleaning method which doesn't properly remove extended attributes.

## What I Fixed

### 1. Enhanced Script Discovery
Updated `.github/scripts/sign-and-notarize-macos.sh` to:
- Better path resolution with debugging output
- Try multiple locations for the cleaning script
- Show exactly where it's looking for the script

### 2. Made Python Scripts Executable
Updated `.github/workflows/build-macos.yml` to:
- `chmod +x scripts/*.py` - Make all Python scripts executable
- Specifically ensure `bulletproof_clean_app_bundle.py` is executable
- Add verification step to check if cleaning scripts exist

### 3. Emergency Fallback Cleaner
Created `.github/scripts/emergency-clean-app.sh`:
- Shell script that doesn't require Python
- Uses `ditto --norsrc --noextattr --noacl` for cleaning
- Fallback when Python script isn't available

### 4. Diagnostic Tools
Added `test-signing-environment.sh`:
- Checks repository structure
- Verifies cleaning scripts exist
- Tests if ditto supports required flags
- Shows extended attribute counts on app bundles

### 5. Enhanced Standard Cleanup
When bulletproof script isn't found, the signing script now:
- Uses `xattr -rc` (not -cr)
- Removes Python cache files (*.pyc, __pycache__)
- Tries the emergency shell cleaner
- More aggressive xattr removal

## How to Use

### Local Testing
```bash
# Run the diagnostic
./test-signing-environment.sh

# Clean apps manually
./clean-for-signing.sh
```

### In GitHub Actions
The workflow will now:
1. Make all scripts executable (including Python)
2. Verify cleaning scripts exist
3. Use bulletproof cleaner if found
4. Fall back to emergency cleaner if needed
5. Show detailed debugging info

## Key Commands That Work

```bash
# Proper ditto usage (must include all three flags)
ditto --norsrc --noextattr --noacl source destination

# Correct xattr usage
xattr -rc /path/to/app.app
```

## Next Steps

1. Commit these changes
2. Push to trigger GitHub Actions
3. Check the new debug output to see:
   - If the script is found
   - Where it's looking
   - What cleaning method is used
   - Final xattr count

The build should now properly clean the app bundles before signing!
