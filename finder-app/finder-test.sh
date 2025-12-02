#!/bin/sh
#
# finder-test.sh
# Test harness for the Finder assignment, A4-compatible version.
# - If run with two args: usage is ./finder-test.sh <directory> <search string>
# - If run with no args: defaults to /home and uses /etc/finder-app/conf/assignment.txt
# Assumes:
#   - finder.sh is in the PATH (e.g. /usr/bin/finder.sh)
#   - config files are in /etc/finder-app/conf
#   - Output of finder.sh is written to /tmp/assignment4-result.txt

set -eu

OUTPUT_FILE="/tmp/assignment4-result.txt"
CONF_DIR="/etc/finder-app/conf"
ASSIGNMENT_CONF="${CONF_DIR}/assignment.txt"

usage() {
    echo "Usage:"
    echo "  $0 <directory> <search string>"
    echo "or:"
    echo "  $0    (uses /home and ${ASSIGNMENT_CONF})"
    exit 1
}

# Ensure finder.sh is available in PATH
if ! command -v finder.sh >/dev/null 2>&1; then
    echo "Error: finder.sh not found in PATH"
    exit 1
fi

# Determine mode
if [ $# -eq 0 ]; then
    FILESDIR="/home"

    if [ ! -f "${ASSIGNMENT_CONF}" ]; then
        echo "Error: ${ASSIGNMENT_CONF} not found"
        exit 1
    fi

    # Read first non-empty, trimmed line as search string
    searchstr=$(sed -n 's/^[[:space:]]*//;s/[[:space:]]*$//;/^$/d;p;q' "${ASSIGNMENT_CONF}" 2>/dev/null || true)
    if [ -z "${searchstr:-}" ]; then
        echo "Error: ${ASSIGNMENT_CONF} exists but is empty or unreadable"
        exit 1
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

echo "Running finder.sh on:"
echo "  Directory   : $FILESDIR"
echo "  Search string: '$searchstr'"
echo "  Output file : ${OUTPUT_FILE}"

# Run finder.sh and capture its output into /tmp/assignment4-result.txt
# Also echo it to the console using tee
if ! finder.sh "$FILESDIR" "$searchstr" | tee "${OUTPUT_FILE}"; then
    echo "finder.sh reported failure"
    exit 2
fi

echo "finder-test.sh completed successfully"
exit 0

