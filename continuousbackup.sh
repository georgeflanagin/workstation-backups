#!/bin/bash

export my_computers="aamy adam alexis boyi camryn cooper evan hamilton irene2 josh justin kevin khanh mayer michael sarah thais "

logdir=/var/log/continuousbackup
sudo mkdir -p "$logdir"
sudo chown zeus "$logdir"

while true; do
    logfile="$logdir/backup-$(date +%F).log"
    for host in $my_computers; do
        {
            # Be sure the workstation has the latest version
            # of the backup script.
            scp dailybackup.sh "$host:dailybackup.sh"
            echo "=== $(date '+%F %T') ==="
            echo "Starting backup for $host"
            ssh "$host" "./dailybackup.sh --do-it /home"
            rc=$?
            if [[ $rc -eq 0 ]]; then
                echo "Backup successful for $host"
            else
                echo "Backup FAILED for $host with exit code $rc"
            fi
            echo "Finished backup for $host"
            echo "Resting for one minute."
            sleep 60
            echo
        } >> "$logfile" 2>&1
    done
    echo "$(date '+%F %T') -- Cycle complete. Restarting after pause." >> "$logfile"
    sleep 300
done

