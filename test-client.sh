#!/bin/bash
# Test runner for client component using build_venv_client

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 Running Client Component Tests${NC}"
echo "======================================"

# Check if client virtual environment exists
if [ ! -d "build_venv_client" ]; then
    echo -e "${RED}❌ Client virtual environment not found at build_venv_client${NC}"
    echo -e "${YELLOW}Please run the build system to create the virtual environment first${NC}"
    exit 1
fi

# Activate the client virtual environment
echo -e "${BLUE}📦 Activating client virtual environment...${NC}"
source build_venv_client/bin/activate

# Verify pytest is available
if ! command -v pytest &> /dev/null; then
    echo -e "${RED}❌ pytest not found in client virtual environment${NC}"
    exit 1
fi

# Run client-specific tests
echo -e "${BLUE}🔬 Running client tests with pytest markers...${NC}"
pytest tests/ -m client -v "$@"

test_result=$?

if [ $test_result -eq 0 ]; then
    echo -e "${GREEN}✅ All client tests passed!${NC}"
else
    echo -e "${RED}❌ Some client tests failed${NC}"
fi

deactivate
exit $test_result