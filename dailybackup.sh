#!/bin/bash

cd "$HOME"

if (return 0 2>/dev/null); then
    echo "ERROR: This script must not be sourced. Run it instead:"
    echo "  $0 [args]"
    return 1
fi

# User to receive the email.
export OWNER=gflanagin@richmond.edu


help_me=false
for arg in "$@"; do
    if [[ "$arg" == "-h" ]]; then
        help_me=true
        break
    fi
done

if "$help_me" ; then
    cat<<EOF
    NOTE: by default, this shell script only shows you what would happen,
        but does not do the backup. You must include --do-it to have
        the backup take place.
        $0 -h
            Show this message and exit
        $0 {dir}
            Defaults to "/home", and is the directory to backup.
        $0 --do-it {dir}
            Does the backup.
EOF
    exit 0
fi

do_it=false
for arg in "$@"; do
    if [[ "$arg" == "--do-it" ]]; then
        do_it=true
        break
    fi
done

if [ -z "$1" ]; then
    SOURCE="/home"
else
    SOURCE=${!#}
fi

# if it does not start with a /, then it must be
# an option or an invalid path.
if [[ ! "$SOURCE" =~ /* ]]; then
    SOURCE="/home"

    # Let's make sure it exists. Test without a trailing
    # slash in case tab-completion put one there.
elif [ ! -d "${SOURCE%/}" ]; then
    echo "$SOURCE does not exist."
fi
# Make sure it ends in a / so that rsync will copy the contents.
SOURCE="${SOURCE%/}/"

if ! $do_it; then
    echo "Dry run only. Use --do-it to execute."
    dry_run="--dry-run"
else
    echo "Executing backup ..."
    dry_run=""
fi


###
# To change the list of excluded files, put the cursor on the
# file name below, and press gf
###
export EXCLUSIONS=rsync-excludes.txt
if [ ! -f "$EXCLUSIONS" ]; then
    echo "Could not find exclusions file: $EXCLUSIONS"
    exit 1
else
    EXCLUSIONS="--exclude-from=$EXCLUSIONS"
fi


# -a : preserves times, owner ids, group ids
#  v : verbose .. show what is going on.
#  X : any extended attribute metadata
#  A : any ACLs
#  inplace : write the files directly rather than doing "commits"
#  whole-file : skip rolling checksums; do them only once for the whole file.

export BACKUPARGS="-av --inplace --whole-file --preallocate"

# The (short) name of the computer running this script.
export HOST=$(hostname -s 2>/dev/null)
export DESTDIR="/mnt/everything/backup-testing/$HOST"

# The destination user is not always "root". The destination
# might have an administrative user who is not named root.

export DESTINATION_HOST="root@141.166.186.1"

# Let's make each run clean.
export OUTPUT=dailybackup.out
export ERRORS=dailybackup.err
rm -f "$OUTPUT"
rm -f "$ERRORS"

# Let's make sure the storage is up and accessible.
ssh -o ConnectTimeout=3 "$DESTINATION_HOST" true
if [ $? -ne 0 ]; then
	mail -s "Could not backup $HOST. $DESTINATION_HOST not reachable." "$OWNER" </dev/null
	exit
fi


# Echo just for documentation.
echo "rsync $BACKUPARGS $dry_run $EXCLUSIONS $SOURCE $DESTINATION_HOST:$DESTDIR >$OUTPUT 2>$ERRORS" | tee $OUTPUT

echo "Backup started: $(date)" >> $OUTPUT
echo "Source: $SOURCE" >> $OUTPUT
echo "Destination: $DESTINATION_HOST:$DESTDIR" >> $OUTPUT
echo "Exclusions file: $EXCLUSIONS" >> $OUTPUT
echo "----------------------------------------" >> $OUTPUT

nice -n 7 ionice -c 2 -n 7 rsync $BACKUPARGS $dry_run $EXCLUSIONS "$SOURCE" "$DESTINATION_HOST:$DESTDIR" >>$OUTPUT 2>$ERRORS
RSYNC_EXIT=$?

if [ $RSYNC_EXIT -ne 0 ] || [ -s "$ERRORS" ]; then
    {
        echo "Rsync exit code: $RSYNC_EXIT"
        echo "=== STDERR ==="
        cat "$ERRORS"
    } | mail -s "Backup on $HOST had problems" "$OWNER"
fi

