#!/bin/bash

# test_workflow_fix.sh - Test the GitHub Actions workflow fix
set -e

echo "🧪 Testing GitHub Actions workflow fix..."

# Check if the workflow files exist
echo "📋 Checking workflow files..."
if [ ! -f ".github/workflows/build.yml" ]; then
    echo "❌ build.yml not found"
    exit 1
fi

if [ ! -f ".github/workflows/build-macos.yml" ]; then
    echo "❌ build-macos.yml not found"
    exit 1
fi

echo "✅ Both workflow files exist"

# Test YAML syntax using Python (if available)
echo ""
echo "🔍 Testing YAML syntax..."

if command -v python3 >/dev/null 2>&1; then
    echo "Testing build.yml syntax..."
    python3 -c "
import yaml
import sys
try:
    with open('.github/workflows/build.yml', 'r') as f:
        yaml.safe_load(f)
    print('✅ build.yml syntax is valid')
except Exception as e:
    print(f'❌ build.yml syntax error: {e}')
    sys.exit(1)
"

    echo "Testing build-macos.yml syntax..."
    python3 -c "
import yaml
import sys
try:
    with open('.github/workflows/build-macos.yml', 'r') as f:
        content = yaml.safe_load(f)
    print('✅ build-macos.yml syntax is valid')

    # Check if workflow_call trigger exists (YAML parses 'on:' as True)
    triggers = content.get('on') or content.get(True)
    if triggers and 'workflow_call' in triggers:
        print('✅ workflow_call trigger found')

        # Check if required inputs exist
        wc = triggers['workflow_call']
        if 'inputs' in wc and 'version' in wc['inputs']:
            print('✅ version input found')
        else:
            print('❌ version input missing')
            sys.exit(1)

        if 'secrets' in wc:
            print('✅ secrets section found')
        else:
            print('❌ secrets section missing')
            sys.exit(1)
    else:
        print('❌ workflow_call trigger missing')
        sys.exit(1)

except Exception as e:
    print(f'❌ build-macos.yml syntax error: {e}')
    sys.exit(1)
"
else
    echo "⚠️ Python3 not available, skipping YAML syntax check"
fi

# Check the specific line in build.yml that was causing the issue
echo ""
echo "🔍 Checking workflow call in build.yml..."
if grep -n "uses: ./.github/workflows/build-macos.yml" .github/workflows/build.yml; then
    echo "✅ Found workflow call to build-macos.yml"
else
    echo "❌ Workflow call not found"
    exit 1
fi

echo ""
echo "📋 Summary of fixes applied:"
echo "  ✅ Added workflow_call trigger to build-macos.yml"
echo "  ✅ Added required inputs: version, build-type, runner-type"
echo "  ✅ Added required secrets for Apple certificates"
echo "  ✅ Updated job to use input parameters"
echo "  ✅ Added environment variables for Apple credentials"
echo ""
echo "🎯 The workflow should now be reusable and the error should be resolved!"
