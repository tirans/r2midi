#!/bin/bash
# test_environments.sh - Test virtual environments
set -euo pipefail

echo "🧪 Testing virtual environments..."

# Function to extract module names from requirements.txt and generate import statements
generate_imports_from_requirements() {
    local requirements_file="$1"
    local imports=""

    if [ ! -f "$requirements_file" ]; then
        echo "⚠️ Requirements file $requirements_file not found"
        return 1
    fi

    # Read requirements file and extract package names
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Extract package name (everything before ==, >=, <=, >, <, !=, ~=)
        package=$(echo "$line" | sed -E 's/[><=!~].*//' | tr '[:upper:]' '[:lower:]' | xargs)

        # Skip common build/test packages that don't need import testing
        case "$package" in
            setuptools|wheel|pip|py2app|pytest|pytest-*) continue ;;
        esac

        # Handle special package name mappings
        case "$package" in
            pyqt6) import_name="PyQt6" ;;
            pyqt6-sip) continue ;; # Skip sip, it's a dependency
            python-rtmidi) import_name="rtmidi" ;;
            python-dotenv) import_name="dotenv" ;;
            gitpython) import_name="git" ;;
            *) import_name="$package" ;;
        esac

        if [ -n "$imports" ]; then
            imports="$imports, $import_name"
        else
            imports="$import_name"
        fi
    done < "$requirements_file"

    echo "$imports"
}

test_env() {
    local name="$1"
    local requirements_file="$2"

    if [ -d "venv_$name" ]; then
        echo "🔍 Testing $name environment..."

        # Generate import statements from requirements file
        imports=$(generate_imports_from_requirements "$requirements_file")
        if [ -z "$imports" ]; then
            echo "⚠️ No imports to test for $name environment"
            return 1
        fi

        test_imports="import $imports; print('$name dependencies OK')"
        echo "📦 Testing imports: $imports"

        source "venv_$name/bin/activate"
        if python -c "$test_imports"; then
            echo "✅ $name environment working"
        else
            echo "❌ $name environment failed"
            deactivate
            return 1
        fi
        deactivate
    else
        echo "⚠️ $name environment not found"
        return 1
    fi
}

success=true

test_env "client" "r2midi_client/requirements.txt" || success=false
test_env "server" "server/requirements.txt" || success=false

if [ "$success" = "true" ]; then
    echo "✅ All environment tests passed!"
    exit 0
else
    echo "❌ Some environment tests failed!"
    exit 1
fi
