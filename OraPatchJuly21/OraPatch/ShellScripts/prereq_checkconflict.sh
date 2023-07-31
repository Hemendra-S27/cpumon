#!/bin/bash
# prereq_checkconflict.sh
# Log location
# Example:
# prereq_checkconflict.sh --OraHome /u01/app/oracle/product/db_1 --PatchHome /mnt/backup --PatchName PSU


log_path="/tmp"
log_file="${log_path}/${0%.*}_$(hostname)_$(date +%Y%m%d%H%M%S).log"

# Function to log error messages
function LOG_ERROR() {
  timestamp=$(date "+%Y-%m-%d %H:%M:%S %Z")
  script_name=${BASH_SOURCE[1]}
  line_number=$1
  error_message=$2
  echo "ERROR:: ${timestamp}:: Error in ${script_name} at line ${line_number}:: ${error_message}" | tee -a "${log_file}"
  exit 1
}

# Function to log informative messages
function LOG_MESSAGE() {
  timestamp=$(date "+%Y-%m-%d %H:%M:%S %Z")
  out_message=$1
  echo "MESSAGE:: ${timestamp}:: $out_message" | tee -a "${log_file}"
}

# Function to log script results
function LOG_RESULT() {
  timestamp=$(date "+%Y-%m-%d %H:%M:%S %Z")
  out_result=$1
  echo "RESULT:: ${timestamp}:: $out_result" | tee -a "${log_file}"
}

# check argument count
if [ $# -ne 6 ]; then
  LOG_ERROR ${LINENO} "Invalid number of arguments. Expected 6, got $#."
fi

while [ $# -gt 0 ]
do
  key="$1"
  case $key in
    -OraHome)
    ORA_HOME="$2"
    shift # past argument
    shift # past value
    ;;
    -PatchHome)
    PATCH_HOME="$2"
    shift # past argument
    shift # past value
    ;;
    -PatchName)
    PATCH_NAME="$2"
    shift # past argument
    shift # past value
    ;;
    *)    # unknown option
    LOG_ERROR ${LINENO} "Invalid option: $key"
    ;;
  esac
done

# check if ORA_HOME and PATCH_HOME exist and have read/write access
if [ ! -d "$ORA_HOME" ] || [ ! -r "$ORA_HOME" ] || [ ! -w "$ORA_HOME" ]; then
  LOG_ERROR ${LINENO} "ORA_HOME either does not exist or does not have read/write access."
fi

if [ ! -d "$PATCH_HOME" ] || [ ! -r "$PATCH_HOME" ] || [ ! -w "$PATCH_HOME" ]; then
  LOG_ERROR ${LINENO} "PATCH_HOME either does not exist or does not have read/write access."
fi

# check if PATCH_NAME is valid
UPPER_PATCH_NAME=$(echo "$PATCH_NAME" | tr '[:lower:]' '[:upper:]')
if [[ ! "PSU OJVM JDK PERL GIPATCH" =~ (^|[[:space:]])"$UPPER_PATCH_NAME"($|[[:space:]]) ]]; then
  LOG_ERROR ${LINENO} "Invalid PATCH_NAME. Valid values are PSU, OJVM, PERL, JDK, GIPATCH."
fi

tempname="$PATCH_HOME"
tempname=${tempname%/}
PATCH_NUMBER=$(basename "$tempname")

LOG_MESSAGE "Running patch pre-requisite checks"
LOG_MESSAGE "HOST_NAME is set to    : $(hostname)"
LOG_MESSAGE "ORA_HOME is set to     : $ORA_HOME"
LOG_MESSAGE "PATCH_HOME is set to   : $PATCH_HOME"
LOG_MESSAGE "PATCH_NAME is set to   : $PATCH_NAME"
LOG_MESSAGE "PATCH_NUMBER is set to : $PATCH_NUMBER"

export ORACLE_HOME=$ORA_HOME
OPAT=$ORACLE_HOME/OPatch/opatch

cd $PATCH_HOME
#$OPAT prereq CheckConflictAgainstOHWithDetail -ph ./$PATCH_NAME | while IFS= read -r line
$OPAT prereq CheckConflictAgainstOHWithDetail -ph ./ | while IFS= read -r line
do
  LOG_MESSAGE "$line"
done

if [ ${PIPESTATUS[0]} -eq 0 ]; then
  LOG_MESSAGE "$PATCH_NAME patch pre-requisite checks completed successfully"
  LOG_RESULT "SUCCESSFUL"
  exit 0
else
  LOG_ERROR ${LINENO} "$PATCH_NAME pre-requisite checks failed."
  LOG_RESULT "UNSUCCESSFUL"
  exit 1
fi

