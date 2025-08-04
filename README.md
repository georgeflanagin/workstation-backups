# Procedure for backingup the workstations in the Parish Lab

As with other administrative functions, these are assigned to be run by `zeus@jonimitchell` 


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

## The continuous backup shell script

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
    32
```
