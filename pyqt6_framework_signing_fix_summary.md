# PyQt6 Framework Signing Fix Summary

## Issue Description
The macOS PKG creation and notarization process was failing with signing errors for PyQt6/Qt6 frameworks. The notarization logs showed multiple errors like:

```json
{
  "severity": "error",
  "code": null,
  "path": "R2MIDI Server-0.1.178.dmg/R2MIDI Server.app/Contents/Resources/app_packages/PyQt6/Qt6/lib/QtQuick3DPhysicsHelpers.framework/Versions/A/QtQuick3DPhysicsHelpers",
  "message": "The binary is not signed with a valid Developer ID certificate.",
  "docUrl": "https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution/resolving_common_notarization_issues#3087721",
  "architecture": "arm64"
},
{
  "severity": "error",
  "code": null,
  "path": "R2MIDI Server-0.1.178.dmg/R2MIDI Server.app/Contents/Resources/app_packages/PyQt6/Qt6/lib/QtQuick3DPhysicsHelpers.framework/Versions/A/QtQuick3DPhysicsHelpers",
  "message": "The signature does not include a secure timestamp.",
  "docUrl": "https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution/resolving_common_notarization_issues#3087733",
  "architecture": "arm64"
}
```

Similar errors were occurring for other Qt frameworks like:
- QtLabsQmlModels.framework
- QtQuickControls2Universal.framework
- And potentially other Qt frameworks

## Root Cause Analysis

### The Problem
The existing signing process in `.github/scripts/create-macos-pkg.sh` was finding and attempting to sign framework bundles, but it wasn't properly handling the internal structure of Qt frameworks.

### Qt Framework Structure
Qt frameworks have a specific internal structure:
```
QtFramework.framework/
├── Versions/
│   └── A/
│       ├── QtFramework          # ← Main executable (needs signing)
│       ├── Resources/
│       └── Headers/
├── QtFramework -> Versions/Current/QtFramework
└── Resources -> Versions/Current/Resources
```

### Why the Original Process Failed
1. **Surface-level signing**: The original process only signed the framework bundle itself
2. **Missing internal executables**: The main executable inside `Versions/A/` was not being signed
3. **No secure timestamps**: Internal components weren't getting proper timestamp signatures
4. **Inside-out violation**: Framework bundles were signed before their internal components

## Solution Implemented

### Enhanced Framework Signing Logic
Modified the framework signing section in `.github/scripts/create-macos-pkg.sh` to include special handling for Qt frameworks:

```bash
# Special handling for Qt frameworks (PyQt6/Qt6)
if [[ "$(basename "$framework")" == Qt* ]] || [[ "$framework" == *PyQt6/Qt6* ]]; then
    echo "🎯 Special Qt framework signing: $(basename "$framework")"
    
    # Sign internal executables in Qt frameworks first (inside-out approach)
    # Qt frameworks have structure: Framework.framework/Versions/A/Framework
    local framework_name=$(basename "$framework" .framework)
    local framework_executable="$framework/Versions/A/$framework_name"
    
    if [ -f "$framework_executable" ]; then
        echo "  🔗 Signing Qt framework executable: $framework_name"
        codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp "$framework_executable"
    fi
    
    # Sign any other executables or dylibs inside the framework
    find "$framework" -type f \( -name "*.dylib" -o -perm +111 \) -not -path "*/Headers/*" -not -path "*/Resources/*" | while read inner_file; do
        if [ -f "$inner_file" ] && file "$inner_file" | grep -q "Mach-O"; then
            echo "  🔗 Signing Qt framework component: $(basename "$inner_file")"
            codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp "$inner_file"
        fi
    done
fi

# Sign the framework bundle itself (this works for both Qt and regular frameworks)
codesign --force --sign "$APPLICATION_SIGNING_IDENTITY" --options runtime --timestamp "$framework"
```

### Key Improvements

1. **Qt Framework Detection**: Automatically detects Qt frameworks by name pattern or path
2. **Inside-Out Signing**: Signs internal executables before the framework bundle
3. **Comprehensive Coverage**: Signs all Mach-O files within the framework
4. **Secure Timestamps**: Ensures all components get proper timestamp signatures
5. **Developer ID Certificates**: Uses the proper APPLICATION_SIGNING_IDENTITY for all components

### Signing Order
The enhanced process follows proper inside-out signing:
1. Sign internal framework executable (`Versions/A/QtFramework`)
2. Sign any other dylibs or executables within the framework
3. Sign the framework bundle itself
4. Continue with normal app bundle signing

## Expected Results

### Before Fix
- ❌ Qt framework internal executables unsigned
- ❌ Missing secure timestamps on Qt components
- ❌ Notarization failures for PyQt6 applications
- ❌ "The binary is not signed with a valid Developer ID certificate" errors

### After Fix
- ✅ All Qt framework components properly signed with Developer ID
- ✅ Secure timestamps included on all Qt components
- ✅ Notarization should succeed without Qt framework errors
- ✅ PyQt6 applications ready for distribution

## Files Modified

- `.github/scripts/create-macos-pkg.sh`: Enhanced framework signing logic with Qt-specific handling

## Testing Recommendations

1. **Build Test**: Run a complete PKG build with a PyQt6 application
2. **Signing Verification**: Check that Qt frameworks are properly signed:
   ```bash
   codesign --verify --deep --strict path/to/QtFramework.framework
   ```
3. **Notarization Test**: Submit PKG for notarization and verify no Qt framework errors
4. **Distribution Test**: Install and run the PKG to ensure functionality is preserved

## Technical Details

### Framework Detection Logic
- Detects frameworks with names starting with "Qt"
- Detects frameworks in PyQt6/Qt6 paths
- Maintains compatibility with non-Qt frameworks

### Signing Parameters
- `--force`: Overwrites any existing signatures
- `--sign "$APPLICATION_SIGNING_IDENTITY"`: Uses Developer ID Application certificate
- `--options runtime`: Enables hardened runtime for notarization
- `--timestamp`: Includes secure timestamp from Apple's servers

### Performance Impact
- Minimal impact: Qt framework detection is fast
- Parallel processing: Maintains existing batch processing for performance
- Selective enhancement: Only affects Qt frameworks, others unchanged

## Conclusion

This fix addresses the root cause of PyQt6 framework signing issues by implementing proper inside-out signing for Qt frameworks. The solution ensures all Qt framework components are signed with valid Developer ID certificates and secure timestamps, enabling successful notarization and distribution of PyQt6-based macOS applications.