#!/bin/bash

################################################################################
# copy_opatch.sh
#
# Description:
#   This script performs a backup of a specified directory by creating a tar
#   archive and optionally unzipping a provided zip file. The backup process
#   moves the directory to a backup location, creates a tar archive, verifies
#   its validity, compresses it using gzip, and then unzips the provided zip file
#   back into the original directory. The script logs any errors, informative
#   messages, and the final result of the backup process.
#
# Usage:
#   copy_opatch.sh --OraHome <ORA_HOME> --BkpLoc <backup_location> --OpatchZip <opatch_OPATCH_ZIP>
#
# Options:
#   -OraHome   Directory to backup.
#   -BkpLoc   Location where the backup should be stored.
#   -OpatchZip  Zip file to unzip back into the original directory.
#
# Example:
#   copy_opatch.sh --OraHome /path/to/directory --BkpLoc /path/to/backup --OpatchZip /path/to/OpatchZip.zip
#
################################################################################

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
  LOG_ERROR $LINENO "Invalid usage. Usage: $0 -OraHome <ORA_HOME> -BkpLoc <backup_location> -OpatchZip <opatch_OPATCH_ZIP>"
  exit 1
}

# Initialize variables
ORA_HOME=""
BKP_LOC=""
OPATCH_ZIP=""

# Process command line options
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -OraHome)
      ORA_HOME="$2"
      shift
      shift
      ;;
    -BkpLoc)
      BKP_LOC="$2"
      shift
      shift
      ;;
        -OpatchZip)
      OPATCH_ZIP="$2"
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

# If directory or backup location or zip file is not provided, log error and exit
if [ -z "$ORA_HOME" ] || [ -z "$BKP_LOC" ] || [ -z "$OPATCH_ZIP" ]; then
  usage
fi

# Backup function
copy_opatch() {
  OH_GI_HOME=$1
  BACKUP_LOCATION=$2
  OPATCH_ZIP_PATH=$3
  OPATCH_DIR="$OH_GI_HOME"/"OPatch"
  DIRECTORY="$OPATCH_DIR"
  TIMESTAMP=$(date +%Y%m%d%H%M%S)
  DIRNAME=$(basename "$DIRECTORY")
  BACKUP_DIR_NAME="${DIRNAME}_bkp_${TIMESTAMP}"
  BACKUP_FILE="$BACKUP_LOCATION"/"$BACKUP_DIR_NAME".tar


  if [ -d "$DIRECTORY" ]; then
    # Extra check: Ensure we are working with the correct directory
    #LOG_MESSAGE "Confirmed. Working with the correct directory."

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

    # Move directory to backup location
    mv "$DIRECTORY" "$BACKUP_LOCATION/$BACKUP_DIR_NAME"
    if [ $? -ne 0 ]; then
      LOG_ERROR $LINENO "Moving directory failed."
      exit 1
    fi

    # Taking tar backup
    LOG_MESSAGE "Taking tar backup..."
    tar -cvf "$BACKUP_FILE" "$BACKUP_LOCATION/$BACKUP_DIR_NAME"  >> "$log_file" 2>&1

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
      gzip "$BACKUP_FILE"  >> "$log_file" 2>&1
    else
      LOG_ERROR $LINENO "Tar file creation failed."
      exit 1
    fi

    # If zip file exists, then unzip it
    if [ -f "$OPATCH_ZIP_PATH" ]; then
      LOG_MESSAGE "Zip file exists. Unzipping..."
      unzip "$OPATCH_ZIP_PATH" -d "$OH_GI_HOME"  >> "$log_file" 2>&1
    else
      LOG_ERROR $LINENO "Zip file does not exist or not the correct file."
      exit 1
    fi

    # Return success status
    return 0
  else
    LOG_ERROR $LINENO "Directory does not exist or not the correct directory."
    exit 1
  fi
}

# Call the function and log result
LOG_MESSAGE "Start Latest Opatch to $ORA_HOME"
if copy_opatch "$ORA_HOME" "$BKP_LOC" "$OPATCH_ZIP"; then
  LOG_MESSAGE "OPatch copy completed successfully."
  LOG_RESULT "SUCCESSFUL"
  exit 0
else
  LOG_ERROR $LINENO "OPatch copy failed."
  LOG_RESULT "UNSUCCESSFUL"
  exit 1
fi

