# R2MIDI - MIDI Preset Selection System

A MIDI preset selection application and user midi hardware devices, preset definition with planned sharing via https://github.com/tirans/midi-presets project.

## Overview

- R2MIDI is a PyQt6-based application that provides an intuitive interface for browsing and selecting MIDI presets across multiple devices and manufacturers.
- The app sends the same midi selection command to the device and another port (probably the sequencer for recording)
##  Be aware: 
- No user data is collected for advertising etc., however, the application uses the https://github.com/tirans/midi-presets project which stored midi capable devices infromation, currently describing midi patches related information. 
- The target is to enable the user to add/sync midi devices automatically to this repo.

## Key Features

### Core Functionality
- **Device Management**: Browse devices by manufacturer with cascading selection
- **Preset Selection**: View and select presets with category filtering
- **MIDI Control**: Send preset changes to MIDI devices with configurable ports and channels
- **Community Folders**: Support for community-contributed preset collections
- **Multi-Device Support**: Control multiple MIDI devices simultaneously
- **Sequencer Integration**: Optional routing to a sequencer port

### Performance Features

#### 🚀 Performance Optimizations
- **Intelligent Caching**: 1-hour cache for API responses significantly reduces server load
- **Retry Logic**: Automatic retry with exponential backoff for failed requests
- **Debounced Controls**: Prevents rapid API calls during UI interactions
- **Performance Monitoring**: Real-time CPU and memory usage tracking in debug mode
- **Lazy Loading**: Efficient handling of large preset datasets
- **Parallel Processing**: Multi-threaded device scanning and preset loading

#### 🎨 User Interface
- **Dark Mode**: Professional dark theme with full UI integration
- **Loading Indicators**: Visual feedback for all async operations
- **Search Functionality**: Real-time preset search with debouncing
- **Favorites System**: Mark and filter favorite presets
- **Keyboard Shortcuts**: Comprehensive keyboard navigation
- **Category Colors**: Visual categorization with persistent color assignments
- **Offline Mode**: Work without syncing to remote repositories

#### ⚙️ Configuration
- **Preferences Dialog**: Comprehensive settings management
- **Persistent State**: Remembers selections between sessions
- **Configuration Export/Import**: Share settings between installations
- **Debug Mode**: Advanced logging and performance monitoring

#### ⌨️ Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Send Preset | Enter/Return |
| Search Presetes | Ctrl+F |
| Clear Search | Esc |
| Toggle Favorites | Ctrl+D |
| Refresh Data | F5 |
| Preferences | Ctrl+, |
| Quit | Ctrl+Q |
| Next/Previous Preset | ↓/↑ or J/K |
| Next/Previous Category | →/← or L/H |
| MIDI Channel Up/Down | Ctrl+↑/↓ |

## Installation

R2MIDI can be installed in multiple ways:

### Pre-built Executables

Download the latest pre-built executable for your platform from the [GitHub Releases](https://github.com/tirans/r2midi/releases) page:

- **Windows**: Download `r2midi-windows.exe`
- **macOS**: Download `r2midi-macos`
- **Linux**: Download `r2midi-linux`

The executables are self-contained and don't require Python or any dependencies to be installed.

### PyPI Installation

Available on PyPI: https://pypi.org/project/r2midi

```bash
pip install r2midi
r2midi
```

### Manual Installation

#### Requirements

- Python 3.8+
- PyQt6
- httpx
- psutil
- [SendMIDI](https://github.com/gbevin/SendMIDI) command-line tool
- MIDI devices connected to your computer

#### Installation Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/tirans/r2midi.git
   cd r2midi
   ```

2. Initialize and update the midi-presets submodule:
   ```bash
   git submodule init
   git submodule update --init --recursive
   ```

   If you encounter issues with the submodule, you can also manually clone it:
   ```bash
   git clone https://github.com/tirans/midi-presets.git midi-presets
   ```

3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

   Or using the pyproject.toml:
   ```bash
   pip install -e .
   ```

4. Run the application:
   ```bash
   python main.py
   ```

## Configuration

### Environment Variables

Create a `.env` file in the project root with the following variables:

```
PORT=7777  # The port for the API server (default: 7777)
```

### Application Configuration

Configuration is stored in `~/.r2midi_config.json` with the following options:

```json
{
    "server_url": "http://localhost:7777",
    "cache_timeout": 3600,
    "dark_mode": false,
    "enable_favorites": true,
    "enable_search": true,
    "enable_keyboard_shortcuts": true,
    "debounce_delay_ms": 300,
    "max_presets_display": 1000,
    "sync_enabled": true
}
```

The `sync_enabled` option controls whether the application syncs with remote repositories. Set to `false` to enable offline mode.

### Device Configuration

Device definitions are stored as JSON files in the `devices` folder. Each device file should follow this format:

```json
{
  "name": "Device Name",
  "midi_ports": {
    "main": "MIDI Port Name",
    "alternate": "Alternative MIDI Port Name"
  },
  "midi_channels": {
    "main": 1,
    "alternate": 2
  },
  "presets": [
    {
      "preset_name": "Preset 1",
      "category": "Category",
      "characters": ["warm", "bright"],
      "cc_0": 0,
      "pgm": 1
    },
    {
      "preset_name": "Preset 2",
      "category": "Another Category",
      "characters": ["dark", "deep"],
      "cc_0": 0,
      "pgm": 2
    }
  ]
}
```

An example device file for the Expressivee Osmose is included in the `devices` folder.

## Usage

### Starting the Application

Run the main application:

```bash
python main.py
```

This will:
1. Start the API server on the configured port (default: 7777)
2. Scan for connected MIDI devices
3. Launch the GUI client

### Using the GUI

The GUI is divided into two main panels:

#### Device Panel (Top)

- **MIDI Output Port**: Select the MIDI port to send commands to
- **MIDI Channel**: Select the MIDI channel (1-16)
- **Sequencer Port**: Optionally select a secondary port to send the same commands to (useful for recording in a DAW)

#### Preset Panel (Bottom)

- Browse presets by category
- Search for presets by name
- Select a preset to send to the device
- Mark favorites for quick access
- Filter by characteristics or categories

#### Sending MIDI Commands

1. Select a MIDI output port and channel in the Device Panel
2. Select a preset in the Preset Panel
3. Click the "Send MIDI" button or press Enter to send the program change to your device

### API Endpoints

The application provides a REST API that can be used by other applications:

- `GET /devices` - Get a list of all devices
- `GET /presets` - Get a list of all presets
- `GET /midi_port` - Get a list of available MIDI ports
- `POST /preset` - Send a preset to a MIDI port/channel
- `GET /git/sync` - Sync the midi-presets submodule

Example API usage with curl:

```bash
# Get all devices
curl http://localhost:7777/devices

# Get all presets
curl http://localhost:7777/presets

# Get MIDI ports
curl http://localhost:7777/midi_port

# Send a preset
curl -X POST http://localhost:7777/preset \
  -H "Content-Type: application/json" \
  -d '{"preset_name": "Preset Name", "midi_port": "MIDI Port Name", "midi_channel": 1}'

# Sync the midi-presets submodule
curl http://localhost:7777/git/sync
```

## Architecture

### Naming Convention Note

The project uses two different naming conventions:
- The Python code for the client is located in the `r2midi_client` directory (with an underscore)
- The built project artifacts are named `r2midi-client` (with a hyphen) due to Briefcase packaging convention

This distinction is important when working with the codebase versus referencing the built applications.

### Module Structure

```
r2midi/
├── r2midi_client/              # Client code (note the underscore in directory name)
│   ├── api_client.py            # Enhanced API client with caching
│   ├── config.py                # Configuration management
│   ├── models.py                # Data models
│   ├── performance.py           # Performance monitoring
│   ├── shortcuts.py             # Keyboard shortcuts
│   ├── themes.py                # Theme management
│   └── ui/
│       ├── device_panel.py      # Device selection with debouncing and offline mode
│       ├── main_window.py       # Main application window
│       ├── preset_panel.py       # Preset display with search and persistent category colors
│       ├── edit_dialog.py       # Edit dialog for manufacturers, devices, and presets
│       └── preferences_dialog.py # Settings management
├── midi-presets/                # Git submodule containing device definitions
│   └── devices/                 # Device definitions and presets
├── main.py                      # Main entry point and API server
├── device_manager.py            # Handles device scanning and management with parallel processing
├── git_operations.py            # Handles git submodule operations
├── midi_utils.py                # MIDI utility functions
├── models.py                    # Data models
├── ui_launcher.py               # Launches the GUI client
├── version.py                   # Contains the current version of the application
├── pre-commit                   # Git hook script to increment version on commit
├── .github/
│   └── workflows/               # GitHub Actions workflows for CI/CD and executable building
└── tests/
    ├── unit/                    # Unit tests
    └── temp/                    # Temporary test files
```

### Key Components

#### CachedApiClient
- Implements caching with configurable timeout
- Automatic retry with exponential backoff
- Persistent UI state management
- Thread-safe async operations

#### DebouncedComboBox
- Prevents rapid selection changes from triggering API calls
- Configurable delay (default: 300ms)
- Maintains smooth UI responsiveness

#### PerformanceMonitor
- Real-time CPU and memory tracking
- Operation timing with statistics
- Performance summary logging
- Context managers for easy integration

#### ThemeManager
- Light and dark theme support
- Comprehensive widget styling
- Native look and feel
- Smooth theme transitions

## Testing

Run the comprehensive test suite:

```bash
# Install test dependencies
pip install -e ".[test]"

# Run all tests
python -m pytest tests/ -v

# Run specific test modules
python -m pytest tests/test_enhanced_functionality.py -v
python -m pytest tests/test_comprehensive_features.py -v

# Run with coverage
python -m pytest tests/ --cov=r2midi_client --cov-report=html
```

## Performance

### Benchmarks
- **Cache Hit Rate**: >90% for repeated operations
- **API Response Time**: <100ms with caching (vs 500ms+ without)
- **UI Responsiveness**: <16ms frame time (60+ FPS)
- **Memory Usage**: ~50MB baseline, ~100MB with 1000+ presets

### Optimization Tips
1. Enable caching in preferences (default: on, now with 1-hour timeout)
2. Adjust debounce delay for your network speed
3. Use lazy loading for large preset collections
4. Enable performance monitoring in debug mode
5. The application now uses parallel processing for device scanning, significantly improving load times

## Troubleshooting

### Common Issues

1. **No MIDI devices detected**
   - Check that your MIDI devices are connected and powered on
   - Some devices may require specific drivers
   - Verify MIDI port names in the device configuration
   - The application automatically validates and initializes the midi-presets submodule on startup
   - If you're having connectivity issues, try enabling offline mode in the UI
   - If you still have issues, manually run the git sync operation via the API: `curl http://localhost:7777/git/sync?sync_enabled=true`

2. **UI client fails to start**
   - Check the logs in the `logs` directory for error messages
   - Ensure PyQt6 is properly installed
   - Verify that the API server is running

3. **Server Connection Failed**
   - Check server is running on configured port
   - Verify firewall settings
   - Check server URL in preferences

4. **Presetes Not Loading**
   - Ensure manufacturer and device are selected
   - Check server logs for errors
   - Try refreshing data (F5)

5. **High Memory Usage**
   - Reduce max_presets_display in config
   - Clear cache in preferences
   - Disable debug mode

### Logs

Logs are stored in the `logs` directory:
- `main.log` - Main application logs
- `device_manager.log` - Device manager logs
- `midi_utils.log` - MIDI utility logs
- `ui_launcher.log` - UI launcher logs
- `uvicorn.log` - Web server logs
- `all.log` - Combined logs from all components

## Version Management

The application version is stored in `version.py` and is automatically incremented on each push to the master branch using GitHub Actions.

### How Version Incrementing Works

The version incrementing is handled by the GitHub Actions workflow defined in `.github/workflows/build.yml`. When code is pushed to the master branch, the workflow:

1. Increments the patch version (the third number in the version)
2. Updates `version.py`, `pyproject.toml`, and `CHANGELOG.md` with the new version
3. Commits and pushes the version changes back to the repository
4. Builds and tests the application with the new version
5. Publishes the package to PyPI
6. Builds cross-platform applications for Windows and Linux

After the build workflow completes, the `.github/workflows/release.yml` workflow:

1. Creates a GitHub release with the new version
2. Builds signed applications for Windows, macOS, and Linux
3. Uploads the executables to the GitHub release

For example, if the current version is `0.1.0`, after a push to master it will be `0.1.1`.

### Manual Version Updates

For major or minor version updates (first or second number), manually edit the `version.py` and `pyproject.toml` files before pushing to master. The GitHub Actions workflow will still handle creating the release and publishing to PyPI.

## Security

**This project is 100% safe for open source distribution.** All GitHub Actions workflows have been security audited to ensure no secrets, passwords, or sensitive information can be exposed in public repositories.

Key security features:
- ✅ Complete secret masking in all workflows
- ✅ No hardcoded credentials anywhere in the codebase
- ✅ Secure certificate and API key handling
- ✅ Environment protection for production secrets

For detailed information about required GitHub secrets for macOS signing and PyPI publishing, see the [GitHub Secrets Guide](docs/github_secrets_guide.md).

For comprehensive instructions on creating signed and notarized macOS PKG installers, see the [macOS PKG Signing Guide](MACOS_PKG_SIGNING_GUIDE.md).

For detailed security information, see [.github/SECURITY_AUDIT.md](.github/SECURITY_AUDIT.md).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Add tests for new functionality
4. Ensure all tests pass
5. Commit your changes (`git commit -m 'Add some amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

**Note**: You don't need to worry about incrementing the version number. This is handled automatically by GitHub Actions when your changes are merged to the master branch.

## MIDI Presets Management

The R2MIDI server automatically manages the MIDI presets repository. For most users, no manual setup is required as the server will automatically clone the repository on startup.

For developers who want to contribute to both the R2MIDI project and the midi-presets repository, there's an option to set up the `server/midi-presets` directory as a Git submodule. See [SUBMODULE_SETUP.md](SUBMODULE_SETUP.md) for detailed instructions on both automatic and manual management options.

## Git Hooks

To prevent accidentally committing the `server/midi-presets` directory or its files to the repository, we provide Git hooks that will automatically check your commits.

### Installation

To install the Git hooks, run the following command from the repository root:

```bash
./install-hooks.sh
```

This will set up a pre-commit hook that prevents committing the `server/midi-presets` directory itself, files from the directory (except for `.gitkeep` and `README.md`), or the `.gitmodules` file with references to the midi-presets submodule.

For more details about the Git hooks and how to manage them, see [GIT_HOOKS.md](GIT_HOOKS.md).

## Acknowledgments
- PyQt6 for the excellent GUI framework
- httpx for async HTTP client
- psutil for system monitoring
- Contributors to the midi-presets repository

## License

[MIT License](LICENSE)
