#!/bin/bash
set -euo pipefail
# Validate R2MIDI project structure
# Usage: validate-project-structure.sh

echo "🔍 Validating R2MIDI project structure..."

# Initialize validation status
VALIDATION_FAILED=false
WARNINGS=0
ERRORS=0

# Function to log validation results
log_check() {
    local status="$1"
    local message="$2"
    local level="${3:-info}"
    
    case "$status" in
        "✅")
            echo "$status $message"
            ;;
        "⚠️")
            echo "$status $message"
            WARNINGS=$((WARNINGS + 1))
            ;;
        "❌")
            echo "$status $message"
            ERRORS=$((ERRORS + 1))
            VALIDATION_FAILED=true
            ;;
    esac
}

# Function to check if file exists
check_file() {
    local file="$1"
    local required="${2:-true}"
    local description="$3"
    
    if [ -f "$file" ]; then
        log_check "✅" "$description: $file"
        return 0
    else
        if [ "$required" = "true" ]; then
            log_check "❌" "$description missing: $file"
            return 1
        else
            log_check "⚠️" "$description not found (optional): $file"
            return 1
        fi
    fi
}

# Function to check if directory exists
check_directory() {
    local dir="$1"
    local required="${2:-true}"
    local description="$3"
    
    if [ -d "$dir" ]; then
        log_check "✅" "$description: $dir"
        return 0
    else
        if [ "$required" = "true" ]; then
            log_check "❌" "$description missing: $dir"
            return 1
        else
            log_check "⚠️" "$description not found (optional): $dir"
            return 1
        fi
    fi
}

# Function to validate Python project files
validate_python_files() {
    echo ""
    echo "🐍 Validating Python project files..."
    
    # Check main project files
    check_file "pyproject.toml" true "Main project configuration"
    check_file "requirements.txt" false "Main requirements file"
    check_file "README.md" true "Project README"
    check_file "LICENSE" false "License file"
    
    # Check server files
    check_directory "server" true "Server directory"
    if [ -d "server" ]; then
        check_file "server/__init__.py" false "Server package init"
        check_file "server/version.py" true "Server version file"
        check_file "server/main.py" false "Server main module"
    fi
    
    # Check client files
    check_directory "r2midi_client" true "Client directory"
    if [ -d "r2midi_client" ]; then
        check_file "r2midi_client/pyproject.toml" true "Client project configuration"
        check_file "r2midi_client/requirements.txt" false "Client requirements file"
        check_file "r2midi_client/src/r2midi_client/__init__.py" false "Client package init"
        check_file "r2midi_client/src/r2midi_client/app.py" false "Client main app"
    fi
}

# Function to validate configuration files
validate_config_files() {
    echo ""
    echo "⚙️ Validating configuration files..."
    
    # Check GitHub workflows
    check_directory ".github" true "GitHub directory"
    check_directory ".github/workflows" true "GitHub workflows directory"
    check_file ".github/workflows/build-macos.yml" true "macOS build workflow"
    check_file ".github/workflows/build-linux.yml" true "Linux build workflow"
    check_file ".github/workflows/build-windows.yml" true "Windows build workflow"
    check_file ".github/workflows/ci.yml" true "CI workflow"
    check_file ".github/workflows/release.yml" false "Release workflow"
    
    # Check GitHub scripts
    check_directory ".github/scripts" true "GitHub scripts directory"
    
    # Check Apple credentials (if present)
    if [ -d "apple_credentials" ]; then
        log_check "✅" "Apple credentials directory found"
        check_directory "apple_credentials/config" false "Apple config directory"
        check_directory "apple_credentials/certificates" false "Apple certificates directory"
        
        if [ -d "apple_credentials/config" ]; then
            check_file "apple_credentials/config/app_config.json" false "App configuration"
        fi
    else
        log_check "⚠️" "Apple credentials directory not found (optional for non-macOS builds)"
    fi
    
    # Check other config files
    check_file ".gitignore" true "Git ignore file"
    check_file "entitlements.plist" false "macOS entitlements file"
}

# Function to validate build scripts
validate_build_scripts() {
    echo ""
    echo "🔧 Validating build scripts..."
    
    # Check main build scripts
    check_file "build-all-local.sh" true "Main local build script"
    check_file "clean-environment.sh" false "Environment cleanup script"
    check_file "setup-virtual-environments.sh" false "Virtual environment setup script"
    check_file "test_environments.sh" false "Environment test script"
    check_file "test-signing-environment.sh" false "Signing environment test script"
    
    # Check GitHub scripts
    local github_scripts=(
        "extract-version.sh"
        "validate-build-environment.sh"
        "install-system-dependencies.sh"
        "install-python-dependencies.sh"
        "build-briefcase-apps.sh"
        "package-linux-apps.sh"
        "package-windows-apps.sh"
        "generate-build-summary.sh"
        "setup-environment.sh"
        "validate-project-structure.sh"
        "detect-runner.sh"
        "clean-app.sh"
        "sign-notarize.sh"
    )
    
    for script in "${github_scripts[@]}"; do
        check_file ".github/scripts/$script" true "GitHub script: $script"
    done
    
    # Check scripts directory
    if [ -d "scripts" ]; then
        log_check "✅" "Scripts directory found"
        check_file "scripts/bulletproof_clean_app_bundle.py" false "Bulletproof clean script"
    else
        log_check "⚠️" "Scripts directory not found (optional)"
    fi
}

# Function to validate project structure
validate_project_structure() {
    echo ""
    echo "📁 Validating project structure..."
    
    # Check for common directories
    check_directory "artifacts" false "Artifacts directory"
    check_directory "logs" false "Logs directory"
    check_directory "build" false "Build directory"
    check_directory "dist" false "Distribution directory"
    
    # Check for Python cache directories (should not be present)
    if [ -d "__pycache__" ]; then
        log_check "⚠️" "Python cache directory found (should be in .gitignore)"
    fi
    
    if find . -name "*.pyc" -type f | head -1 | grep -q .; then
        log_check "⚠️" "Python bytecode files found (should be in .gitignore)"
    fi
    
    # Check for common development files
    if [ -f ".env" ]; then
        log_check "⚠️" "Environment file found (ensure it's in .gitignore)"
    fi
    
    if [ -f ".DS_Store" ]; then
        log_check "⚠️" "macOS .DS_Store file found (should be in .gitignore)"
    fi
}

# Function to validate Python syntax
validate_python_syntax() {
    echo ""
    echo "🐍 Validating Python syntax..."
    
    local python_files_found=false
    
    # Check Python files in server directory
    if [ -d "server" ]; then
        while IFS= read -r -d '' file; do
            python_files_found=true
            if python3 -m py_compile "$file" 2>/dev/null; then
                log_check "✅" "Python syntax valid: $file"
            else
                log_check "❌" "Python syntax error: $file"
            fi
        done < <(find server -name "*.py" -type f -print0 2>/dev/null)
    fi
    
    # Check Python files in client directory
    if [ -d "r2midi_client/src" ]; then
        while IFS= read -r -d '' file; do
            python_files_found=true
            if python3 -m py_compile "$file" 2>/dev/null; then
                log_check "✅" "Python syntax valid: $file"
            else
                log_check "❌" "Python syntax error: $file"
            fi
        done < <(find r2midi_client/src -name "*.py" -type f -print0 2>/dev/null)
    fi
    
    if [ "$python_files_found" = false ]; then
        log_check "⚠️" "No Python files found to validate"
    fi
}

# Function to validate shell script syntax
validate_shell_syntax() {
    echo ""
    echo "🐚 Validating shell script syntax..."
    
    local shell_files_found=false
    
    # Check shell scripts in root directory
    while IFS= read -r -d '' file; do
        shell_files_found=true
        if bash -n "$file" 2>/dev/null; then
            log_check "✅" "Shell syntax valid: $file"
        else
            log_check "❌" "Shell syntax error: $file"
        fi
    done < <(find . -maxdepth 1 -name "*.sh" -type f -print0 2>/dev/null)
    
    # Check shell scripts in .github/scripts directory
    if [ -d ".github/scripts" ]; then
        while IFS= read -r -d '' file; do
            shell_files_found=true
            if bash -n "$file" 2>/dev/null; then
                log_check "✅" "Shell syntax valid: $file"
            else
                log_check "❌" "Shell syntax error: $file"
            fi
        done < <(find .github/scripts -name "*.sh" -type f -print0 2>/dev/null)
    fi
    
    if [ "$shell_files_found" = false ]; then
        log_check "⚠️" "No shell scripts found to validate"
    fi
}

# Function to validate YAML syntax
validate_yaml_syntax() {
    echo ""
    echo "📄 Validating YAML syntax..."
    
    local yaml_files_found=false
    
    # Check GitHub workflow files
    if [ -d ".github/workflows" ]; then
        while IFS= read -r -d '' file; do
            yaml_files_found=true
            # Try to parse YAML with Python if available
            if command -v python3 >/dev/null 2>&1; then
                if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
                    log_check "✅" "YAML syntax valid: $file"
                else
                    log_check "❌" "YAML syntax error: $file"
                fi
            else
                log_check "⚠️" "Cannot validate YAML syntax (Python not available): $file"
            fi
        done < <(find .github/workflows -name "*.yml" -o -name "*.yaml" -type f -print0 2>/dev/null)
    fi
    
    if [ "$yaml_files_found" = false ]; then
        log_check "⚠️" "No YAML files found to validate"
    fi
}

# Function to create validation report
create_validation_report() {
    echo ""
    echo "📋 Creating validation report..."
    
    local report_file="project_structure_validation.txt"
    
    cat > "$report_file" << EOF
# R2MIDI Project Structure Validation Report
Generated: $(date)

## Validation Summary
Total Errors: $ERRORS
Total Warnings: $WARNINGS
Overall Status: $([ "$VALIDATION_FAILED" = false ] && echo "✅ PASSED" || echo "❌ FAILED")

## Validation Categories
- Python project files
- Configuration files
- Build scripts
- Project structure
- Python syntax
- Shell script syntax
- YAML syntax

## Recommendations
EOF

    if [ "$ERRORS" -gt 0 ]; then
        echo "- Fix all errors before proceeding with builds" >> "$report_file"
    fi
    
    if [ "$WARNINGS" -gt 0 ]; then
        echo "- Review warnings and fix if necessary" >> "$report_file"
    fi
    
    if [ "$VALIDATION_FAILED" = false ]; then
        echo "- Project structure is valid and ready for builds" >> "$report_file"
    fi
    
    echo "" >> "$report_file"
    echo "For detailed validation output, see the console log above." >> "$report_file"
    
    log_check "✅" "Validation report created: $report_file"
}

# Main validation function
main() {
    echo "🚀 Starting project structure validation..."
    echo ""
    
    # Run all validation checks
    validate_python_files
    validate_config_files
    validate_build_scripts
    validate_project_structure
    validate_python_syntax
    validate_shell_syntax
    validate_yaml_syntax
    
    # Create validation report
    create_validation_report
    
    # Final summary
    echo ""
    echo "📊 Validation Summary:"
    echo "   Errors: $ERRORS"
    echo "   Warnings: $WARNINGS"
    echo "   Status: $([ "$VALIDATION_FAILED" = false ] && echo "✅ PASSED" || echo "❌ FAILED")"
    echo ""
    
    if [ "$VALIDATION_FAILED" = false ]; then
        echo "🎉 Project structure validation completed successfully!"
        echo "The project is ready for builds and deployment."
        exit 0
    else
        echo "💥 Project structure validation failed!"
        echo "Please fix the errors above before proceeding."
        exit 1
    fi
}

# Run main function
main "$@"