#!/usr/bin/env bash

# Usage: file_history.sh REPO_PATH FILE_PATH

# This program prints every revision of the file passed as the second argument.
# Each line of every commit of the file is printed, with the date of the commit
# appended to the file. The date field is printed as a UNIX timestamp. The
# header from HEAD's version of the file is printed to stdout as the first
# line, and ",date_commit" is appended to it to describe the new field added.
# Note that the value of `date_commit` is the authorship date, which for most
# cases, except those involving rebasing and a few other scenarios, is 
# equivalent to the commit date.
#
# GNU Parallel is required in order for this script to work. Furthermore, the 
# file must be version-controlled by Git.
#
# Information on how to install GNU Parallel can be found here:
#   https://www.gnu.org/software/parallel/
#
# To customize the modifications made by the script, refer to documentation for
# the following commands:
#
# - git submodule
# - git cat-file
# - git log
#
# which can be accessed by typing `git help [command name]`

TARGET_FILE="$2"   # The path file we want to see the revisions of
ENCLOSING_DIR="$1" # The path of the git repository
OLD_WD=`pwd`       # The old working directory

# Go into the submodule, so that arguments to 'git cat-file' won't be
# garbled
cd "$ENCLOSING_DIR"

# Print a list of every {hash},{timestamp} of this file
# Since the above ^ is technically a .csv file, treat it as such.
# Then, for each line, print the file associated with that commit hash.
# Delete its first line, since that is merely a header, and append the date
# of the commit as the final column in the "csv".
echo "$(head -n1 $TARGET_FILE),date_commit"
git log --pretty='%h,%at' -- $TARGET_FILE | \
  parallel --csv \
    git cat-file -p '{1}:'"$TARGET_FILE" '|' \
    sed -e '1d' -e 's/$/,{2}/' '|' \
    sed -e "'\$a\'"

cd "$OLD_WD"
