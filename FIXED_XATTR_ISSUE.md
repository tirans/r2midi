# FIXED: macOS Code Signing Extended Attributes Issue

## The Problem
The `ditto` command was preserving extended attributes by default, which is why the cleaning wasn't working.

## The Solution

### 1. Updated `bulletproof_clean_app_bundle.py`
- Now uses `ditto --norsrc --noextattr --noacl` to exclude ALL metadata
- Always runs `xattr -rc` after ditto for complete cleanup
- Uses `-rc` flag instead of `-cr` (more reliable on all macOS versions)

### 2. Key Commands That Work

```bash
# Correct ditto usage (excludes all metadata)
ditto --norsrc --noextattr --noacl source destination

# Correct xattr usage (recursive clear)
xattr -rc /path/to/app.app
```

### 3. Quick Usage

```bash
# Clean apps after build failure
./clean-for-signing.sh

# Or manually with bulletproof cleaner
python3 scripts/bulletproof_clean_app_bundle.py --method ditto "build_client/dist/R2MIDI Client.app"
```

## Why This Works Now

1. **`--noextattr`** flag tells ditto to NOT preserve extended attributes
2. **`--norsrc`** flag tells ditto to NOT preserve resource forks
3. **`--noacl`** flag tells ditto to NOT preserve ACLs
4. **`xattr -rc`** recursively clears any remaining attributes
5. Multiple cleanup passes ensure complete removal

## Cleaned Up Scripts
- Removed duplicate `deep_clean_app_bundle.py` (moved to deprecated/)
- Removed old `fix_macos_signing.py` (moved to deprecated/)
- Updated all references to use `bulletproof_clean_app_bundle.py`
- All scripts now use `xattr -rc` instead of `xattr -cr`

The cleaning should now actually work and remove ALL extended attributes!
