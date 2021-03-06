#! /bin/bash

### DO NOT EDIT THIS FILE

CURRENT_PATH=`dirname $0`

source $CURRENT_PATH/lib/log.sh
source $CURRENT_PATH/lib/onerror.sh

# Call onerror function if a command exits with a non-zero status.
trap onerror ERR

source $CURRENT_PATH/conf.sh
source $CURRENT_PATH/lib/gnudate.sh

NOW=`gnudate "+%m-%d-%Y_%H-%M-%S"`
CURRENT_MONTH=`gnudate -d "$D" '+%m'`
CURRENT_YEAR=`gnudate -d "$D" '+%Y'`

log "Beginning Jackpot Backup..."

# Create temp backup directory
mkdir -p /tmp/db_backups/${NOW}

### UPDATE LOGIC FOR THIS COMMAND IN ./conf.sh

log "Starting main_backup function..."
# Pass in backup directory to the user-defined main_backup function
main_backup /tmp/db_backups/${NOW}

log-success "Finished running main_backup function!"

### END UPDATE

log "Creating daily backup..."

# Tar everything in the new backup folder, and store it in backups/daily
tar -C /tmp/db_backups -zcvf ${CURRENT_PATH}/backups/daily/${NOW}.tar.gz ${NOW}

log-success "Finished creating daily backup!"

# If it's the first backup of the month, store it in backups/monthly
NUM_CURRENT_MONTHLY_BACKUPS=`find ${CURRENT_PATH}/backups/monthly | grep "${CURRENT_MONTH}\-[0-9]\{1,2\}\-${CURRENT_YEAR}_.*\.tar\.gz" | wc -l`
if  [ "$NUM_CURRENT_MONTHLY_BACKUPS" -eq "0" ];
then
  log "No backup has been found for this month. Creating one now..."
  cp ${CURRENT_PATH}/backups/daily/${NOW}.tar.gz ${CURRENT_PATH}/backups/monthly/${NOW}.tar.gz;
  log-success "Finished creating monthly backup!"
else
  log "There already exists a monthly backup for this month. Skipping..."
fi

# If it's the first backup of the year, store it in backups/yearly
NUM_CURRENT_YEARLY_BACKUPS=`find ${CURRENT_PATH}/backups/yearly | grep "[0-9]\{1,2\}\-[0-9]\{1,2\}\-${CURRENT_YEAR}_.*\.tar\.gz" | wc -l`
if  [ "$NUM_CURRENT_YEARLY_BACKUPS" -eq "0" ];
then
  log "No backup has been found for this year. Creating one now..."
  cp ${CURRENT_PATH}/backups/daily/${NOW}.tar.gz ${CURRENT_PATH}/backups/yearly/${NOW}.tar.gz;
  log-success "Finished creating yearly backup!"
else
  log "There already exists a yearly backup for this year. Skipping..."
fi

log "Deleting all outdated backups..."

# Delete temp backup directory
rm -r /tmp/db_backups/${NOW}

# Delete daily backups older than 7 days
find ${CURRENT_PATH}/backups/daily/. -mtime +7 -name "*.tar.gz" -exec bash -c 'rm "$0"' {} \;

# Delete monthly backups older than 7 months, or 215 days
find ${CURRENT_PATH}/backups/monthly/. -mtime +215 -name "*.tar.gz" -exec bash -c 'rm "$0"' {} \;

# Delete yearly backups older than 7 years, or 2557 days
find ${CURRENT_PATH}/backups/yearly/. -mtime +2557 -name "*.tar.gz" -exec bash -c 'rm "$0"' {} \;

log-success "Finished deleting outdated backups!"

# Perform user-defined after_backup() function - if it exists
if typeset -f after_backup > /dev/null; then
  log "Running after_backup function..."
  after_backup ${CURRENT_PATH}/backups/daily/${NOW}.tar.gz
  log-success "Finished running after_backup function!"
else
  log "No custom after_backup function found. Skipping..."
fi

# Get list of all daily backup files
TOTAL_DAILY_BACKUPS=`find ${CURRENT_PATH}/backups/daily/. -name "*.tar.gz" | wc -l`

# Sync the backups to remote sources - only if there are daily backups in the dir
# If there are no daily backups, that's a sign of a problem, so we don't want to sync
if  [ "$TOTAL_DAILY_BACKUPS" -ne "0" ];
then

  # Sync to S3 if the config is set
  if [ -n "$S3_BUCKET" ]; then
    log "Backing up to the AWS ${S3_BUCKET} S3 bucket..."
    ${AWS_PATH} s3 sync ${CURRENT_PATH}/backups/. s3://${S3_BUCKET} --delete --sse
    log-success "Done backing up to AWS S3!"
  else
    log "No configuration set to backup for AWS S3. Skipping..."
  fi

  # Sync to Google Cloud if the config is set
  if [ -n "$GOOGLE_CLOUD_BUCKET" ]; then
    log "Backing up to the Google Cloud ${GOOGLE_CLOUD_BUCKET} bucket..."
    ${GSUTIL_PATH} rsync -d -r ${CURRENT_PATH}/backups/. gs://${GOOGLE_CLOUD_BUCKET}
    log-success "Done backing up to Google Cloud!"
  else
    log "No configuration set to backup for Google Cloud. Skipping..."
  fi
else
  # No backups found - that's bad
  log-error "ERROR: Zero backups found in backups/daily. This is a problem.
  Aborting syncing with all remote services."
fi

log-success "Successfully Completed Jackpot Backup!"
