#!/bin/bash
# ==============================================================================
# Script Name: oradb_stop_start.sh
# Author: Your Name
# Date: DD-MM-YYYY
#
# Description: This script is used to start / startup upgrade or stop Oracle databases 
# based on the provided arguments. It checks the Oracle Home for each SID 
# from the /etc/oratab file and ensures that each SID is under the provided 
# Oracle Home. The script also verifies that no SID is running before 
# performing any operation. All operations are logged in real time.
#
# Usage: oradb_stop_start.sh <Oracle Home> <Comma-separated list of SIDs> <DB_ACTION: start|stop|start_upgrade>
#
# Example: oradb_stop_start.sh /u01/app/oracle/product/db_1 orcl1,orcl2,orcl3 start
# ==============================================================================

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
  exit 0
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

# Function to check if the SID is up
check_sids_up() {
  sid=$1
  if pgrep -f "ora_smon_$sid" >/dev/null; then
      LOG_ERROR $LINENO "SID $sid is already running."
  fi
}

# Function to check if the SID is down
startup_db() {
  local orasid=$1
  local orahome=$2
  
  if [ -z "$orasid" ] || [ -z "$orahome" ] ; then
  LOG_ERROR "$LINENO" "Oracle_home and sid can't be null."
  return 1
  fi
  
export ORACLE_HOME=$orahome
export ORACLE_SID=$orasid
SQLP=$ORACLE_HOME/bin/sqlplus

LOG_MESSAGE "Startup upgrade ORACLE_SID : $ORACLE_SID.."
LOG_MESSAGE "ORACLE_HOME is set to      : $ORACLE_HOME"
LOG_MESSAGE "ORACLE_SID  is set to      : $ORACLE_SID"

"$SQLP" '/ as sysdba' <<EOF | while IFS= read -r line
WHENEVER SQLERROR EXIT SQL.SQLCODE;
WHENEVER OSERROR  EXIT SQL.SQLCODE;
SET HEADING ON
SET PAGESIZE 40000
COL HOST_NAME FOR A35
SET ECHO ON
SET SERVEROUTPUT ON
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET PAGES 0
SET LINE 32767
COL NAME FOR A30
COL OPEN_MODE FOR A30
COL STATUS FOR A30
startup;
SELECT NAME,OPEN_MODE,STATUS FROM V\$DATABASE,V\$INSTANCE;
exit;
EOF
  do
      LOG_MESSAGE "$line"
  done
  if [[ ${PIPESTATUS[1]} -ne 0 ]]; then
      LOG_ERROR $LINENO "Failed to start SID $sid."
  fi
}

# Function to start SID in upgrade mode
startup_db_upgrade_mode() {
  local orasid=$1
  local orahome=$2
  
  if [ -z "$orasid" ] || [ -z "$orahome" ] ; then
  LOG_ERROR "$LINENO" "Oracle_home and sid can't be null."
  return 1
  fi
  
export ORACLE_HOME=$orahome
export ORACLE_SID=$orasid
SQLP=$ORACLE_HOME/bin/sqlplus

LOG_MESSAGE "Startup upgrade ORACLE_SID : $ORACLE_SID.."
LOG_MESSAGE "ORACLE_HOME is set to      : $ORACLE_HOME"
LOG_MESSAGE "ORACLE_SID  is set to      : $ORACLE_SID"

"$SQLP" '/ as sysdba' <<EOF | while IFS= read -r line
WHENEVER SQLERROR EXIT SQL.SQLCODE;
WHENEVER OSERROR  EXIT SQL.SQLCODE;
SET HEADING ON
SET PAGESIZE 40000
COL HOST_NAME FOR A35
SET ECHO ON
SET SERVEROUTPUT ON
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET PAGES 0
SET LINE 32767
COL NAME FOR A30
COL OPEN_MODE FOR A30
COL STATUS FOR A30
startup upgrade;
SELECT NAME,OPEN_MODE,STATUS FROM V\$DATABASE,V\$INSTANCE;
exit;
EOF
  do
      LOG_MESSAGE "$line"
  done
  if [[ ${PIPESTATUS[1]} -ne 0 ]]; then
      LOG_ERROR $LINENO "Failed to start SID $sid in upgrade mode."
  fi
}

shutdown_db() {

  local orasid=$1
  local orahome=$2
  
  if [ -z "$orasid" ] || [ -z "$orahome" ] ; then
  LOG_ERROR "$LINENO" "Oracle_home and sid can't be null."
  return 1
  fi
  
export ORACLE_HOME=$orahome
export ORACLE_SID=$orasid
SQLP=$ORACLE_HOME/bin/sqlplus

LOG_MESSAGE "Stopping ORACLE_SID    : $ORACLE_SID.."
LOG_MESSAGE "ORACLE_HOME is set to  : $ORACLE_HOME"
LOG_MESSAGE "ORACLE_SID  is set to  : $ORACLE_SID"

"$SQLP" '/ as sysdba' <<EOF | while IFS= read -r line
WHENEVER SQLERROR EXIT SQL.SQLCODE;
WHENEVER OSERROR  EXIT SQL.SQLCODE;
SET HEADING ON
SET PAGESIZE 40000
COL HOST_NAME FOR A35
SET ECHO ON
SET SERVEROUTPUT ON
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET PAGES 0
SET LINE 32767
COL NAME FOR A30
COL OPEN_MODE FOR A30
COL STATUS FOR A30
SELECT NAME,OPEN_MODE,STATUS FROM V\$DATABASE,V\$INSTANCE;
shutdown immediate;
exit;
EOF
  do
      LOG_MESSAGE "$line"
  done
  if [[ ${PIPESTATUS[1]} -ne 0 ]]; then
      LOG_ERROR $LINENO "Failed to stop SID $sid."
  fi
unset ORACLE_HOME
unset ORACLE_SID
}

# Function to display usage
usage() {
  LOG_ERROR $LINENO "Invalid usage. Usage: $0 --OraHome Oracle home path --SidList <orcl1,orcl2,orcl3> --DbAction <dbstop/dbstart/dbstartupgrade>"
  exit 1
}


# Function to check if SID is down
is_sid_down() {
  sid=$1
  ! pgrep -f "ora_smon_$sid" >/dev/null
}

# Function to display usage
usage() {
  LOG_ERROR $LINENO "Invalid usage. Usage: $0 --OraHome Oracle home path --SidList <orcl1,orcl2,orcl3> --DbAction <dbstop/dbstart/dbstartupgrade>"
  exit 1
}

# Initialize variables
ORA_HOME=""
SID_LIST=""
DB_ACTION=""

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
    -DbAction)
      DB_ACTION="$2"
      shift
      shift
      ;;
    *)
      LOG_ERROR "$LINENO" "Invalid option: $1"
      usage
      shift
      ;;
  esac
done

# If directory or backup location is not provided, log error and exit
if [ -z "$ORA_HOME" ] || [ -z "$SID_LIST" ] || [ -z "$DB_ACTION" ]; then
  usage
fi

# Iterate over each SID one by one
IFS=','
for SID_NAME in $SID_LIST
do

# Validate the Oracle Home
validate_orahome "$SID_NAME"	
if [[ $? -ne 0 ]]; then
LOG_ERROR "$LINENO" "The validation of Oracle Home failed."
exit 1
fi

    # Choose the operation based on the DB_ACTION argument
    case "$DB_ACTION" in
        'dbstart')
            if is_sid_down "$SID_NAME"; then
                startup_db "$SID_NAME" "$ORA_HOME"
				sleep 10
            else
                LOG_MESSAGE "SID $SID_NAME is already running. Skipping..."
				sleep 5
            fi
            ;;
        'dbstop')
            if is_sid_down "$SID_NAME"; then
                LOG_MESSAGE "SID $SID_NAME is already down. Skipping..."
				sleep 5
            else
                shutdown_db "$SID_NAME" "$ORA_HOME"
				sleep 10
            fi
            ;;
        'dbstartupg')
            if is_sid_down "$SID_NAME"; then
                startup_db_upgrade_mode "$SID_NAME" "$ORA_HOME"
				sleep 10
            else
                LOG_MESSAGE "SID $SID_NAME is already running. Skipping..."
				sleep 5
            fi
            ;;
        *)
            LOG_ERROR $LINENO "Invalid DB_ACTION. DB_ACTION must be either 'dbstart', 'dbstop', or 'dbstartupg'."
            ;;
    esac
done
unset IFS

LOG_RESULT "$DB_ACTION operation completed successfully"
