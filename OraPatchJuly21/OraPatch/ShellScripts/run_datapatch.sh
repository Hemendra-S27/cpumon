#!/bin/bash

ORATAB=/etc/oratab

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

# Function to log script results
function TEMP_RESULT() {
  timestamp=$(date "+%Y-%m-%d %H:%M:%S %Z")
  out_result=$1
  echo "TEMP_RESULT:: ${timestamp}:: $out_result" | tee -a "${log_file}"
  #echo "TEMP_RESULT:: ${timestamp}:: $out_result" | tee -a "${log_file}" >/dev/null
}

# Function to validate the Oracle Home for each SID
validate_orahome() {
  sid=$1
  orahome_in_file=$(grep "^$sid:" /etc/oratab | cut -d: -f2)
  if [[ "$orahome_in_file" != "$ORA_HOME" ]]; then
      LOG_ERROR $LINENO "The Oracle Home for SID $sid does not match the provided Oracle Home."
      return 1
  else
      LOG_MESSAGE "The Oracle Home for SID $sid match the provided Oracle Home."
      return 0
  fi
}


# Function to display usage
usage() {
  LOG_ERROR $LINENO "Invalid usage. Usage: $0 --OraHome <directory_to_backup> --SidList <backup_location>"
  exit 1
}

# Initialize variables
ORA_HOME=""
SID_LIST=""

# Process command line options
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -OraHome)
      ORA_HOME="$2"
      shift
      shift
      ;;
    -SidList)
      SID_LIST="$2"
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
if [ -z "$ORA_HOME" ] || [ -z "$SID_LIST" ]; then
  usage
fi

# check if ORA_HOME and PATCH_DIR exist and have read/write access
if [ ! -d "$ORA_HOME" ] || [ ! -r "$ORA_HOME" ] || [ ! -w "$ORA_HOME" ]; then
  LOG_ERROR ${LINENO} "ORA_HOME either does not exist or does not have read/write access."
fi

LOG_MESSAGE "Starting datapatch for : $ORACLE_HOME"
IFS=','
for SID_NAME in $SID_LIST
do

# Validate the Oracle Home
validate_orahome "$SID_NAME"
if [[ $? -ne 0 ]]; then
LOG_ERROR "$LINENO" "The validation of Oracle Home failed."
exit 1
fi

export ORACLE_SID=$SID_NAME
export ORACLE_HOME=$ORA_HOME
SQLP=$ORACLE_HOME/bin/sqlplus
LSNR=$ORACLE_HOME/bin/lsnrctl
OPAT=$ORACLE_HOME/OPatch/opatch
EMCT=$ORACLE_HOME/bin/emctl
DPV=$ORACLE_HOME/OPatch/datapatch

#db_check=$(GET_DB_STATUS)
#if echo "$db_check" | grep -i "Error:" > /dev/null ; then
# LOG_ERROR $LINENO "datapatch not started due to error $db_check"
# continue
#fi

LOG_MESSAGE "ORA_HOME is set to   : $ORACLE_HOME"
LOG_MESSAGE "DB_SID is set to     : $ORACLE_SID"
LOG_MESSAGE "DATAPATCH is set to  : $DPV"
LOG_MESSAGE "TASK                 : datapatch run"
sleep 10

#cd $ORACLE_HOME/OPatch
#./datapatch -verbose

"$DPV" -verbose | while IFS= read -r line
do
  LOG_MESSAGE "$line"
done
if [ ${PIPESTATUS[0]} -eq 0 ]; then
  LOG_MESSAGE "Datapatch apply successfully on : $ORACLE_SID"
  unset ORACLE_SID
  unset ORACLE_HOME
else
  LOG_ERROR ${LINENO} "Datapatch failed on $ORACLE_SID"
  unset ORACLE_SID
  unset ORACLE_HOME
fi
done
unset IFS
LOG_MESSAGE "Datapatch complete for : $ORACLE_HOME"
