# Procedure for backup of the workstations in the Parish Lab

As with other administrative functions, these are assigned to be run by `zeus@jonimitchell`. JoniMitchell is the unified home of administrative functions for the Parish Lab. 

There are four parts of the system, and each is detailed in a section below:

1. The cron job that does the scheduling.
2. The shell script that orders the backups, and runs continuously.
3. The shell script on the workstations that performs the backup.
4. The list of files to backup/exclude, also present on each workstation.

## The crontab 

The backup system 
runs on the cron, and here is the line in Zeus's crontab:

```
0 17 * * * flock -n /home/zeus/.locks/continuousbackup.lock /home/zeus/continuousbackup.sh >/dev/null 2>&1 </dev/null
```

Cron-lingo is not always easy to grok, so here is the explanation:

`0 17 * * *` At 5pm, every day, of every month, regardless of the day of the week ...
`flock -n /home/zeus/.locks/continuousbackup.lock` flock (a standard Linux program) checks
to see if the file `/home/zeus/.locks/continuousbackup.lock` exists. If the file exists,
the program silently fails (`-n`). Otherwise, it creates the named file with an exclusive
lock (`LOCK_EX`), and then proceeds to do whatever you request, in this case, we want to
run the shell script, `/home/zeus/continuousbackup.sh`.

The point is to prevent running this script twice.

## The continuous backup shell script

### A word about the method. 

If there is nothing to backup, this script will run every 22 minutes: 1 minute
per workstation * 17 workstations, plus a five minute "rest" each trip through the loop.

An explanation of the more cryptic lines follows:

### continuousbackup.sh
```bash
     1	#!/bin/bash
     2
     3	export my_computers="aamy adam alexis boyi camryn cooper evan hamilton irene2 josh justin kevin khanh mayer michael sarah thais "
     4	
     5
     6	logdir=/var/log/continuousbackup
     7	sudo mkdir -p "$logdir"
     8	sudo chown zeus "$logdir"
     9
    10	while true; do
    11	    logfile="$logdir/backup-$(date +%F).log"
    12	    for host in $my_computers; do
    13	        {
    14	            echo "=== $(date '+%F %T') ==="
    15	            echo "Starting backup for $host"
    16	            ssh "$host" "./dailybackup.sh --do-it /home"
    17	            rc=$?
    18	            if [[ $rc -eq 0 ]]; then
    19	                echo "Backup successful for $host"
    20	            else
    21	                echo "Backup FAILED for $host with exit code $rc"
    22	            fi
    23	            echo "Finished backup for $host"
    24	            echo "Resting for one minute."
    25	            sleep 60
    26	            echo
    27	        } >> "$logfile" 2>&1
    28	    done
    29	    echo "$(date '+%F %T') -- Cycle complete. Restarting after pause." >> "$logfile"
    30	    sleep 300
    31	done
```

[3] This is the list of computers to cycle through.

[6-8] Creates a logfile directory for the logs, and the directory is owned by Zeus.

[10] This creates the continuous loop. `true` is always true.

[11] Create a new logfile.

[12] The inner loop. 

[16] The line that does the work. This script connects to each host, and the connection
information is in `~/.ssh/config`. The remote user is defined to be `root`.

[25] There is a one minute pause between each host backup. This is primarily to make the 
log file a little easier to read.

[27] All the `echo` statements get written to the logfile. 

[29-30] Wait five minutes to start again. 


## The daily backup shell script

This script is on all the computers being backed up. It is designed to get the information
about the locale programmatically, and it should not need modification. If you want to
backup a directory other than `/home`, then you can invoke it locally with the name of the
directory that you want to backup.

```
./dailybackup.sh --do-it /scratch
```

Following the script, there are explanations of the lines that may require them.

### dailybackup.sh
```
     1	#!/bin/bash
     2
     3	cd "$HOME"
     4
     5	if (return 0 2>/dev/null); then
     6	    echo "ERROR: This script must not be sourced. Run it instead:"
     7	    echo "  $0 [args]"
     8	    return 1
     9	fi
    10
    11	# User to receive the email.
    12	export OWNER=hpc@richmond.edu
    13
    14
    15	help_me=false
    16	for arg in "$@"; do
    17	    if [[ "$arg" == "-h" ]]; then
    18	        help_me=true
    19	        break
    20	    fi
    21	done
    22
    23	if "$help_me" ; then
    24	    cat<<EOF
    25	    NOTE: by default, this shell script only shows you what would happen,
    26	        but does not do the backup. You must include --do-it to have
    27	        the backup take place.
    28	        $0 -h
    29	            Show this message and exit
    30	        $0 {dir}
    31	            Defaults to "/home", and is the directory to backup.
    32	        $0 --do-it {dir}
    33	            Does the backup.
    34	EOF
    35	    exit 0
    36	fi
    37
    38	do_it=false
    39	for arg in "$@"; do
    40	    if [[ "$arg" == "--do-it" ]]; then
    41	        do_it=true
    42	        break
    43	    fi
    44	done
    45
    46	if [ -z "$1" ]; then
    47	    SOURCE="/home"
    48	else
    49	    SOURCE=${!#}
    50	fi
    51
    52	# if it does not start with a /, then it must be
    53	# an option or an invalid path.
    54	if [[ ! "$SOURCE" =~ /* ]]; then
    55	    SOURCE="/home"
    56
    57	    # Let's make sure it exists. Test without a trailing
    58	    # slash in case tab-completion put one there.
    59	elif [ ! -d "${SOURCE%/}" ]; then
    60	    echo "$SOURCE does not exist."
    61	fi
    62	# Make sure it ends in a / so that rsync will copy the contents.
    63	SOURCE="${SOURCE%/}/"
    64
    65	if ! $do_it; then
    66	    echo "Dry run only. Use --do-it to execute."
    67	    dry_run="--dry-run"
    68	else
    69	    echo "Executing backup ..."
    70	    dry_run=""
    71	fi
    72
    73
    74	###
    75	# To change the list of excluded files, put the cursor on the
    76	# file name below, and press gf
    77	###
    78	export EXCLUSIONS=rsync-excludes.txt
    79	if [ ! -f "$EXCLUSIONS" ]; then
    80	    echo "Could not find exclusions file: $EXCLUSIONS"
    81	    exit 1
    82	else
    83	    EXCLUSIONS="--exclude-from=$EXCLUSIONS"
    84	fi
    85
    86
    87	# -a : preserves times, owner ids, group ids
    88	#  v : verbose .. show what is going on.
    89	#  X : any extended attribute metadata
    90	#  A : any ACLs
    91
    92	export BACKUPARGS="-av"
    93
    94	# The (short) name of the computer running this script.
    95	export HOST=$(hostname -s 2>/dev/null)
    96	export DESTDIR="/mnt/everything/backup-testing/$HOST"
    97
    98	# The destination user is not always "root". The destination
    99	# might have an administrative user who is not named root.
   100
   101	export DESTINATION_HOST="root@141.166.186.1"
   102
   103	# Let's make each run clean.
   104	export OUTPUT=dailybackup.out
   105	export ERRORS=dailybackup.err
   106	rm -f "$OUTPUT"
   107	rm -f "$ERRORS"
   108
   109	# Let's make sure the storage is up and accessible.
   110	ssh -o ConnectTimeout=3 "$DESTINATION_HOST" true
   111	if [ $? -ne 0 ]; then
   112		mail -s "Could not backup $HOST. $DESTINATION_HOST not reachable." "$OWNER" </dev/null
   113		exit
   114	fi
   115
   116
   117	# Echo just for documentation.
   118	echo "rsync $BACKUPARGS $dry_run $EXCLUSIONS $SOURCE $DESTINATION_HOST:$DESTDIR >$OUTPUT 2>$ERRORS" | tee $OUTPUT
   119
   120	echo "Backup started: $(date)" >> $OUTPUT
   121	echo "Source: $SOURCE" >> $OUTPUT
   122	echo "Destination: $DESTINATION_HOST:$DESTDIR" >> $OUTPUT
   123	echo "Exclusions file: $EXCLUSIONS" >> $OUTPUT
   124	echo "----------------------------------------" >> $OUTPUT
   125
   126	nice -n 7 ionice -c 2 -n 7 rsync $BACKUPARGS $dry_run $EXCLUSIONS "$SOURCE" "$DESTINATION_HOST:$DESTDIR" >>$OUTPUT 2>$ERRORS
   127	RSYNC_EXIT=$?
   128
   129	if [ $RSYNC_EXIT -ne 0 ] || [ -s "$ERRORS" ]; then
   130	    {
   131	        echo "Rsync exit code: $RSYNC_EXIT"
   132	        echo "=== STDERR ==="
   133	        cat "$ERRORS"
   134	    } | mail -s "Backup on $HOST had problems" "$OWNER"
   135	fi
```

[3] It is always a good idea to establish the `$PWD` of a running script. This is
also where the list of exclusions is located.

[46-50] The directory to be backed up is the last argument.

[89-90] We backup to a UNIX computer running ZFS from Linux computers running XFS.
These two options do not make sense in the UNIX/ZFS environment.

[126] This is the command that executes the file transfer. Let's go through it.

`nice -n 7` Niceness runs from [0..19], where 0 is normal scheduling priority,
and 19 is as nice as a program can be. In this case, -7 is about half the priority
of the default. *NB: this is *CPU* niceness, and running nice avoids the congestion
of normal work.*

`ionice -c 2 -n 7` The nice levels are the same, and `ionice` also has classes of service.
Class 2 is known as "best effort," which is the normal I/O priority. Within that class, this
program is scheduled lower in priority.

`rsync` The program we are running.

`$BACKUPARGS` In our case, `-av`, meaning preserve time stamp info, traverse the directories,
and make a list of what files are transferred.

`$dry_run` If we are really transferring the files (*i.e.*, `--do-it`), this variable is null, otherwise
its value is `--dry-run`, meaning the program just describes what it *would* do.

`$EXCLUSIONS` References the exclusions file.

`"$SOURCE"` Where we are transferring files *from*.

`"$DESTINATION_HOST:$DESTDIR"` Where we are transferring files *to*.

`>>$OUTPUT` In this case, `dailybackup.out`

`2>$ERRORS` In this case, `dailybackup.err`

## The excluded files.

`rsync` is a flexible program, and it is a dependable way to transfer files in a 
backup situation. It is important to understand how it works to use it effectively.
Before `rsync` begins the transfer, it establishes contact with the remote computer
(.. assuming that you are transferring between computers. `rsync` works just as well
to copy or move files on a single host.), and builds a list of the files to be transferred.

Its operation can be considerably sped along by excluding scrap files such as files in
the browser cache. It is not so much that the files are large, but they are numerous
and often short lived. The speed of `rsync`'s operation is related to *the size of the lists
as well as the size of the files*. 

The following list excludes some of the major file space hogs.

### rysnc-excludes.txt
```
# Browser and application caches
.cache/
.mozilla/
.config/google-chrome/

# Development tools
.vscode*/
.config/
.conda/       # these files came from elsewhere
.docker/
.eclipse/ 
.git/         # presumably, the repos have a remote already.
.local/lib/
__pycache__/  # Compiled Python code of the parent directory.
containers/
*.iso

# Desktop environments
.gnome/
.zoom/

# Package managers and build tools
.npm/
.yarn/
.gradle/
.m2/
.cargo/
.rustup/

# System and user directories
.local/share/Trash/
.thumbnails/
snap/

# Gaming and virtualization
.steam/
.wine/
```
