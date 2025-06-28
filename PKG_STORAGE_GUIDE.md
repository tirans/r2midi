# 📦 R2MIDI Signed Package Storage & Build System Guide

## 🎯 **Where Your Signed .pkg Files Are Stored**

### **Primary Location**
```
📁 r2midi/
└── 📦 artifacts/
    ├── R2MIDI-Server-[VERSION].pkg     ← Server installer (signed & notarized)
    ├── R2MIDI-Client-[VERSION].pkg     ← Client installer (signed & notarized)
    ├── SERVER_BUILD_REPORT_[VERSION].md
    └── CLIENT_BUILD_REPORT_[VERSION].md
```

### **Current Files** (as of your last build)
```bash
artifacts/
├── R2MIDI-Client-0.1.213.pkg          # ✅ Your signed client installer
└── CLIENT_BUILD_REPORT_0.1.213.md     # Build report
```

---

## 🔄 **How the Build System Works**

### **Default Build Process (Production)**
```bash
./build-all-local.sh                    # Production build (signed, notarized)
```

**Flow:**
1. `build-all-local.sh` calls `build-server-local.sh` 
2. `build-server-local.sh` calls `scripts/keychain-free-build.sh`
3. `build-client-local.sh` calls `scripts/keychain-free-build.sh`
4. **Result**: Signed, notarized .pkg files in `artifacts/`

### **Build Scripts Hierarchy**
```
build-all-local.sh (main orchestrator)
├── build-server-local.sh 
│   └── scripts/keychain-free-build.sh → artifacts/R2MIDI-Server-[VERSION].pkg
└── build-client-local.sh
    └── scripts/keychain-free-build.sh → artifacts/R2MIDI-Client-[VERSION].pkg
```

---

## 🛡️ **Package Preservation System**

### **Problem Solved**
❌ **Old behavior**: `clean-environment.sh` deleted **ALL** files in `artifacts/`  
✅ **New behavior**: `clean-environment.sh` **preserves** signed .pkg files

### **How It Works**
```bash
# Default: Preserves signed .pkg files
./clean-environment.sh

# Complete cleanup: Removes everything (including .pkg files)
./clean-environment.sh --no-preserve-packages
```

**Preservation Process:**
1. 🔍 Scans `artifacts/` for .pkg files
2. 📦 Moves .pkg files to temporary backup location
3. 🧹 Cleans `artifacts/` directory
4. 📁 Recreates `artifacts/` directory  
5. 🔄 Restores .pkg files
6. ✅ Your signed packages are safe!

---

## 🚀 **Build Commands & Results**

### **Production Builds (Default)**
```bash
# Build everything (signed, notarized)
./build-all-local.sh

# Build with specific version
./build-all-local.sh --version 1.2.3

# Clean production build
./build-all-local.sh --clean
```
**Result**: `artifacts/R2MIDI-Server-[VERSION].pkg` & `artifacts/R2MIDI-Client-[VERSION].pkg`

### **Development Builds**
```bash
# Fast development build (unsigned)
./build-all-local.sh --dev

# Individual component builds
./build-server-local.sh --dev
./build-client-local.sh --dev
```
**Result**: `.app` bundles in `build_server/dist/` and `build_client/dist/`

### **Build Options**
| Option | Description | Result |
|--------|-------------|--------|
| **(default)** | Production build | Signed, notarized .pkg |
| `--dev` | Development build | Unsigned .app only |
| `--no-sign` | Skip code signing | Unsigned .pkg |
| `--no-notarize` | Skip notarization | Signed but not notarized .pkg |
| `--clean` | Clean previous builds | Fresh build environment |

---

## 📁 **Complete File Locations**

### **Build Artifacts**
```
📁 r2midi/
├── 📦 artifacts/                       ← SIGNED .PKG FILES (PRESERVED)
│   ├── R2MIDI-Server-[VERSION].pkg     ← Install with: sudo installer -pkg
│   ├── R2MIDI-Client-[VERSION].pkg     ← Install with: sudo installer -pkg
│   ├── SERVER_BUILD_REPORT_[VERSION].md
│   ├── CLIENT_BUILD_REPORT_[VERSION].md
│   └── BUILD_REPORT_[VERSION].md
├── 📁 build_server/                    ← Server build workspace
│   └── dist/R2MIDI Server.app          ← Server .app bundle
├── 📁 build_client/                    ← Client build workspace
│   └── dist/R2MIDI Client.app          ← Client .app bundle
└── 📁 logs/                            ← Build logs
```

### **Installation Targets**
```
📁 /Applications/
├── R2MIDI Server.app                   ← Installed by server .pkg
└── R2MIDI Client.app                   ← Installed by client .pkg
```

---

## ⚡ **Quick Commands**

### **Build & Install**
```bash
# 1. Build everything (creates signed .pkg files)
./build-all-local.sh

# 2. Install server
sudo installer -pkg artifacts/R2MIDI-Server-*.pkg -target /

# 3. Install client  
sudo installer -pkg artifacts/R2MIDI-Client-*.pkg -target /

# 4. Start applications
open "/Applications/R2MIDI Server.app"
open "/Applications/R2MIDI Client.app"
```

### **Environment Management**
```bash
# Clean but preserve .pkg files (default)
./clean-environment.sh

# Complete clean (removes .pkg files too)
./clean-environment.sh --no-preserve-packages

# Test package preservation
./test-pkg-preservation.sh
```

### **Verification**
```bash
# Check package signatures
pkgutil --check-signature artifacts/*.pkg

# Check app signatures
codesign --verify --deep --strict --verbose=2 "/Applications/R2MIDI Server.app"
codesign --verify --deep --strict --verbose=2 "/Applications/R2MIDI Client.app"

# Check Gatekeeper approval
spctl --assess --type install artifacts/*.pkg
spctl --assess --type exec "/Applications/R2MIDI Server.app"
```

---

## 🔧 **Troubleshooting**

### **If .pkg Files Are Missing**
1. **Check if they were moved during cleanup**:
   ```bash
   find /tmp -name "*r2midi*pkg*" 2>/dev/null
   ```

2. **Rebuild with explicit preservation**:
   ```bash
   ./clean-environment.sh              # This should preserve .pkg files
   ./build-all-local.sh --version X.Y.Z
   ```

3. **Force complete rebuild**:
   ```bash
   ./clean-environment.sh --no-preserve-packages  # Clean everything
   ./build-all-local.sh --clean --version X.Y.Z   # Fresh build
   ```

### **Build Script Issues**
- **Make scripts executable**: `chmod +x *.sh scripts/*.sh`
- **Check dependencies**: `./build-all-local.sh` will verify tools
- **View build logs**: Check `logs/` directory for detailed output

---

## 📋 **Summary**

✅ **Signed .pkg files are stored in**: `artifacts/`  
✅ **Files are preserved** during environment cleanup  
✅ **Production builds create signed, notarized packages** by default  
✅ **Use `sudo installer -pkg artifacts/[FILE].pkg -target /`** to install  
✅ **Apps install to `/Applications/`**  

🎉 **Your signed packages are safe and ready for distribution!**
