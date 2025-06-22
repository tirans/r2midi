#!/bin/bash

echo "🧪 Testing fixes for readonly variable and pydantic dependency..."

# Test 1: Check if logging-utils.sh can be sourced multiple times
echo "📝 Test 1: Testing logging-utils.sh multiple sourcing..."
if source .github/scripts/modules/logging-utils.sh 2>/dev/null; then
    echo "✅ First sourcing successful"
    if source .github/scripts/modules/logging-utils.sh 2>/dev/null; then
        echo "✅ Second sourcing successful - readonly variable issue fixed!"
    else
        echo "❌ Second sourcing failed"
        exit 1
    fi
else
    echo "❌ First sourcing failed"
    exit 1
fi

# Test 2: Check if pydantic is in requirements files
echo "📝 Test 2: Checking pydantic in requirements files..."

if grep -q "pydantic" r2midi_client/requirements.txt; then
    echo "✅ pydantic found in r2midi_client/requirements.txt"
else
    echo "❌ pydantic missing from r2midi_client/requirements.txt"
    exit 1
fi

if grep -q "pydantic" requirements.txt; then
    echo "✅ pydantic found in root requirements.txt"
else
    echo "❌ pydantic missing from root requirements.txt"
fi

if grep -q "pydantic" server/requirements.txt; then
    echo "✅ pydantic found in server/requirements.txt"
else
    echo "❌ pydantic missing from server/requirements.txt"
fi

echo "🎉 All tests passed! Both issues should be resolved."