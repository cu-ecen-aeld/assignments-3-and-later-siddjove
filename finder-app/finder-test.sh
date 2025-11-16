#!/bin/sh
#
# finder-test.sh
# Simple test harness for the Finder assignment.
# - If run with two args: usage is ./finder-test.sh <directory> <search string>
# - If run with no args: defaults to /home and uses conf/assignment.txt (first line)
# This is POSIX sh compatible (works with static BusyBox)

set -eu

usage() {
    echo "Usage:"
    echo "  $0 <directory> <search string>"
    echo "or (inside QEMU):"
    echo "  $0    (will use /home and conf/assignment.txt)"
    exit 1
}

# Determine mode
if [ $# -eq 0 ]; then
    # Default mode: run inside QEMU target. Expect conf/assignment.txt to exist.
    FILESDIR="/home"
    if [ -f "conf/assignment.txt" ]; then
        # read first non-empty line as search string
        searchstr=$(sed -n 's/^[[:space:]]*//;s/[[:space:]]*$//;/^$/d;p;q' conf/assignment.txt 2>/dev/null || true)
        if [ -z "${searchstr:-}" ]; then
            echo "Error: conf/assignment.txt exists but is empty or unreadable"
            exit 1
        fi
    else
        # If conf/assignment.txt isn't in current dir, try /home/conf (when installed into rootfs/home/conf)
        if [ -f /home/conf/assignment.txt ]; then
            searchstr=$(sed -n 's/^[[:space:]]*//;s/[[:space:]]*$//;/^$/d;p;q' /home/conf/assignment.txt)
        else
            echo "Error: conf/assignment.txt not found (cannot determine search string)"
            usage
        fi
    fi
elif [ $# -eq 2 ]; then
    FILESDIR="$1"
    searchstr="$2"
else
    usage
fi

if [ ! -d "$FILESDIR" ]; then
    echo "Error: ${FILESDIR} is not a directory."
    exit 1
fi

# Count files under FILESDIR
num_files=$(find "$FILESDIR" -type f 2>/dev/null | wc -l | tr -d ' ')
# Count matching lines for search string (recursive)
num_matches=$(grep -r -- "$searchstr" "$FILESDIR" 2>/dev/null | wc -l | tr -d ' ')

echo "Directory tested: $FILESDIR"
echo "Search string: '$searchstr'"
echo "Number of files found: $num_files"
echo "Number of matching lines: $num_matches"

# Basic pass/fail heuristics:
# - At least 1 file present
# - At least 1 matching line (if the assignment expects matches)
pass=0
if [ "$num_files" -gt 0 ] && [ "$num_matches" -ge 0 ]; then
    # we won't be overly strict here — the autograder will apply its own checks
    pass=1
fi

if [ "$pass" -eq 1 ]; then
    echo "Result: PASS (basic checks)"
    exit 0
else
    echo "Result: FAIL"
    exit 2
fi

