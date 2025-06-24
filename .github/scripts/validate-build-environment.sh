#!/bin/bash
set -euo pipefail
# Validate build environment for different platforms
# Usage: validate-build-environment.sh <platform>

PLATFORM="${1:-unknown}"
echo "🔍 Validating build environment for $PLATFORM..."

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check version
check_version() {
    local cmd="$1"
    local name="$2"
    if command_exists "$cmd"; then
        local version=$($cmd --version 2>/dev/null | head -1 || echo "Unknown version")
        echo "✅ $name: $version"
        return 0
    else
        echo "❌ $name: Not found"
        return 1
    fi
}

# Initialize validation report
echo "# Build Environment Validation Report" > build_environment_report.txt
echo "Platform: $PLATFORM" >> build_environment_report.txt
echo "Date: $(date)" >> build_environment_report.txt
echo "" >> build_environment_report.txt

# Common tools validation
echo "🔧 Checking common build tools..."
VALIDATION_FAILED=false

# Python
if check_version python3 "Python"; then
    python3 --version >> build_environment_report.txt
else
    echo "❌ Python 3 is required" >> build_environment_report.txt
    VALIDATION_FAILED=true
fi

# Pip
if check_version pip3 "Pip"; then
    pip3 --version >> build_environment_report.txt
else
    echo "❌ Pip 3 is required" >> build_environment_report.txt
    VALIDATION_FAILED=true
fi

# Git
if check_version git "Git"; then
    git --version >> build_environment_report.txt
else
    echo "❌ Git is required" >> build_environment_report.txt
    VALIDATION_FAILED=true
fi

# Platform-specific validation
case "$PLATFORM" in
    "linux")
        echo "🐧 Validating Linux environment..."
        
        # Check for essential build tools
        if command_exists gcc; then
            echo "✅ GCC: $(gcc --version | head -1)"
            gcc --version | head -1 >> build_environment_report.txt
        else
            echo "❌ GCC not found"
            echo "❌ GCC: Not found" >> build_environment_report.txt
            VALIDATION_FAILED=true
        fi
        
        if command_exists make; then
            echo "✅ Make: $(make --version | head -1)"
            make --version | head -1 >> build_environment_report.txt
        else
            echo "❌ Make not found"
            echo "❌ Make: Not found" >> build_environment_report.txt
            VALIDATION_FAILED=true
        fi
        
        # Check for pkg-config
        if command_exists pkg-config; then
            echo "✅ pkg-config: $(pkg-config --version)"
            echo "✅ pkg-config: $(pkg-config --version)" >> build_environment_report.txt
        else
            echo "⚠️ pkg-config not found (may be needed for some dependencies)"
            echo "⚠️ pkg-config: Not found" >> build_environment_report.txt
        fi
        ;;
        
    "windows")
        echo "🪟 Validating Windows environment..."
        
        # Check for Visual Studio Build Tools or similar
        if command_exists cl; then
            echo "✅ MSVC Compiler available"
            echo "✅ MSVC Compiler: Available" >> build_environment_report.txt
        else
            echo "⚠️ MSVC Compiler not found (may be needed for some dependencies)"
            echo "⚠️ MSVC Compiler: Not found" >> build_environment_report.txt
        fi
        ;;
        
    "macos")
        echo "🍎 Validating macOS environment..."
        
        # Check for Xcode command line tools
        if xcode-select -p >/dev/null 2>&1; then
            echo "✅ Xcode Command Line Tools: $(xcode-select -p)"
            echo "✅ Xcode Command Line Tools: $(xcode-select -p)" >> build_environment_report.txt
        else
            echo "❌ Xcode Command Line Tools not found"
            echo "❌ Xcode Command Line Tools: Not found" >> build_environment_report.txt
            VALIDATION_FAILED=true
        fi
        
        # Check for code signing identities
        if command_exists security; then
            local cert_count=$(security find-identity -v -p codesigning | grep "Developer ID Application" | wc -l || echo "0")
            echo "✅ Code Signing Identities: $cert_count found"
            echo "✅ Code Signing Identities: $cert_count found" >> build_environment_report.txt
        fi
        ;;
        
    *)
        echo "⚠️ Unknown platform: $PLATFORM"
        echo "⚠️ Unknown platform: $PLATFORM" >> build_environment_report.txt
        ;;
esac

# Check Python packages that are commonly needed
echo "🐍 Checking Python environment..."
if python3 -c "import briefcase" 2>/dev/null; then
    echo "✅ Briefcase: Available"
    echo "✅ Briefcase: Available" >> build_environment_report.txt
else
    echo "⚠️ Briefcase: Not found (will be installed)"
    echo "⚠️ Briefcase: Not found" >> build_environment_report.txt
fi

# Check disk space
echo "💾 Checking disk space..."
if command_exists df; then
    local available_space=$(df -h . | tail -1 | awk '{print $4}')
    echo "✅ Available disk space: $available_space"
    echo "✅ Available disk space: $available_space" >> build_environment_report.txt
else
    echo "⚠️ Could not check disk space"
    echo "⚠️ Could not check disk space" >> build_environment_report.txt
fi

# Check memory
echo "🧠 Checking memory..."
case "$(uname)" in
    "Linux")
        if command_exists free; then
            local memory=$(free -h | grep "Mem:" | awk '{print $2}')
            echo "✅ Total memory: $memory"
            echo "✅ Total memory: $memory" >> build_environment_report.txt
        fi
        ;;
    "Darwin")
        local memory=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024) "GB"}')
        echo "✅ Total memory: $memory"
        echo "✅ Total memory: $memory" >> build_environment_report.txt
        ;;
    *)
        echo "⚠️ Could not check memory"
        echo "⚠️ Could not check memory" >> build_environment_report.txt
        ;;
esac

# Final validation summary
echo "" >> build_environment_report.txt
echo "Validation Summary:" >> build_environment_report.txt
if [ "$VALIDATION_FAILED" = true ]; then
    echo "❌ FAILED: Some required tools are missing" >> build_environment_report.txt
    echo ""
    echo "❌ Build environment validation FAILED!"
    echo "📋 Validation report:"
    cat build_environment_report.txt
    exit 1
else
    echo "✅ PASSED: All required tools are available" >> build_environment_report.txt
    echo ""
    echo "✅ Build environment validation complete!"
    echo "📋 Validation report:"
    cat build_environment_report.txt
fi