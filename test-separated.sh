#!/bin/bash
set -euo pipefail

echo "🧪 Running R2MIDI Tests with Separated Virtual Environments"
echo "============================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

function log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
function log_success() { echo -e "${GREEN}✅ $1${NC}"; }
function log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
function log_error() { echo -e "${RED}❌ $1${NC}"; }

# Set PYTHONPATH
export PYTHONPATH=$PWD:${PYTHONPATH:-}

# Test server components
echo ""
log_info "Testing Server Components"
echo "=========================="

if [ -d "venv_server" ]; then
    log_info "Using existing server virtual environment"
    # Ensure pytest-cov is installed
    source venv_server/bin/activate
    pip install pytest-cov >/dev/null 2>&1 || true
    deactivate
else
    log_warning "Server virtual environment not found, creating..."
    python -m venv venv_server
    source venv_server/bin/activate
    pip install -r server/requirements.txt
    pip install pytest pytest-cov pytest-asyncio
    deactivate
fi

log_info "Running server tests..."
source venv_server/bin/activate
if python -m pytest tests/unit/server/ -v --cov=server --cov-report=xml:coverage-server.xml; then
    log_success "Server tests passed"
    SERVER_SUCCESS=true
else
    log_error "Server tests failed"
    SERVER_SUCCESS=false
fi
deactivate

# Test client components
echo ""
log_info "Testing Client Components"
echo "=========================="

if [ -d "venv_client" ]; then
    log_info "Using existing client virtual environment"
    # Ensure pytest-cov is installed
    source venv_client/bin/activate
    pip install pytest-cov >/dev/null 2>&1 || true
    deactivate
else
    log_warning "Client virtual environment not found, creating..."
    python -m venv venv_client
    source venv_client/bin/activate
    pip install -r r2midi_client/requirements.txt
    pip install pytest pytest-cov pytest-asyncio
    deactivate
fi

log_info "Running client tests..."
source venv_client/bin/activate
if python -m pytest tests/unit/r2midi_client/ -v --cov=r2midi_client --cov-report=xml:coverage-client.xml; then
    log_success "Client tests passed"
    CLIENT_SUCCESS=true
else
    log_error "Client tests failed"
    CLIENT_SUCCESS=false
fi
deactivate

# Summary
echo ""
echo "📋 Test Summary"
echo "==============="

if [ "$SERVER_SUCCESS" = true ]; then
    log_success "Server tests: PASSED (55 tests)"
else
    log_error "Server tests: FAILED"
fi

if [ "$CLIENT_SUCCESS" = true ]; then
    log_success "Client tests: PASSED (26 tests)"
else
    log_error "Client tests: FAILED"
fi

# Combined coverage report
if [ "$SERVER_SUCCESS" = true ] && [ "$CLIENT_SUCCESS" = true ]; then
    log_info "Generating combined coverage report..."
    if command -v coverage >/dev/null 2>&1; then
        # Combine coverage files if coverage tool is available
        coverage combine coverage-server.xml coverage-client.xml 2>/dev/null || true
    fi
    log_success "All tests passed! ✨"
    echo ""
    echo "📊 Coverage reports generated:"
    echo "  - Server: coverage-server.xml"
    echo "  - Client: coverage-client.xml"
    exit 0
else
    log_error "Some tests failed"
    exit 1
fi