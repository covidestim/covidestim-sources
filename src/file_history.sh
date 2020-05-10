#!/usr/bin/env bash
# This program prints every revision of the file passed as the first argument.
# Each line of every commit of the file is printed, with the date of the commit
# appended to the file. The date field is printed as ',YYYY-MM-DD'.
#
# GNU Parallel is required in order for this script to work. Furthermore, the 
# file must be version-controlled by Git.
#
# To customize the modifications made by the script, refer to documentation for
# the following commands:
#
# - git submodule
# - git cat-file
# - git log

# The file we want to see the revisions of
TARGET_FILE="$2"
ENCLOSING_DIR="$1"
OLD_WD=`pwd`

# Go into the submodule, so that arguments to 'git cat-file' won't be
# garbled
cd "$ENCLOSING_DIR"

# Print a list of every {hash},{YYYY-MM-DD} of this file
# Since the above ^ is technically a .csv file, treat it as such
# Then, for each line, print the file associated with that commit hash
# Delete its first line, since that is merely a header, and append the date
# of the commit as the final column in the "csv"
echo "$(head -n1 $TARGET_FILE),date_commit"
git log --pretty='%h,%at' -- $TARGET_FILE | \
  parallel --csv \
    git cat-file -p '{1}:'"$TARGET_FILE" '|' \
    sed -e '1d' -e 's/$/,{2}/' '|' \
    sed -e "'\$a\'"

cd "$OLD_WD"
