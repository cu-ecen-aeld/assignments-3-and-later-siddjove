#!/bin/sh
# finder.sh
# Author: Siddjove

filesdir=$1
searchstr=$2

# Validate input
if [ $# -ne 2 ]; then
    echo "Error: Two arguments required. Usage: $0 <filesdir> <searchstr>"
    exit 1
fi

# Check if directory exists
if [ ! -d "$filesdir" ]; then
    echo "Error: Directory $filesdir does not exist"
    exit 1
fi

# Count total files and matching lines
num_files=$(find "$filesdir" -type f | wc -l)
num_matches=$(grep -r "$searchstr" "$filesdir" 2>/dev/null | wc -l)

# Print result
echo "The number of files are $num_files and the number of matching lines are $num_matches"

exit 0

