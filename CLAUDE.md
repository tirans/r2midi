# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

R2MIDI is a MIDI 2.0 Patch Selection Application with a client-server architecture:
- **Server**: FastAPI-based REST API for MIDI device management and preset operations
- **Client**: PyQt6-based GUI for browsing and selecting MIDI presets
- **Architecture**: Separate components that can be built independently or together

## Development Commands

### Building the Application

**New macOS-Pkg-Builder System**:
```bash
# Build both components with signing and notarization
./build-all-local.sh

# Build specific component
./build-all-local.sh --component server
./build-all-local.sh --component client

# Development build (unsigned, faster)
./build-all-local.sh --no-sign

# Skip notarization (signed but not notarized)
./build-all-local.sh --no-notarize

# Specify version
./build-all-local.sh --version 1.2.3
```

**Direct Python Builder**:
```bash
# Use the Python builder directly for more control
python3 build-pkg.py --help
python3 build-pkg.py --component both
python3 build-pkg.py --component server --no-sign
python3 build-pkg.py --component client --version 1.2.3 --no-notarize
```

**Testing the Build System**:
```bash
# Test development build (unsigned)
./test-simplified-build.sh --dev

# Test specific component
./test-simplified-build.sh --component server --dev

# Test production build (requires certificates)
./test-simplified-build.sh
```

**Build System Exit Codes**:
- `0`: Success (all requirements met)
- `1`: PKG creation failed
- `2`: Signing required but failed
- `3`: Notarization required but failed  
- `4`: Certificate setup failed

The build system now properly fails when signing/notarization requirements aren't met, instead of claiming success for unsigned packages when signing was requested.

### Testing

**Component-Specific Testing** (uses virtual environments):
```bash
# All tests in component-specific environments
./test-all.sh

# Server tests only (uses build_venv_server)
./test-server.sh

# Client tests only (uses build_venv_client)  
./test-client.sh

# With additional pytest options
./test-server.sh --cov=server --cov-report=html
./test-client.sh -v --tb=short
```

**Direct pytest** (legacy, single environment):
```bash
# All tests with markers
python -m pytest tests/ -v

# Server tests only
python -m pytest tests/ -m server -v

# Client tests only
python -m pytest tests/ -m client -v

# Specific test modules
python -m pytest tests/unit/server/ -v
python -m pytest tests/unit/r2midi_client/ -v
```

### Development Setup

**Virtual Environments** (automatically managed by build scripts):
```bash
# Server environment: build_venv_server/
# Client environment: build_venv_client/
```

**Manual Setup**:
```bash
# Install main dependencies
pip install -r requirements.txt

# Install development dependencies
pip install -e ".[dev]"

# Install test dependencies
pip install -e ".[test]"
```

### Running the Application

**Server**:
```bash
# From server directory
cd server && python main.py

# Or from root
python -c "import sys; sys.path.append('server'); from main import main; main()"
```

**Client**:
```bash
# From client directory
cd r2midi_client && python main.py

# Or from root
python -c "import sys; sys.path.append('r2midi_client'); from main import main; main()"
```

## Project Architecture

### Directory Structure

```
r2midi/
├── server/                     # FastAPI server component
│   ├── main.py                # Server entry point and FastAPI app
│   ├── device_manager.py      # MIDI device scanning and management
│   ├── midi_utils.py          # MIDI utility functions
│   ├── models.py              # Pydantic data models
│   ├── git_operations.py      # Git submodule operations
│   ├── ui_launcher.py         # GUI launcher integration
│   └── midi-presets/          # Git submodule (device definitions)
├── r2midi_client/             # PyQt6 client component (note: underscore)
│   ├── main.py               # Client entry point
│   ├── api_client.py         # HTTP client with caching and retry logic
│   ├── config.py             # Configuration management
│   ├── models.py             # Client data models
│   ├── performance.py        # Performance monitoring
│   ├── shortcuts.py          # Keyboard shortcuts
│   ├── themes.py             # Dark/light theme management
│   └── ui/                   # UI components
│       ├── main_window.py    # Main application window
│       ├── device_panel.py   # MIDI device selection panel
│       ├── preset_panel.py   # Preset browsing panel
│       ├── edit_dialog.py    # Edit dialog for presets
│       └── preferences_dialog.py # Settings dialog
├── scripts/                   # Build and utility scripts
├── tests/                    # Test suite
│   ├── unit/server/          # Server unit tests
│   └── unit/r2midi_client/   # Client unit tests
└── build-*.sh               # Build scripts
```

### Key Components

**Server (FastAPI)**:
- `main.py`: FastAPI app with REST endpoints (`/devices`, `/presets`, `/midi_port`, `/preset`)
- `device_manager.py`: Parallel MIDI device scanning, caching with 1-hour timeout
- `midi_utils.py`: MIDI operations using python-rtmidi and external SendMIDI tool
- `git_operations.py`: Manages midi-presets submodule synchronization

**Client (PyQt6)**:
- `api_client.py`: HTTP client with intelligent caching, retry logic, and offline mode
- `ui/main_window.py`: Main window with device and preset panels
- `performance.py`: Real-time CPU/memory monitoring for debug mode
- `themes.py`: Dark/light theme system with persistent settings

### Build System Architecture

**New macOS-Pkg-Builder Based System**:
- **Primary Builder**: `build-pkg.py` - Python script using macOS-Pkg-Builder library
- **No py2app**: Simplified app bundle creation without py2app complications
- **Direct PKG Creation**: Uses macOS-Pkg-Builder for signed and notarized packages
- **Dual Certificate Support**: Local P12 files and GitHub Actions secrets
- **Clean Architecture**: No complex setup.py files in components

**Certificate Management**:
- **Local Development**: 
  - Certificates: `apple_credentials/certificates/developerID_application.p12`, `developerID_installer.p12`
  - Configuration: `apple_credentials/config/app_config.json`
  - Password: `"p12_password": "x2G2srk2RHtp"`
- **GitHub Actions**:
  - Environment variables: `APPLE_DEVELOPER_ID_APPLICATION_CERT`, `APPLE_DEVELOPER_ID_INSTALLER_CERT`
  - Credentials: `APPLE_CERT_PASSWORD`, `APPLE_ID`, `APPLE_ID_PASSWORD`, `APPLE_TEAM_ID`
- **Automatic Cleanup**: Temporary keychains are created and cleaned up automatically

### Configuration Management

**pyproject.toml files**:
- Root: Combined project configuration with Briefcase setup
- `server/pyproject.toml`: Server-specific dependencies and Briefcase config
- `r2midi_client/pyproject.toml`: Client-specific dependencies and Briefcase config

**Version Management**:
- Version stored in `server/version.py` 
- Automatically incremented by GitHub Actions on master branch pushes
- Build scripts auto-detect version from pyproject.toml or version.py

## Important Development Notes

### Naming Convention

The project uses different naming conventions:
- **Code directories**: `r2midi_client` (underscore) 
- **Built artifacts**: `r2midi-client` (hyphen)
- This is due to Python packaging vs Briefcase naming requirements

### Security Considerations

- Path validation utilities in `server/main.py` prevent path traversal attacks
- Comprehensive secret masking in GitHub Actions
- No hardcoded credentials in codebase
- Certificate management through GitHub secrets and local keychain

### Performance Optimizations

- **Server**: 1-hour API response caching, parallel device scanning
- **Client**: Debounced UI controls (300ms default), lazy loading, intelligent caching
- **Build**: Virtual environment preservation, incremental builds

### Testing Strategy

- Unit tests for both server and client components
- PyQt testing with pytest-qt
- Async testing with pytest-asyncio
- Coverage reporting with pytest-cov

### MIDI Integration

- Uses python-rtmidi for device detection
- External SendMIDI tool for actual MIDI commands
- Supports multiple MIDI ports and channels
- Device definitions stored in midi-presets git submodule

This architecture supports both local development and production builds with comprehensive signing, notarization, and cross-platform compatibility.