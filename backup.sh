#!/bin/bash
# ------------------------------------------------------------
# Backup Settings
# ------------------------------------------------------------
# Rsync uses IP 
# First you have to create /var/log/backup folder

server=host.example.com
server_ip=1.2.3.4

ssh_port=22

max_days=7
max_weeks=4
max_months=1

# ------------------------------------------------------------
# Check if I am Running
# ------------------------------------------------------------
PDIR=${0%`basename $0`}
LCK_FILE=`basename $0`.lck
if [ -f "${LCK_FILE}" ]; then
  # The file exists so read the PID to see if it is still running
  MYPID=`head -n 1 "${LCK_FILE}"`
  TEST_RUNNING=`ps -p ${MYPID} | grep ${MYPID}`
  if [ -z "${TEST_RUNNING}" ]; then
    # The process is not running Echo current PID into lock file
    # echo "Not running"
    echo $$ > "${LCK_FILE}"
  else
    echo "`basename $0` is already running [${MYPID}]"
    exit 0
  fi
else
  # echo "Not running"
  echo $$ > "${LCK_FILE}"
fi

# ------------------------------------------------------------
# Find Last Backups and Initialize variables
# ------------------------------------------------------------
today=$(date +%Y%m%d)

# Get last backup directory
last_backup=`ls -1|grep ^day|tail -n1`;

# Get first backup
first_backup=`ls -1 -r|grep ^day|tail -n1`;

# Check how many daily backups exist
days_backup=`ls -1|grep ^day|wc -l`;

# Check how many weekly backups exist
weeks_backup=`ls -1|grep ^week|wc -l`;

# Check how many monthly backups exist
months_backup=`ls -1|grep ^month|wc -l`;

echo "START BACKUP for $server at $(date +%Y%m%d-%H:%M) " >>/var/log/backups/${server}_stout.log;

echo "- Total Daily backups $days_backup" >>/var/log/backups/${server}_stout.log;
echo "- Total Weekly backups $weeks_backup" >>/var/log/backups/${server}_stout.log;
echo "- Total Monthly backups $months_backup" >>/var/log/backups/${server}_stout.log;

echo "- First Daily backup $first_backup" >>/var/log/backups/${server}_stout.log;
echo "- Last Daily backup $last_backup" >>/var/log/backups/${server}_stout.log;
echo "- New Daily backup destination day_$today" >>/var/log/backups/${server}_stout.log;


# ------------------------------------------------------------
# Check if today backup pre-exist
# ------------------------------------------------------------
if [[ "$last_backup" == *"$today" ]]; then
  echo "ERROR - Last ($last_backup) and New (day_$today) date are the same you must sync manual ";
  echo "ERROR - Last ($last_backup) and New (day_$today) date are the same you must sync manual " >>/var/log/backups/${server}_stout.log;
  echo "----------------------------------------------------------------------------------------- " >>/var/log/backups/${server}_stout.log;
  rm -f "${LCK_FILE}"
  exit 0
fi


# ------------------------------------------------------------
# Start RSYNC
# ------------------------------------------------------------
echo "----------------------------------------------------------------------------------------- " >>/var/log/backups/${server}_stout.log;
echo "- START RSYNC for $server at $(date +%Y%m%d-%H:%M) hardlinks from $last_backup destination folder day_${date}" >>/var/log/backups/${server}_stout.log;

# SYNC with IP
ionice -c3 rsync -ahv --log-file=/var/log/backups/${server}_rsync.log --delete --link-dest=../$last_backup --exclude-from=backup_exclude --rsh="/usr/bin/ssh -p ${ssh_port}" root@${server_ip}:/ temp_rsync >> /var/log/backups/${server}_stout.log && mv temp_rsync day_${today}

echo "- END RSYNC for $server at $(date +%Y%m%d-%H:%M)" >>/var/log/backups/${server}_stout.log;
echo "----------------------------------------------------------------------------------------- " >>/var/log/backups/${server}_stout.log;

# ------------------------------------------------------------
# Incremental rotate folders
# ------------------------------------------------------------
echo "- Increment directories" >>/var/log/backups/${server}_stout.log;

# ------------------------------------------------------------
# Check if Last Weekly backup is older than a week
# ------------------------------------------------------------

# Check if we changed Week
if [[ "$max_weeks" -ge 1 ]]; then 
  last_weekly_backup=`ls -1|grep ^week|tail -n1`;
  diff_days=$(( ($(date -d "$today" +%s) - $(date -d "${last_weekly_backup//week_/}" +%s)) / 86400 ))

  if [[ "$diff_days" -ge 7 ]] || [ -z "$last_weekly_backup" ] ; then 
    echo "- Last Weekly difference $diff_days - Clone the Last day to weekly" >>/var/log/backups/${server}_stout.log;
    ionice -c3 rsync -ahv --link-dest=../day_${today} day_${today}/ week_${today}/ >>/var/log/backups/${server}_stout.log
  fi
fi

# Check if we changed Month
if [[ "$max_months" -ge 1 ]]; then 
  last_monthly_backup=`ls -1|grep ^month|tail -n1`;
  diff_days=$(( ($(date -d "$today" +%s) - $(date -d "${last_monthly_backup//month_/}" +%s)) / 86400 ))

  if [[ "$diff_days" -ge 30 ]] || [ -z "$last_monthly_backup" ] ; then 
    echo "- Last Monthly difference $diff_days - Clone the Last day to weekly" >>/var/log/backups/${server}_stout.log;
    ionice -c3 rsync -ahv --link-dest=../day_${today} day_${today}/ month_${today}/ >>/var/log/backups/${server}_stout.log
  fi
fi

# ------------------------------------------------------------
# Audit Clean old directories
# ------------------------------------------------------------

# Cleanup Daily backups
xn=0;
for x in $(ls -1 -r|grep ^day);do
  xn=$(($xn+1))
  if [ $xn -eq 1 ]; then
    fw=$x;
  fi
  if [ $xn -gt $max_days ]; then
    echo "Remove Directory "+$x >>/var/log/backups/${server}_stout.log 
    ionice -c3 rm -rf $x;
  fi
done

# Cleanup Weekly backups
xn=0;
for x in $(ls -1 -r|grep ^week);do
  xn=$(($xn+1))
  if [ $xn -eq 1 ]; then
    fw=$x;
  fi
  if [ $xn -gt $max_weeks ]; then
    echo "Remove Directory "+$x >>/var/log/backups/${server}_stout.log 
    ionice -c3 rm -rf $x;
  fi
done

# Cleanup Monthly backups
xn=0;
for x in $(ls -1 -r|grep ^month);do
  xn=$(($xn+1))
  if [ $xn -eq 1 ]; then
    fw=$x;
  fi
  if [ $xn -gt $max_months ]; then
    echo "Remove Directory "+$x >>/var/log/backups/${server}_stout.log 
    ionice -c3 rm -rf $x;
  fi
done


# ------------------------------------------------------------
# Done - Cleanup Lock File
# ------------------------------------------------------------
rm -f "${LCK_FILE}"
echo "END BACKUP for $server at $(date +%Y%m%d-%H:%M)" >>/var/log/backups/${server}_stout.log;
echo "----------------------------------------------------------------------------------------- " >>/var/log/backups/${server}_stout.log;

