#!/bin/bash
set -e

# Redis Compatibility Test - Standalone Script
# This script starts Tendis server(s) and runs Redis protocol compatibility tests

# Define Workspace
TENDIS_HOME="/src/Tendis"
if [ -d "/src/Tendis" ]; then
    cd "/src/Tendis"
elif [ -d "$(pwd)/temp_tendis" ]; then
    cd "$(pwd)/temp_tendis"
elif [ -f "redistest.sh" ]; then
    echo "Running in current directory"
else
    echo "Error: Cannot find Tendis source directory"
    exit 1
fi

echo "=================================================="
echo "   TENDIS REDIS COMPATIBILITY TEST (Standalone)"
echo "=================================================="
echo "Working Directory: $(pwd)"
echo ""

# Check if Tendis binary exists
if [ ! -f "build/bin/tendisplus" ]; then
    echo "❌ Error: Tendis binary not found at build/bin/tendisplus"
    exit 1
fi

# Configuration
TEST_PORT=51000
TEST_DIR="./redis_compat_test_data"
CONFIG_FILE="./redis_compat_test.conf"

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    
    # Kill Tendis server
    if [ ! -z "$TENDIS_PID" ] && kill -0 $TENDIS_PID 2>/dev/null; then
        echo "Stopping Tendis server (PID: $TENDIS_PID)..."
        kill $TENDIS_PID
        wait $TENDIS_PID 2>/dev/null || true
    fi
    
    # Clean test directory
    if [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
    
    # Clean config file
    if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE"
    fi
    
    # Clean logs
    rm -f redis_compat_server.log
    
    echo "Cleanup complete."
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Create test configuration
echo "Creating test configuration..."
cat > "$CONFIG_FILE" << EOF
bind 127.0.0.1
port $TEST_PORT
dir $TEST_DIR
logdir $TEST_DIR/log
pidfile $TEST_DIR/tendis.pid
loglevel notice
databases 16
kvstorecount 10
daemon no
EOF

# Create test directory
mkdir -p "$TEST_DIR/log"

# Start Tendis server
echo "Starting Tendis server on port $TEST_PORT..."
nohup ./build/bin/tendisplus "$CONFIG_FILE" > redis_compat_server.log 2>&1 &
TENDIS_PID=$!

echo "Tendis server started (PID: $TENDIS_PID)"
echo "Waiting for server to be ready..."

# Wait for server to be ready (max 30 seconds)
MAX_WAIT=30
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    # Check if log file contains port binding confirmation
    if [ -f redis_compat_server.log ] && grep -q "port.*$TEST_PORT" redis_compat_server.log 2>/dev/null; then
        # Give it one more second to fully initialize
        sleep 1
        echo "✅ Tendis server is ready!"
        break
    fi
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
    if [ $((WAIT_COUNT % 5)) -eq 0 ]; then
        echo "Still waiting... ($WAIT_COUNT/$MAX_WAIT seconds)"
    fi
done

if [ $WAIT_COUNT -eq $MAX_WAIT ]; then
    echo "❌ Error: Tendis server failed to start within $MAX_WAIT seconds"
    echo "--- Server log ---"
    cat redis_compat_server.log
    exit 1
fi

# Run Redis compatibility tests
echo ""
echo "=================================================="
echo "Running Redis Compatibility Tests..."
echo "=================================================="

# Clean previous logs
rm -f redistest.log redistest_output.log
rm -rf ./tests/tmp/*

# Run the actual test
echo "(This may take several minutes, showing progress below)"
echo ""
bash ./redistest.sh 2>&1 | tee redistest_output.log || true

# Check results
echo ""
if [ ! -f "redistest.log" ]; then
    echo "❌ Error: redistest.log not found!"
    echo "--- Test output ---"
    cat redistest_output.log 2>/dev/null || echo "No output log found"
    exit 1
fi

if grep -Eq "\[err|\[exception|49merr|49mexception" redistest.log; then
    echo "❌ Redis Compatibility Tests FAILED"
    echo ""
    echo "Failed tests:"
    grep -E "\[err|\[exception|49merr|49mexception" redistest.log | head -n 30
    echo ""
    echo "See redistest.log for full details."
    exit 1
else
    echo "✅ Redis Compatibility Tests PASSED"
    echo ""
    # Show summary
    total_tests=$(grep -c "Testing " redistest.log 2>/dev/null || echo "unknown")
    echo "Total tests executed: $total_tests"
fi

echo "=================================================="
echo "Test completed successfully!"
echo "=================================================="
