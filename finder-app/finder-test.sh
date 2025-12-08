#!/bin/sh
#
# finder-test.sh
# A4-compatible test harness.
# - If run with two args: ./finder-test.sh <directory> <search string>
# - If run with no args: uses /etc/finder-app/conf/assignment.txt
# Assumes:
#   - finder.sh is in PATH (e.g. /usr/bin/finder.sh)
#   - config file defines filesdir and searchstr
#   - Output of finder.sh is written to /tmp/assignment4-result.txt

set -eu

OUTPUT_FILE="/tmp/assignment4-result.txt"
CONF_DIR="/etc/finder-app/conf"
ASSIGNMENT_CONF="${CONF_DIR}/assignment.txt"

usage() {
    echo "Usage:"
    echo "  $0 <directory> <search string>"
    echo "or:"
    echo "  $0    (uses ${ASSIGNMENT_CONF})"
    exit 1
}

# Ensure finder.sh is available
if ! command -v finder.sh >/dev/null 2>&1; then
    echo "Error: finder.sh not found in PATH"
    exit 1
fi

FILESDIR=""
searchstr=""

if [ $# -eq 0 ]; then
    # No args: load config file
    if [ ! -f "${ASSIGNMENT_CONF}" ]; then
        echo "Error: ${ASSIGNMENT_CONF} not found"
        exit 1
    fi

    # shellcheck source=/dev/null
    . "${ASSIGNMENT_CONF}"

    FILESDIR="${filesdir:-${FILES_DIR:-}}"
    searchstr="${searchstr:-${SEARCH_STR:-}}"

    if [ -z "${FILESDIR}" ] || [ -z "${searchstr}" ]; then
        echo "Error: ${ASSIGNMENT_CONF} must define filesdir and searchstr"
        exit 1
    fi

    # 🔴 IMPORTANT: for A4, create filesdir if it doesn't exist
    if [ ! -d "${FILESDIR}" ]; then
        mkdir -p "${FILESDIR}"
    fi
elif [ $# -eq 2 ]; then
    FILESDIR="$1"
    searchstr="$2"
else
    usage
fi

if [ ! -d "${FILESDIR}" ]; then
    echo "Error: ${FILESDIR} is not a directory."
    exit 1
fi

echo "Running finder.sh on:"
echo "  Directory    : ${FILESDIR}"
echo "  Search string: '${searchstr}'"
echo "  Output file  : ${OUTPUT_FILE}"

# Run finder.sh and capture its output into /tmp/assignment4-result.txt
if ! finder.sh "${FILESDIR}" "${searchstr}" | tee "${OUTPUT_FILE}"; then
    echo "finder.sh reported failure"
    exit 2
fi

echo "finder-test.sh completed successfully"
exit 0
