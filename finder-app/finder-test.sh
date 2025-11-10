#!/bin/sh
# Ensure writer is built before running tests
make clean
make

# Tester script for assignment 1 and assignment 2
# Author: Siddhant Jajoo

set -e
set -u

NUMFILES=10
WRITESTR=AELD_IS_FUN
WRITEDIR=/tmp/aeld-data
username=$(cat conf/username.txt)

if [ $# -lt 3 ]
then
    echo "Using default value ${WRITESTR} for string to write"
    if [ $# -lt 1 ]
    then
        echo "Using default value ${NUMFILES} for number of files to write"
    else
        NUMFILES=$1
    fi
else
    NUMFILES=$1
    WRITESTR=$2
    WRITEDIR=/tmp/aeld-data/$3
fi

# Clean up previous run
rm -rf "${WRITEDIR}"
mkdir -p "${WRITEDIR}"

echo "${WRITEDIR} created"

# Write files using the C writer program
for i in $(seq 1 $NUMFILES)
do
    ./writer "${WRITEDIR}/${username}${i}.txt" "${WRITESTR}"
done

# Verify that finder.sh exists and is executable
if [ ! -f ./finder.sh ]; then
    echo "Error: finder.sh not found in finder-app directory"
    exit 1
fi

chmod +x ./finder.sh

# Run finder.sh to count matches
OUTPUTSTRING=$(./finder.sh "${WRITEDIR}" "${WRITESTR}")

# Expected output
EXPECTEDOUTPUT="The number of files are ${NUMFILES} and the number of matching lines are ${NUMFILES}"

echo "${OUTPUTSTRING}" | grep "${EXPECTEDOUTPUT}" > /dev/null

if [ $? -eq 0 ]; then
    echo "success"
else
    echo "error: Expected '${EXPECTEDOUTPUT}' but got '${OUTPUTSTRING}'"
    exit 1
fi

