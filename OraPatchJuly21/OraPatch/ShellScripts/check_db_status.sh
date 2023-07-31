#!/bin/bash
#check_db_status.sh

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


# Function to check if the databases are open
check_db_status() {

local ORACLE_HOME=$1
local SID_NAMES=$2
local select_op=""
local db_open_rs=""
  
# If directory or backup location is not provided, log error and exit
if [ -z "$ORACLE_HOME" ] || [ -z "$SID_NAMES" ]; then
  LOG_ERROR $LINENO "Orace home and sid can't be null"
  db_open="ERR"
  echo $db_open 
  return 1
fi

# Export Oracle home directory
export ORACLE_HOME=$ORACLE_HOME
SQLP=$ORACLE_HOME/bin/sqlplus

# Check the status of each database
IFS=','
for ora_sid in $SID_NAMES
do
export ORACLE_SID=$ora_sid
LOG_MESSAGE "Checking database open status for $ORACLE_SID"
select_op="$($SQLP -S / as sysdba <<EOF
SET HEADING OFF
SET FEEDBACK OFF
SET ECHO OFF
SET PAGES 0
SET LINE 32767
WHENEVER SQLERROR EXIT SQL.SQLCODE;
WHENEVER OSERROR  EXIT SQL.SQLCODE;
SELECT STATUS FROM V\$INSTANCE
exit;
EOF
)"

    local valid_keyword='OPEN'
    local sp_err="$(echo "$select_op" | grep '^.*SP2-[0-9]\{4\}:' | head -n1)"
    local ora_err="$(echo "$select_op" | grep '^.*ORA-[0-9]\{5\}:' | head -n1)"
    local Unknown_err=$(echo "$select_op" | awk '{print substr($0, 1, 15)}')
    if [ "$select_op" = "$valid_keyword" ] ; then
      db_open="YES"
	  db_open_rs+="${db_open} "
	  LOG_MESSAGE "Database instance $ORACLE_SID open => $db_open"
    elif [ -n "$sp_err" ]; then
	  LOG_ERROR $LINENO "Unable to get the database status;[Error:$sp_err] for $ora_sid"
      db_open="ERR"
	  db_open_rs+="${db_open} "
	  LOG_MESSAGE "Database instance $ORACLE_SID open => $db_open"
    elif [ -n "$ora_err" ]; then
	  LOG_ERROR $LINENO "Unable to get the database status;[Error:$ora_err] for $ora_sid"
      db_open="ERR"
	  db_open_rs+="${db_open} "
	  LOG_MESSAGE "Database instance $ORACLE_SID open => $db_open"
    elif [ -z "$select_op" ] ; then
	  LOG_ERROR $LINENO "Unable to get the database status;[Error:SQL*Plus failed to execute.] for $ora_sid"
      db_open="ERR"
	  db_open_rs+="${db_open} "
	  LOG_MESSAGE "Database instance $ORACLE_SID open => $db_open"
    else
      LOG_ERROR $LINENO "Error:Unknown error or result not in accepted list, Expected ($valid_keyword), Actual ($Unknown_err) for $ora_sid"
	  db_open="NO"
	  db_open_rs+="${db_open} "
	  LOG_MESSAGE "Database instance $ORACLE_SID open => $db_open"
    fi
  done
  unset IFS
#echo $db_open_rs
LOG_MESSAGE "Database Instances $2 open status => $db_open_rs"
TEMP_RESULT "$db_open_rs"
}

# Call the function with arguments
# check_db_status "$ORA_HOME" "$SID_LIST"

check_db_status "$ORA_HOME" "$SID_LIST" | while IFS= read -r line
do
  prefix=$(echo $line | awk -F'::' '{print $1}')
  if [[ "$prefix" == "TEMP_RESULT" ]]; then
      result=$(echo $line | awk -F'::' '{print $3}')
	    if [[ "$result" == *"ERR"* ]]; then
			LOG_RESULT "ERR"
		elif [[ "$result" == *"NO"* ]]; then
			LOG_RESULT "NO"
		elif [[ "$result" == *"YES"* ]]; then
		   LOG_RESULT "YES"
		 else
			LOG_RESULT "ERR"
		fi
	else
	echo $line
	fi		
done
exit

