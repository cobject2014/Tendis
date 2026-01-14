#!/bin/bash
set -e

# Define Workspace
TENDIS_HOME="/src/Tendis"
if [ -d "/src/Tendis" ]; then
    cd "/src/Tendis"
elif [ -d "$(pwd)/temp_tendis" ]; then
    cd "$(pwd)/temp_tendis"
elif [ -f "testall.sh" ]; then
    echo "Running in current directory"
else
    echo "Error: Cannot find Tendis source directory (testall.sh not found)"
    exit 1
fi

echo "=================================================="
echo "   TENDIS FULL TEST SUITE RUNNER"
echo "=================================================="
echo "Working Directory: $(pwd)"

GLOBAL_EXIT_CODE=0

# Helper function to check logs
check_log() {
    local logfile=$1
    local success_pattern=$2
    local failure_pattern=$3
    local name=$4

    echo "Checking $name results in $logfile..."
    
    local failed=0
    
    if [ ! -f "$logfile" ]; then
        echo "❌ Error: Log file $logfile not found!"
        return 1
    fi

    if [ -n "$failure_pattern" ]; then
        if grep -qE "$failure_pattern" "$logfile"; then
             echo "❌ $name FAILED (Found failure pattern '$failure_pattern')"
             grep -E "$failure_pattern" "$logfile" | head -n 20
             failed=1
        fi
    fi

    if [ -n "$success_pattern" ]; then
        if grep -q "$success_pattern" "$logfile"; then
            echo "✅ $name PASSED (Found success pattern '$success_pattern')"
        else
            if [ $failed -eq 0 ]; then
                echo "❌ $name FAILED (Missing success pattern '$success_pattern')"
            fi
            failed=1
        fi
    fi

    if [ $failed -eq 1 ]; then
        echo "--- Last 50 lines of $logfile ---"
        tail -n 50 "$logfile"
        return 1
    fi
    return 0
}

# 1. Unit Tests
echo "--------------------------------------------------"
echo "[1/6] Running Unit Tests (unittest.sh)..."
# Clean previous log
rm -f unittest.log
# Run script
bash ./unittest.sh > /dev/null 2>&1 || true

if grep -E "Expected|FAILED|Check failure stack trace|core dumped|Failure|INVARIANT|heap-use-after-free|heap-buffer-overflow" unittest.log > /dev/null; then
    echo "❌ Unit Tests FAILED"
    grep -E "Expected|FAILED|Check failure stack trace|core dumped|Failure|INVARIANT" unittest.log | head -n 20
    # Continue to next tests but mark failure
    GLOBAL_EXIT_CODE=1
else
    echo "✅ Unit Tests PASSED"
fi

# 2. Replication Test
echo "--------------------------------------------------"
echo "[2/6] Running Repl Test (build/bin/repl_test)..."
rm -f repl_test.log
./build/bin/repl_test > repl_test.log 2>&1 || true
if ! check_log "repl_test.log" "PASSED" "" "Repl Test"; then
    GLOBAL_EXIT_CODE=1
fi

# 3. Restore Test
echo "--------------------------------------------------"
echo "[3/6] Running Restore Test (build/bin/restore_test)..."
rm -f restore_test.log
./build/bin/restore_test > restore_test.log 2>&1 || true
if ! check_log "restore_test.log" "PASSED" "" "Restore Test"; then
    GLOBAL_EXIT_CODE=1
fi

# 4. Cluster Test
echo "--------------------------------------------------"
echo "[4/6] Running Cluster Test (build/bin/cluster_test)..."
rm -f cluster_test.log
./build/bin/cluster_test > cluster_test.log 2>&1 || true
if ! check_log "cluster_test.log" "PASSED" "" "Cluster Test"; then
    GLOBAL_EXIT_CODE=1
fi

# 5. Redis Protocol Tests
echo "--------------------------------------------------"
echo "[5/6] Running Redis Compatibility Tests (redistest.sh)..."
rm -f redistest.log
bash ./redistest.sh > redistest_output.log 2>&1 || true

if grep -Eq "\[err|\[exception|49merr|49mexception" redistest.log; then
    echo "❌ Redis Compatibility Tests FAILED"
    grep -E "\[err|\[exception|49merr|49mexception" redistest.log | head -n 20
    echo "See redistest.log for full details."
    GLOBAL_EXIT_CODE=1
else
    echo "✅ Redis Compatibility Tests PASSED"
fi

# 6. Go Tests
echo "--------------------------------------------------"
echo "[6/6] Running Go Integration Tests (gotest.sh)..."
cd src/tendisplus/integrate_test
rm -f all.log
bash ./gotest.sh all > gotest_run.log 2>&1 || true
cd - > /dev/null

GOTEST_LOG="src/tendisplus/integrate_test/all.log"
GOTEST_RUN_LOG="src/tendisplus/integrate_test/gotest_run.log"

if ! check_log "$GOTEST_LOG" "go passed" "" "Go Integration Tests"; then
    echo "⚠️  Showing compilation/execution log (gotest_run.log) due to failure:"
    if [ -f "$GOTEST_RUN_LOG" ]; then
        cat "$GOTEST_RUN_LOG" | head -n 50
        echo "..."
        tail -n 20 "$GOTEST_RUN_LOG"
    else
        echo "gotest_run.log not found."
    fi
    GLOBAL_EXIT_CODE=1
fi 

echo "=================================================="
if [ $GLOBAL_EXIT_CODE -eq 0 ]; then
    echo "🎉 ALL TESTS COMPLETED SUCCESSFULLY"
else
    echo "⚠️  SOME TESTS FAILED"
fi
echo "=================================================="
exit $GLOBAL_EXIT_CODE
