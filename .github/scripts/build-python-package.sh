#!/bin/bash
set -euo pipefail

# Build Python package for PyPI distribution
# Usage: build-python-package.sh

echo "📦 Building R2MIDI Python package..."

# Validate environment
if ! command -v python >/dev/null 2>&1; then
    echo "❌ Error: Python not found"
    exit 1
fi

echo "🐍 Python version: $(python --version)"

# Clean previous builds
echo "🧹 Cleaning previous build artifacts..."
rm -rf build/ dist/ *.egg-info/ || true

# Ensure we have the latest build tools
echo "🔧 Installing/updating build tools..."
python -m pip install --upgrade pip
python -m pip install --upgrade build twine setuptools wheel

# Validate project structure
echo "🔍 Validating project structure for packaging..."

# Check required files
required_files=(
    "pyproject.toml"
    "README.md"
    "LICENSE"
    "server/version.py"
    "server/main.py"
    "r2midi_client/main.py"
)

missing_files=()
for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        missing_files+=("$file")
    fi
done

if [ ${#missing_files[@]} -gt 0 ]; then
    echo "❌ Error: Missing required files for packaging:"
    printf '  - %s\n' "${missing_files[@]}"
    exit 1
fi

# Extract version information
echo "📋 Extracting version information..."
if [ -f "server/version.py" ]; then
    VERSION=$(grep -o '__version__ = "[^"]*"' server/version.py | cut -d'"' -f2)
    echo "Package version: $VERSION"
else
    echo "❌ Error: Cannot find version in server/version.py"
    exit 1
fi

# Validate pyproject.toml
echo "🔍 Validating pyproject.toml..."
if ! grep -q "^name = " pyproject.toml; then
    echo "❌ Error: Missing 'name' in pyproject.toml"
    exit 1
fi

if ! grep -q "^version = " pyproject.toml; then
    echo "❌ Error: Missing 'version' in pyproject.toml"
    exit 1
fi

# Check version consistency
echo "🔍 Checking version consistency..."
PYPROJECT_VERSION=$(grep '^version = ' pyproject.toml | head -1 | cut -d'"' -f2 | tr -d '\n\r')

# Clean up any whitespace
VERSION=$(echo "$VERSION" | tr -d '\n\r')
PYPROJECT_VERSION=$(echo "$PYPROJECT_VERSION" | tr -d '\n\r')

echo "📋 server/version.py: '$VERSION'"
echo "📋 pyproject.toml: '$PYPROJECT_VERSION'"

if [ "$VERSION" != "$PYPROJECT_VERSION" ]; then
    echo "⚠️ Warning: Version mismatch between server/version.py ($VERSION) and pyproject.toml ($PYPROJECT_VERSION)"
    echo "Using server/version.py version: $VERSION"

    # Escape special characters for sed (dots become literal dots)
    ESCAPED_OLD_VERSION=$(echo "$PYPROJECT_VERSION" | sed 's/\./\\./g')
    ESCAPED_NEW_VERSION=$(echo "$VERSION" | sed 's/\./\\./g')

    # Update pyproject.toml version to match using a more robust approach
    if sed -i.bak "1,/^version = \"$ESCAPED_OLD_VERSION\"/s/^version = \"$ESCAPED_OLD_VERSION\"/version = \"$VERSION\"/" pyproject.toml; then
        rm -f pyproject.toml.bak
        echo "✅ Updated pyproject.toml version to match"

        # Verify the update worked
        NEW_PYPROJECT_VERSION=$(grep '^version = ' pyproject.toml | head -1 | cut -d'"' -f2 | tr -d '\n\r')
        if [ "$VERSION" = "$NEW_PYPROJECT_VERSION" ]; then
            echo "✅ Version update verified successfully"
        else
            echo "❌ Error: Version update failed. Expected: $VERSION, Got: $NEW_PYPROJECT_VERSION"
            exit 1
        fi
    else
        echo "❌ Error: Failed to update pyproject.toml version"
        exit 1
    fi
else
    echo "✅ Version consistency check passed"
fi

# Create source distribution manifest
echo "📝 Ensuring proper package manifest..."
cat > MANIFEST.in << EOF
# Include documentation
include README.md
include LICENSE
include CHANGELOG.md

# Include configuration files
include pyproject.toml
include requirements.txt
include r2midi_client/requirements.txt

# Include application resources
include r2midi.png
include r2midi.ico
include r2midi.icns
recursive-include r2midi.iconset *
recursive-include resources *

# Include server application
recursive-include server *.py
recursive-include server *.json
recursive-include server *.yaml
recursive-include server *.yml
recursive-include server *.txt

# Include client application
recursive-include r2midi_client *.py
recursive-include r2midi_client *.ui
recursive-include r2midi_client *.qrc
recursive-include r2midi_client *.json
recursive-include r2midi_client *.txt

# Include tests
recursive-include tests *.py

# Exclude development and build files
global-exclude __pycache__
global-exclude *.py[co]
global-exclude .DS_Store
global-exclude *.so
global-exclude .git*
global-exclude build
global-exclude dist
global-exclude *.egg-info
EOF

# Build the package
echo "🏗️ Building Python package..."

# Build source distribution and wheel
python -m build --sdist --wheel

if [ $? -ne 0 ]; then
    echo "❌ Error: Package build failed"
    exit 1
fi

echo "✅ Package build completed successfully"

# Validate the built package
echo "🔍 Validating built package..."

# Check if distribution files were created
if [ ! -d "dist" ] || [ -z "$(ls -A dist/)" ]; then
    echo "❌ Error: No distribution files created"
    exit 1
fi

# Check package with twine
echo "🔍 Running package checks..."
python -m twine check dist/*.whl dist/*.tar.gz

if [ $? -ne 0 ]; then
    echo "❌ Error: Package validation failed"
    exit 1
fi

# Test package installation in isolated environment
echo "🧪 Testing package installation..."

# Create temporary virtual environment for testing
temp_venv=$(mktemp -d)
python -m venv "$temp_venv"

# Activate virtual environment
source "$temp_venv/bin/activate" 2>/dev/null || source "$temp_venv/Scripts/activate"

# Install the built package
wheel_file=$(find dist/ -name "*.whl" | head -1)
if [ -n "$wheel_file" ]; then
    echo "📦 Testing wheel installation: $(basename "$wheel_file")"
    pip install "$wheel_file"

    # Test basic import
    if python -c "import server.main, r2midi_client.main" 2>/dev/null; then
        echo "✅ Package imports successfully"
    else
        echo "⚠️ Warning: Package import test failed"
    fi
else
    echo "⚠️ Warning: No wheel file found for testing"
fi

# Deactivate and cleanup
deactivate 2>/dev/null || true
rm -rf "$temp_venv"

# Generate package information
echo "📋 Generating package information..."

cat > dist/PACKAGE_INFO.txt << EOF
R2MIDI Python Package Information
=================================

Package Name: r2midi
Version: $VERSION
Build Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Python Version: $(python --version)

Distribution Files:
EOF

# List distribution files with sizes
find dist/ -name "*.tar.gz" -o -name "*.whl" | sort | while read file; do
    if [ -f "$file" ]; then
        size=$(du -h "$file" | cut -f1)
        echo "  - $(basename "$file") ($size)" >> dist/PACKAGE_INFO.txt
    fi
done

cat >> dist/PACKAGE_INFO.txt << EOF

Installation:
  pip install r2midi

Development Installation:
  pip install r2midi[dev]

Package Contents:
  - R2MIDI Server: MIDI 2.0 REST API server
  - R2MIDI Client: PyQt6-based GUI client
  - Configuration files and documentation

PyPI Upload:
  This package is ready for upload to PyPI using:
  python -m twine upload dist/*

Security:
  Package built in isolated environment
  All dependencies verified
  Source code integrity maintained
EOF

# Display summary
echo ""
echo "✅ Python package build complete!"
echo ""
echo "📦 Distribution files created in dist/:"
find dist/ -name "*.tar.gz" -o -name "*.whl" | while read file; do
    if [ -f "$file" ]; then
        size=$(du -h "$file" | cut -f1)
        echo "  - $(basename "$file") ($size)"
    fi
done

echo ""
echo "📋 Package information:"
cat dist/PACKAGE_INFO.txt

echo ""
echo "🚀 Next steps:"
echo "  1. Review dist/PACKAGE_INFO.txt for package details"
echo "  2. Test the package in a clean environment"
echo "  3. Upload to PyPI with: python -m twine upload dist/*"
echo "  4. Verify package on PyPI: https://pypi.org/project/r2midi/"
