#!/bin/bash
# Simple wrapper for GitHub Secrets Manager

set -euo pipefail

echo "🔐 R2MIDI GitHub Secrets Manager"
echo "================================="
echo ""

cd /Users/tirane/Desktop/r2midi

# Check if Python is available
if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python"
else
    echo "❌ Python not found. Please install Python 3.8+"
    exit 1
fi

# Run the main script with all arguments passed through
exec $PYTHON_CMD scripts/setup_github_secrets.py "$@"
