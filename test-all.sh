#!/bin/bash
# Test runner for all components using their respective virtual environments

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 Running All Component Tests${NC}"
echo "==============================="

# Track test results
server_result=0
client_result=0

# Run server tests
echo -e "${BLUE}📡 Running Server Tests...${NC}"
if ./test-server.sh "$@"; then
    echo -e "${GREEN}✅ Server tests passed${NC}"
else
    echo -e "${RED}❌ Server tests failed${NC}"
    server_result=1
fi

echo
echo "================================"
echo

# Run client tests  
echo -e "${BLUE}💻 Running Client Tests...${NC}"
if ./test-client.sh "$@"; then
    echo -e "${GREEN}✅ Client tests passed${NC}"
else
    echo -e "${RED}❌ Client tests failed${NC}"
    client_result=1
fi

echo
echo "================================"
echo -e "${BLUE}📊 Test Summary${NC}"
echo "================================"

if [ $server_result -eq 0 ] && [ $client_result -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed:${NC}"
    [ $server_result -ne 0 ] && echo -e "${RED}  - Server tests failed${NC}"
    [ $client_result -ne 0 ] && echo -e "${RED}  - Client tests failed${NC}"
    exit 1
fi