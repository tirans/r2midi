#!/bin/bash
# Test runner for server component using build_venv_server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 Running Server Component Tests${NC}"
echo "======================================"

# Check if server virtual environment exists
if [ ! -d "build_venv_server" ]; then
    echo -e "${RED}❌ Server virtual environment not found at build_venv_server${NC}"
    echo -e "${YELLOW}Please run the build system to create the virtual environment first${NC}"
    exit 1
fi

# Activate the server virtual environment
echo -e "${BLUE}📦 Activating server virtual environment...${NC}"
source build_venv_server/bin/activate

# Verify pytest is available
if ! command -v pytest &> /dev/null; then
    echo -e "${RED}❌ pytest not found in server virtual environment${NC}"
    exit 1
fi

# Run server-specific tests
echo -e "${BLUE}🔬 Running server tests with pytest markers...${NC}"
pytest tests/ -m server -v "$@"

test_result=$?

if [ $test_result -eq 0 ]; then
    echo -e "${GREEN}✅ All server tests passed!${NC}"
else
    echo -e "${RED}❌ Some server tests failed${NC}"
fi

deactivate
exit $test_result