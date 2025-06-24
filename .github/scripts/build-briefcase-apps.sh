#!/bin/bash
set -euo pipefail
# Build applications using Briefcase
# Usage: build-briefcase-apps.sh <platform> <signing_mode>

PLATFORM="${1:-linux}"
SIGNING_MODE="${2:-unsigned}"
echo "🏗️ Building Briefcase applications for $PLATFORM ($SIGNING_MODE)..."

# Function to build client application
build_client_app() {
    echo "📱 Building R2MIDI Client..."
    
    cd r2midi_client || {
        echo "❌ Error: r2midi_client directory not found"
        return 1
    }
    
    # Create the app
    echo "🔨 Creating client app..."
    briefcase create $PLATFORM
    
    # Build the app
    echo "🔧 Building client app..."
    briefcase build $PLATFORM
    
    # Package the app if not in dev mode
    if [ "$SIGNING_MODE" != "dev" ]; then
        echo "📦 Packaging client app..."
        if [ "$SIGNING_MODE" = "signed" ]; then
            briefcase package $PLATFORM --adhoc-sign
        else
            briefcase package $PLATFORM
        fi
    fi
    
    cd ..
    echo "✅ Client app build complete"
}

# Function to build server application
build_server_app() {
    echo "🖥️ Building R2MIDI Server..."
    
    # Check if server has its own pyproject.toml
    if [ -f "server/pyproject.toml" ]; then
        cd server
    elif [ -f "pyproject.toml" ]; then
        # Server is in root directory
        echo "📋 Using root pyproject.toml for server"
    else
        echo "❌ Error: No pyproject.toml found for server"
        return 1
    fi
    
    # Create the app
    echo "🔨 Creating server app..."
    briefcase create $PLATFORM
    
    # Build the app
    echo "🔧 Building server app..."
    briefcase build $PLATFORM
    
    # Package the app if not in dev mode
    if [ "$SIGNING_MODE" != "dev" ]; then
        echo "📦 Packaging server app..."
        if [ "$SIGNING_MODE" = "signed" ]; then
            briefcase package $PLATFORM --adhoc-sign
        else
            briefcase package $PLATFORM
        fi
    fi
    
    # Return to root if we changed directory
    if [ -f "pyproject.toml" ] && [ "$(basename $(pwd))" = "server" ]; then
        cd ..
    fi
    
    echo "✅ Server app build complete"
}

# Function to handle platform-specific build settings
setup_platform_environment() {
    case "$PLATFORM" in
        "linux")
            echo "🐧 Setting up Linux build environment..."
            export BRIEFCASE_LINUX_SYSTEM_REQUIRES="true"
            ;;
        "windows")
            echo "🪟 Setting up Windows build environment..."
            # Windows-specific environment setup
            ;;
        "macOS")
            echo "🍎 Setting up macOS build environment..."
            # macOS-specific environment setup
            if [ "$SIGNING_MODE" = "signed" ]; then
                echo "🔐 Code signing will be handled by briefcase"
            fi
            ;;
        *)
            echo "⚠️ Warning: Unknown platform '$PLATFORM'"
            ;;
    esac
}

# Function to verify build outputs
verify_build_outputs() {
    echo "🔍 Verifying build outputs..."
    
    local build_failed=false
    
    # Check client build outputs
    if [ -d "r2midi_client/dist" ]; then
        echo "✅ Client build outputs found"
        ls -la r2midi_client/dist/
    else
        echo "❌ Client build outputs not found"
        build_failed=true
    fi
    
    # Check server build outputs
    if [ -d "dist" ]; then
        echo "✅ Server build outputs found"
        ls -la dist/
    elif [ -d "server/dist" ]; then
        echo "✅ Server build outputs found"
        ls -la server/dist/
    else
        echo "❌ Server build outputs not found"
        build_failed=true
    fi
    
    if [ "$build_failed" = true ]; then
        echo "❌ Build verification failed"
        return 1
    else
        echo "✅ Build verification passed"
        return 0
    fi
}

# Function to create build summary
create_build_summary() {
    echo "📋 Creating build summary..."
    
    cat > build_summary.txt << EOF
# Briefcase Build Summary
Platform: $PLATFORM
Signing Mode: $SIGNING_MODE
Build Date: $(date)

## Build Status
EOF

    if [ -d "r2midi_client/dist" ]; then
        echo "Client: ✅ SUCCESS" >> build_summary.txt
        echo "Client Outputs:" >> build_summary.txt
        ls -la r2midi_client/dist/ >> build_summary.txt
    else
        echo "Client: ❌ FAILED" >> build_summary.txt
    fi
    
    echo "" >> build_summary.txt
    
    if [ -d "dist" ] || [ -d "server/dist" ]; then
        echo "Server: ✅ SUCCESS" >> build_summary.txt
        echo "Server Outputs:" >> build_summary.txt
        if [ -d "dist" ]; then
            ls -la dist/ >> build_summary.txt
        else
            ls -la server/dist/ >> build_summary.txt
        fi
    else
        echo "Server: ❌ FAILED" >> build_summary.txt
    fi
    
    echo "📋 Build summary created: build_summary.txt"
}

# Main build process
main() {
    echo "🚀 Starting Briefcase build process..."
    
    # Setup platform environment
    setup_platform_environment
    
    # Verify briefcase is installed
    if ! command -v briefcase >/dev/null 2>&1; then
        echo "❌ Error: Briefcase is not installed"
        echo "Please run: pip install briefcase"
        exit 1
    fi
    
    echo "📋 Briefcase version: $(briefcase --version)"
    
    # Build applications
    local build_success=true
    
    # Build client
    if build_client_app; then
        echo "✅ Client build successful"
    else
        echo "❌ Client build failed"
        build_success=false
    fi
    
    # Build server
    if build_server_app; then
        echo "✅ Server build successful"
    else
        echo "❌ Server build failed"
        build_success=false
    fi
    
    # Verify outputs
    if verify_build_outputs; then
        echo "✅ Build verification successful"
    else
        echo "❌ Build verification failed"
        build_success=false
    fi
    
    # Create summary
    create_build_summary
    
    # Final result
    if [ "$build_success" = true ]; then
        echo "🎉 Briefcase build completed successfully!"
        exit 0
    else
        echo "💥 Briefcase build failed!"
        exit 1
    fi
}

# Run main function
main "$@"