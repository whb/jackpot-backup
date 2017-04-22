#! /bin/bash

### DO NOT EDIT THIS FILE

set -e

CURRENT_PATH=`dirname $0`

source $CURRENT_PATH/conf.sh
source $CURRENT_PATH/lib/gnudate.sh

NOW=`gnudate "+%m-%d-%Y_%H-%M-%S"`
CURRENT_MONTH=`gnudate -d "$D" '+%m'`
CURRENT_YEAR=`gnudate -d "$D" '+%Y'`

# Create temp backup directory
mkdir -p /tmp/db_backups/${NOW}

### UPDATE LOGIC FOR THIS COMMAND IN ./conf.sh

# Pass in backup directory to the user-defined main_backup function
main_backup /tmp/db_backups/${NOW}

### END UPDATE

# Tar everything in the new backup folder, and store it in backups/daily
tar -C /tmp/db_backups -zcvf ${CURRENT_PATH}/backups/daily/${NOW}.tar.gz ${NOW}

# If it's the first backup of the month, store it in backups/monthly
NUM_CURRENT_MONTHLY_BACKUPS=`find ${CURRENT_PATH}/backups/monthly | grep "${CURRENT_MONTH}\-[0-9]\{1,2\}\-${CURRENT_YEAR}_.*\.tar\.gz" | wc -l`
if  [ "$NUM_CURRENT_MONTHLY_BACKUPS" -eq "0" ];
then
  cp ${CURRENT_PATH}/backups/daily/${NOW}.tar.gz ${CURRENT_PATH}/backups/monthly/${NOW}.tar.gz;
fi

# If it's the first backup of the year, store it in backups/yearly
NUM_CURRENT_YEARLY_BACKUPS=`find ${CURRENT_PATH}/backups/yearly | grep "[0-9]\{1,2\}\-[0-9]\{1,2\}\-${CURRENT_YEAR}_.*\.tar\.gz" | wc -l`
if  [ "$NUM_CURRENT_YEARLY_BACKUPS" -eq "0" ];
then
  cp ${CURRENT_PATH}/backups/daily/${NOW}.tar.gz ${CURRENT_PATH}/backups/yearly/${NOW}.tar.gz;
fi

# Delete temp backup directory
rm -r /tmp/db_backups/${NOW}

# Delete daily backups older than 7 days
find ${CURRENT_PATH}/backups/daily/. -mtime +7 -name "*.tar.gz" -exec bash -c 'rm "$0"' {} \;

# Delete monthly backups older than 7 months, or 215 days
find ${CURRENT_PATH}/backups/monthly/. -mtime +215 -name "*.tar.gz" -exec bash -c 'rm "$0"' {} \;

# Delete yearly backups older than 7 years, or 2557 days
find ${CURRENT_PATH}/backups/yearly/. -mtime +2557 -name "*.tar.gz" -exec bash -c 'rm "$0"' {} \;

# Get list of all daily backup files
TOTAL_DAILY_BACKUPS=`find ${CURRENT_PATH}/backups/daily/. -name "*.tar.gz" | wc -l`

# Sync the backups to AWS - only if there are daily backups in the dir
# If there are no daily backups, that's a sign of a problem, so we don't want to sync
if  [ "$TOTAL_DAILY_BACKUPS" -ne "0" ] &&
    [ -n "$AWS_PATH" ] &&
    [ -n "$S3_BUCKET" ];
then
  ${AWS_PATH} s3 sync ${CURRENT_PATH}/backups/. s3://${S3_BUCKET} --delete --sse
fi