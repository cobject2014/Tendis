#!/bin/bash
set -e

# Go Integration Test - Standalone Script
# This script runs Go integration tests which require Tendis cluster setup

# Define Workspace
TENDIS_HOME="/src/Tendis"
if [ -d "/src/Tendis" ]; then
    cd "/src/Tendis"
elif [ -d "$(pwd)/temp_tendis" ]; then
    cd "$(pwd)/temp_tendis"
elif [ -f "testall.sh" ]; then
    echo "Running in current directory"
else
    echo "Error: Cannot find Tendis source directory"
    exit 1
fi

echo "=================================================="
echo "   TENDIS GO INTEGRATION TEST (Standalone)"
echo "=================================================="
echo "Working Directory: $(pwd)"
echo ""

# Check if Go is available
if ! command -v go &> /dev/null; then
    echo "❌ Error: Go is not installed or not in PATH"
    exit 1
fi

echo "Go version: $(go version)"
echo ""

# Check if Tendis binary exists
if [ ! -f "build/bin/tendisplus" ]; then
    echo "❌ Error: Tendis binary not found at build/bin/tendisplus"
    exit 1
fi

# Navigate to integration test directory
if [ ! -d "src/tendisplus/integrate_test" ]; then
    echo "❌ Error: Integration test directory not found"
    exit 1
fi

cd src/tendisplus/integrate_test

echo "=================================================="
echo "Setting up Go environment..."
echo "=================================================="

# Set Go environment
export GO111MODULE=on
export GOPATH=$(pwd)/gopath
export PATH=$PATH:$(pwd)/../../../build/bin:$(pwd)/../../../bin

echo "GOPATH: $GOPATH"
echo ""

# Download dependencies
echo "Downloading Go dependencies..."
go get integrate_test/util
go mod tidy 2>&1 | grep -v "go.mod file indicates go" || true
go mod download

# Patch ngaut/log for ARM64 if needed
if [ -d "$GOPATH/pkg/mod/github.com/ngaut" ]; then
    echo "Checking for ARM64 compatibility patch..."
    chmod -R u+w "$GOPATH/pkg/mod" 2>/dev/null || true
    TARGET_FILE=$(find "$GOPATH/pkg/mod/github.com/ngaut" -name "crash_unix.go" | head -n 1)
    if [ -f "$TARGET_FILE" ]; then
        if grep -q "syscall.Dup2" "$TARGET_FILE"; then
            echo "Applying ARM64 compatibility patch to ngaut/log..."
            sed -i 's/syscall\.Dup2(int(f\.Fd()), 2)/syscall.Dup3(int(f.Fd()), 2, 0)/g' "$TARGET_FILE"
            echo "✅ Patch applied"
        else
            echo "✅ Already patched or not needed"
        fi
    fi
fi

echo ""
echo "=================================================="
echo "Running Go Integration Tests..."
echo "=================================================="
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up test processes..."
    
    # Run clear.sh to kill test processes
    if [ -f "./clear.sh" ]; then
        bash ./clear.sh 2>/dev/null || true
    fi
    
    # Clean test artifacts
    rm -rf m*_* s*_* running slowlog benchmark_*.log predixy_* dst_* src_* redis-sync* sync* dts.log jeprof* 2>/dev/null || true
    cd dts 2>/dev/null && rm -rf ./m*_* ./s*_* ./t*_* ./running 2>/dev/null || true
    cd .. 2>/dev/null || true
    
    echo "Cleanup complete."
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Clean previous test results
rm -f all.log all_tmp.log gotest_run.log normaltest.log
rm -rf running

# Test selection - allow override via environment variable
TEST_TYPE="${GO_TEST_TYPE:-normaltest}"

echo "Test type: $TEST_TYPE"
echo "Options: all, normaltest, normaltest-part1, normaltest-part2, normaltest-part3, versiontest"
echo ""

# Run tests
echo "Starting test execution..."
echo "(This may take several minutes, showing progress below)"
echo ""
bash ./gotest.sh "$TEST_TYPE" 2>&1 | tee gotest_run.log

# Check results
echo ""
echo "=================================================="
echo "Checking test results..."
echo "=================================================="
echo ""

LOGFILE="${TEST_TYPE}.log"

if [ ! -f "$LOGFILE" ]; then
    echo "❌ Error: Log file $LOGFILE not found!"
    echo ""
    echo "--- gotest_run.log output (first 50 lines) ---"
    head -n 50 gotest_run.log 2>/dev/null || echo "No run log found"
    echo ""
    echo "--- gotest_run.log output (last 20 lines) ---"
    tail -n 20 gotest_run.log 2>/dev/null || echo "No run log found"
    exit 1
fi

# Count passed tests
PASS_COUNT=$(grep -c "go passed" "$LOGFILE" 2>/dev/null || echo "0")

if [ "$PASS_COUNT" -eq "0" ] || [ -z "$PASS_COUNT" ]; then
    echo "❌ Go Integration Tests FAILED (no tests passed)"
    echo ""
    echo "--- Test log (last 100 lines) ---"
    tail -n 100 "$LOGFILE"
    echo ""
    echo "--- Execution log (first 50 lines) ---"
    head -n 50 gotest_run.log
    echo ""
    echo "--- Execution log (last 30 lines) ---"
    tail -n 30 gotest_run.log
    exit 1
else
    echo "✅ Go Integration Tests PASSED"
    echo ""
    echo "Total tests passed: $PASS_COUNT"
    echo ""
    
    # Show test summary
    echo "Test results:"
    grep "go passed" "$LOGFILE" 2>/dev/null | head -n 20 || echo "(no detailed results)"
    
    if [ "$PASS_COUNT" -gt "20" ]; then
        echo "... and $((PASS_COUNT - 20)) more tests"
    fi
fi

echo ""
echo "=================================================="
echo "Test completed successfully!"
echo "=================================================="
echo ""
echo "Logs:"
echo "  - Test results: $(pwd)/$LOGFILE"
echo "  - Execution log: $(pwd)/gotest_run.log"
