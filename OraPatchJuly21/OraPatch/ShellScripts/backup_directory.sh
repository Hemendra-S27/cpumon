#!/bin/bash

# backup_directory.sh
#
# Description:
#   This script creates a backup of a specified directory. The backup is created
#   as a tar file, which is then compressed using gzip. The script checks whether
#   the directory and the backup location exist, whether the backup location is
#   writable, and whether there is enough space in the backup location to store
#   the backup. It also checks if the tar file creation was successful. The tar
#   file is named based on the name of the directory and the current date and time.
#
# Usage:
#   backup_directory.sh --BkpDir <directory_to_backup> --BkpLoc <backup_location>
#
# Options:
#   -BkpDir   Directory to backup.
#   -BkpLoc   Location where the backup should be stored.
#
# Example:
#   backup_directory.sh --BkpDir /home/user/mydir --BkpLoc /mnt/backup
#
#!/bin/bash

# Log location
log_path="/tmp"
log_file="${log_path}/${0%.*}_$(hostname)_$(date +%Y%m%d%H%M%S).log"

# Function to log error messages
function LOG_ERROR() {
  timestamp=$(date "+%Y-%m-%d %H:%M:%S %Z")
  script_name=${BASH_SOURCE[1]}
  line_number=$1
  error_message=$2
  echo "ERROR:: ${timestamp}:: Error in ${script_name} at line ${line_number}:: ${error_message}" | tee -a "${log_file}"
  #echo "ERROR:: ${timestamp}:: Error in ${script_name} at line ${line_number}:: ${error_message}" | tee -a "${log_file}" >/dev/null
}

# Function to log informative messages
function LOG_MESSAGE() {
  timestamp=$(date "+%Y-%m-%d %H:%M:%S %Z")
  out_message=$1
  echo "MESSAGE:: ${timestamp}:: $out_message" | tee -a "${log_file}"
  #echo "MESSAGE:: ${timestamp}:: $out_message" | tee -a "${log_file}" >/dev/null
}

# Function to log script results
function LOG_RESULT() {
  timestamp=$(date "+%Y-%m-%d %H:%M:%S %Z")
  out_result=$1
  echo "RESULT:: ${timestamp}:: $out_result" | tee -a "${log_file}"
  #echo "RESULT:: ${timestamp}:: $out_result" | tee -a "${log_file}" >/dev/null
}

# Function to display usage
usage() {
  LOG_ERROR $LINENO "Invalid usage. Usage: $0 --BkpDir <directory_to_backup> --BkpLoc <backup_location>"
  exit 1
}

# Initialize variables
BKP_DIR=""
BKP_LOC=""

# Process command line options
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -BkpDir)
      BKP_DIR="$2"
      shift
      shift
      ;;
    -BkpLoc)
      BKP_LOC="$2"
      shift
      shift
      ;;
    *)
      LOG_ERROR $LINENO "Invalid option: $1"
      usage
      shift
      ;;
  esac
done


# If directory or backup location is not provided, log error and exit
if [ -z "$BKP_DIR" ] || [ -z "$BKP_LOC" ]; then
  usage
fi

# Backup function
backup_directory() {
  DIRECTORY=$1
  BACKUP_LOCATION=$2
  TIMESTAMP=$(date +%Y%m%d%H%M%S)
  DIRNAME=$(basename "$DIRECTORY")
  BACKUP_FILE="$BACKUP_LOCATION"/"$DIRNAME"_"$TIMESTAMP".tar

  if [ -d "$DIRECTORY" ]; then
    # Check if backup location exists
    if [ ! -d "$BACKUP_LOCATION" ]; then
      LOG_ERROR $LINENO "Backup location does not exist."
      exit 1
    fi

    # Check if backup location is writable
    if [ ! -w "$BACKUP_LOCATION" ]; then
      LOG_ERROR $LINENO "Backup location is not writable."
      exit 1
    fi

    # Estimate directory size in KB
    DIR_SIZE=$(du -sk "$DIRECTORY" | cut -f1)

    # Check if there is enough space in the backup location
    AVAILABLE_SPACE=$(df -k "$BACKUP_LOCATION" | tail -1 | awk '{print $4}')
    if [ "$AVAILABLE_SPACE" -lt "$DIR_SIZE" ]; then
      LOG_ERROR $LINENO "Not enough space in backup location."
      exit 1
    fi

    LOG_MESSAGE "Directory exists. Taking tar backup..."
    #tar -cvf "$BACKUP_FILE" "$DIRECTORY" 2>&1 | tee -a "$log_file"
    #tar -cvf "$BACKUP_FILE" "$DIRECTORY" 2>&1 | tee "$log_file"
    tar -cvf "$BACKUP_FILE" "$DIRECTORY" >> "$log_file" 2>&1

    # Verify if the tar file is valid
    tar -tvf "$BACKUP_FILE" > /dev/null 2>&1
    TAR_STATUS=$?
    if [ $TAR_STATUS -ne 0 ]; then
      LOG_ERROR $LINENO "Tar file is invalid. Possibly due to interruption during creation. Please try again."
      exit 1
    fi

    # If tar file exists, then zip it
    if [ -f "$BACKUP_FILE" ]; then
      LOG_MESSAGE "Tar file created and verified. Creating zip..."
      #gzip "$BACKUP_FILE"
      #gzip "$BACKUP_FILE" 2>&1 | tee -a "$log_file"
      #gzip "$BACKUP_FILE" 2>&1 | tee "$log_file"
       gzip "$BACKUP_FILE" >> "$log_file" 2>&1
    else
      LOG_ERROR $LINENO "Tar file creation failed."
      exit 1
    fi

    # Return success status
    return 0
  else
    LOG_ERROR $LINENO "Directory does not exist."
    exit 1
  fi
}

# Call the function and log result
if backup_directory "$BKP_DIR" "$BKP_LOC"; then
  LOG_RESULT "Backup process completed successfully."
  exit 0
else
  LOG_ERROR $LINENO "Backup process failed."
  exit 1
fi
