# Refactored Signing System

## Overview

The complex `sign-notarize.sh` script has been broken down into smaller, focused scripts that are easier to maintain, debug, and understand.

## New Architecture

### 1. **app-cleaner.sh** 🧹
**Purpose**: Clean app bundles before signing
**Features**:
- Removes `.DS_Store`, `._*`, and `__MACOSX` files
- Cleans Python cache (`*.pyc`, `__pycache__`)
- Removes extended attributes using multiple methods
- Handles `com.apple.provenance` attributes
- Uses `ditto` to create clean copies
- Provides detailed progress reporting

**Usage**: `./app-cleaner.sh "MyApp.app"`

### 2. **codesign.sh** 🔐
**Purpose**: Code sign app bundles step by step
**Features**:
- Signs dynamic libraries (`.dylib`) first
- Signs Python extensions (`.so`) files
- Signs frameworks in correct order
- Signs main executable with entitlements
- Signs entire app bundle with deep signing
- Verifies signature integrity
- Clear progress reporting for each step

**Usage**: `./codesign.sh "MyApp.app" "Developer ID Application: Name" "entitlements.plist"`

### 3. **notarize.sh** 📤
**Purpose**: Handle notarization process
**Features**:
- Supports both `notarytool` (modern) and `altool` (legacy)
- Creates temporary ZIP for app bundles
- Automatic credential handling
- Staples notarization tickets
- Graceful fallback if credentials unavailable
- Clear status reporting

**Usage**: `./notarize.sh "MyApp.app"`

### 4. **sign-and-notarize.sh** 🚀
**Purpose**: Main orchestrator script
**Features**:
- Finds and validates signing certificates
- Creates entitlements files
- Discovers targets automatically
- Orchestrates cleaning → signing → notarization
- Handles both `.app` and `.pkg` files
- Comprehensive error handling and reporting
- Support for dev builds (skip notarization)

**Usage**: `./sign-and-notarize.sh --version 1.0.0 [--dev] [--skip-notarize]`

### 5. **handle-attributes.sh** 🔧
**Purpose**: Handle stubborn `com.apple.provenance` attributes
**Features**:
- Multiple removal strategies
- File recreation to bypass attributes
- Graceful handling of system-protected attributes
- Non-blocking (won't fail build)

**Usage**: `./handle-attributes.sh "MyApp.app"`

## Benefits of New Architecture

### ✅ **Modularity**
- Each script has a single, clear responsibility
- Easy to test individual components
- Can be used independently or together

### ✅ **Debugging**
- Clear error messages at each step
- Easy to identify which step failed
- Can run individual scripts for testing

### ✅ **Maintenance**
- Smaller, focused code files
- Easier to understand and modify
- Less chance of introducing bugs

### ✅ **Flexibility**
- Can skip individual steps if needed
- Easy to add new features
- Support for different build types

### ✅ **Reliability**
- Better error handling
- Graceful fallbacks
- Detailed progress reporting

## Integration with Build Scripts

The build scripts now automatically detect and prefer the new scripts:

```bash
# Build scripts check for new scripts first
if [ -f "../.github/scripts/sign-and-notarize.sh" ]; then
    # Use new modular system
    ./.github/scripts/sign-and-notarize.sh --version $VERSION
elif [ -f "../.github/scripts/sign-notarize.sh" ]; then
    # Fall back to old complex system
    ./.github/scripts/sign-notarize.sh --version $VERSION
fi
```

## Troubleshooting

### Common Issues and Solutions

#### **Code Signing Fails with "resource fork" Error**
**Solution**: The `app-cleaner.sh` specifically handles this
```bash
./app-cleaner.sh "MyApp.app"
./codesign.sh "MyApp.app" "Developer ID Application: Name" "entitlements.plist"
```

#### **com.apple.provenance Attributes**
**Solution**: Use the specialized handling script
```bash
./handle-attributes.sh "MyApp.app"
```

#### **Missing Certificates**
**Solution**: The orchestrator script provides clear error messages
```bash
./sign-and-notarize.sh --version 1.0.0
# Will show: "❌ No Developer ID Application certificate found"
```

#### **Notarization Fails**
**Solution**: Use dev mode to skip notarization
```bash
./sign-and-notarize.sh --version 1.0.0 --dev
```

## Migration Strategy

### ✅ **Immediate Benefits**
- Build scripts automatically use new system
- Old scripts remain as fallback
- No configuration changes needed

### ✅ **Testing**
- Test individual components separately
- Run with `--dev` flag for faster iteration
- Easy to compare old vs new results

### ✅ **Rollback**
- Simply remove/rename new scripts
- Build will automatically fall back to old system
- No data loss or configuration changes

## Performance Improvements

### **Before (Old System)**
- Single monolithic script (~1000+ lines)
- Complex error handling
- Difficult to debug failures
- All-or-nothing approach

### **After (New System)**
- 5 focused scripts (~200 lines each)
- Clear step-by-step process
- Easy to identify and fix issues
- Granular control over each step

## Command Examples

### **Basic Usage**
```bash
# Sign and notarize everything
./sign-and-notarize.sh --version 1.0.0

# Development build (no notarization)
./sign-and-notarize.sh --version 1.0.0 --dev

# Skip notarization only
./sign-and-notarize.sh --version 1.0.0 --skip-notarize
```

### **Individual Steps**
```bash
# Clean an app bundle
./app-cleaner.sh "dist/MyApp.app"

# Sign only (after cleaning)
./codesign.sh "dist/MyApp.app" "Developer ID Application: Name" "entitlements.plist"

# Notarize only (after signing)
./notarize.sh "dist/MyApp.app"
```

### **Troubleshooting**
```bash
# Handle provenance attributes specifically
./handle-attributes.sh "dist/MyApp.app"

# Check what the cleaner would do
./app-cleaner.sh "dist/MyApp.app" # Shows detailed output
```

This refactored system should resolve the `com.apple.provenance` attribute issues and provide a much more reliable signing process! 🎉
