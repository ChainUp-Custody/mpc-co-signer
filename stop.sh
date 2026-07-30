#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Find PID of co-signer server
# We search for "co-signer -server" to avoid killing other instances or the script itself
PID=$(ps -ef | grep "co-signer" | grep -v grep | awk '{print $2}')

if [ -z "$PID" ]; then
    echo -e "${YELLOW}co-signer is not running.${NC}"
    exit 0
fi

echo -e "Stopping co-signer (PID: ${GREEN}$PID${NC})..."
kill $PID

# Wait for process to exit
for i in {1..5}; do
    if ! ps -p $PID > /dev/null; then
        echo -e "${GREEN}co-signer stopped successfully.${NC}"
        exit 0
    fi
    sleep 1
done

# Force kill if still running after timeout
if ps -p $PID > /dev/null; then
    echo -e "${YELLOW}co-signer did not stop gracefully. Force killing...${NC}"
    kill -9 $PID
    echo -e "${GREEN}co-signer stopped.${NC}"
fi
