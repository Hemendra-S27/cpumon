#!/bin/bash
# db_inventory.sh

# Log location
script_name="db_inventory"
log_path="/tmp"
log_file="${log_path}/${script_name}_$(hostname)_$(date +%Y%m%d%H%M%S).log"


# set oratab and orainv.

ORATAB=/etc/oratab
INVPTR=/etc/oraInst.loc

if [ -f "$INVPTR" ]; then
orainv=$(< "$INVPTR" grep -i "inventory_loc" | awk -F'=' '{print $2}')
else
orainv='unknown'
fi

# Veriables for OH/GI details from ORATAB.
home_exist_valid='YES'
sid_status_valid='UP'
sid_status_invalid='DOWN'
ntfs_ora_path='/netfs/ora/vol1'
TIMEOUT_SECONDS=60  # This timeout setting is used in fuser command.

# Declare arrays
declare -a DB_DATA_ARRAY
declare -a OS_DATA_ARRAY
declare -a DB_OS_DATA

# Global OS details
#bash_version="$BASH_VERSION"
bash_major_version=$(echo "$bash_version" | awk -F'.' '{print $1}')
os_name=$(uname -s)
os_kernel=$(uname -r)
os_shell=$(bash --version | head -n 1)

cpu_count=$(grep -c ^processor /proc/cpuinfo 2>/dev/null)
if [ -z "$cpu_count" ]; then
    server_cpu=0
else
   server_cpu=$cpu_count
fi

ram_size=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2/1024 " MB"}' 2>/dev/null)
if [ -z "$ram_size" ]; then
    server_ram=0
else
   server_ram=$ram_size
fi

jchem_check=$(ps -ef | grep -i "jchem" | grep -v "grep" 2>/dev/null)
if [ -z "$jchem_check" ]; then
    jchem_status='DOWN'
else
   jchem_status='UP'
fi

OS_ENV_DATA="$os_name|$os_kernel|$os_shell|$server_cpu|$server_ram|$jchem_status|$orainv"

DB_COLUMNS=(
"ROWSTART"
"INSTANCE_NAME"
"HOST_NAME"
"VERSION"
"STARTUP_TIME"
"STATUS"
"LOGINS"
"DATABASE_STATUS"
"INSTANCE_ROLE"
"DBID"
"NAME"
"CREATED"
"RESETLOGS_TIME"
"LOG_MODE"
"OPEN_MODE"
"PROTECTION_MODE"
"PROTECTION_LEVEL"
"DATABASE_ROLE"
"FORCE_LOGGING"
"PLATFORM_ID"
"PLATFORM_NAME"
"FLASHBACK_ON"
"DB_UNIQUE_NAME"
"IS_DG"
"DG_TNS"
"IS_RAC"
"RAC_NODE"
"WALLET_LOCATION"
"WALLET_STATUS"
"WALLET_TYPE"
"TDE_TBSCOUNT"
"OFFLINE_DATAFILE"
"OFFLINE_TEMPFILE"
"NEED_RECOVERY"
"IS_PDB"
"PDB_LIST"
"PGA_LIMIT"
"PGA_TARGET"
"SGA_TARGET"
"SGA_MAX"
"MEMORY_MAX"
"MEMORY_TARGET"
"CPUCOUNT"
"ALLOC_PGA_MB"
"TOTAL_SGA_MB"
"TOTALSIZE"
"DATAFILESIZE"
"TEMPFILESIZE"
"SEGMENTSIZE"
"ROWEND"
)

##################################################
#           Function LOG_ERROR                   #
##################################################
function LOG_ERROR() {
timestamp=$(date "+%Y-%m-%d %H:%M:%S %Z")
script_name=${BASH_SOURCE[1]}
line_number=$1
error_message=$2
#echo "ERROR:: ${timestamp}:: Error in ${script_name} at line ${line_number}:: ${error_message}" | tee -a "${log_file}"
echo "ERROR:: ${timestamp}:: Error in ${script_name} at line ${line_number}:: ${error_message}" | tee -a "${log_file}" >/dev/null
}

##################################################
#           Function LOG_MESSAGE                 #
##################################################
function LOG_MESSAGE() {
timestamp=$(date "+%Y-%m-%d %H:%M:%S %Z")
out_message=$1
#echo "MESSAGE:: ${timestamp}:: $out_message" | tee -a "${log_file}"
echo "MESSAGE:: ${timestamp}:: $out_message" | tee -a "${log_file}" >/dev/null
}

##################################################
#           Function LOG_RESULT                  #
##################################################
function LOG_RESULT() {
timestamp=$(date "+%Y-%m-%d %H:%M:%S %Z")
out_result=$1
#echo "RESULT:: ${timestamp}:: $out_result" | tee -a "${log_file}"
echo "RESULT:: ${timestamp}:: $out_result" | tee -a "${log_file}" >/dev/null
}

##################################################
#           Function CHECK_COMMAND               #
##################################################
CHECK_COMMAND() {
    local cmd_name=$1
    local default_locations=(
            "/usr/sbin/$cmd_name"
        "/bin/$cmd_name"
        "/sbin/$cmd_name"
        "/usr/bin/$cmd_name"
        "/usr/local/bin/$cmd_name"
        "/usr/local/sbin/$cmd_name"
    )

    for location in "${default_locations[@]}"; do
        if [ -x "$location" ]; then
            # Command found
            echo "$location"
            return
        fi
    done

    # Command not found
    echo "$cmd_name"
}

##################################################
#           Function CHECK_ORACLE_HOME_IN_USE    #
##################################################
CHECK_ORACLE_HOME_IN_USE() {
    local home_path="$1"
        local out_data

    # Search at all default location using function  CHECK_COMMAND and Check if fuser command is available
        local FU=$(CHECK_COMMAND "fuser")
    if ! command -v "$FU" > /dev/null; then
        out_data='fuser:Notfound'
                echo "$out_data"
        return
    fi

#fuser_output=$($FU "$home_path" 2>/dev/null)
fuser_output=$(timeout "$TIMEOUT_SECONDS" $FU "$home_path" 2>/dev/null)
fuser_exit_code=$?

  if [[ "$fuser_exit_code" -eq 0 ]]; then
    out_data='YES'
  elif [[ "$fuser_exit_code" -eq 124 ]]; then
    out_data='fuser:Timeout'
  else
    out_data='NO'
  fi

echo "$out_data"
return
}

##################################################
#           Function RESET_OS_DATA               #
##################################################
function RESET_OS_DATA() {
unset ora_sid
unset ora_home
unset auto_database
home_exist='unknown'
home_active='unknown'
os_user='unknown'
primary_group='unknown'
total_gb='0.0'
used_gb='0.0'
free_gb='0.0'
used_pct='0.0'
free_pct='0.0'
sid_status='unknown'
home_type='unknown'
sqlplus_version='0.0.0.0.0'
db_release='unknown'
opatch_version='0.0.0.0.0'
patch_history='unknown'
patch_date='unknown'
listener_data='unknown'
db_status='unknown'
}

##################################################
#           Function RESET_DB_DATA               #
##################################################
function RESET_DB_DATA() {
ROWSTART='ROWST'
INSTANCE_NAME='unknown'
HOST_NAME='unknown'
VERSION='0.0.0.0.0'
STARTUP_TIME='unknown'
STATUS='unknown'
LOGINS='unknown'
DATABASE_STATUS='unknown'
INSTANCE_ROLE='unknown'
DBID='0'
NAME='unknown'
CREATED='unknown'
RESETLOGS_TIME='unknown'
LOG_MODE='unknown'
OPEN_MODE='unknown'
PROTECTION_MODE='unknown'
PROTECTION_LEVEL='unknown'
DATABASE_ROLE='unknown'
FORCE_LOGGING='unknown'
PLATFORM_ID='unknown'
PLATFORM_NAME='unknown'
FLASHBACK_ON='unknown'
DB_UNIQUE_NAME='unknown'
IS_DG='unknown'
DG_TNS='unknown'
IS_RAC='unknown'
RAC_NODE='unknown'
WALLET_LOCATION='unknown'
WALLET_STATUS='unknown'
WALLET_TYPE='unknown'
TDE_TBSCOUNT='unknown'
OFFLINE_DATAFILE='unknown'
OFFLINE_TEMPFILE='unknown'
NEED_RECOVERY='unknown'
IS_PDB='unknown'
PDB_LIST='unknown'
PGA_LIMIT='0'
PGA_TARGET='0'
SGA_TARGET='0'
SGA_MAX='0'
MEMORY_MAX='0'
MEMORY_TARGET='0'
CPUCOUNT='0'
ALLOC_PGA_MB='0'
TOTAL_SGA_MB='0'
TOTALSIZE='0'
DATAFILESIZE='0'
TEMPFILESIZE='0'
SEGMENTSIZE='0'
ROWEND='ROWED'
}

##################################################
#           Function LOG_OS_DATA                 #
##################################################
function LOG_OS_DATA() {
echo "$ora_sid|"\
"$ora_home|"\
"$auto_database|"\
"$home_exist|"\
"$home_active|"\
"$home_type|"\
"$sid_status|"\
"$db_status|"\
"$sqlplus_version|"\
"$db_release|"\
"$opatch_version|"\
"$patch_history|"\
"$patch_date|"\
"$listener_data|"\
"$os_user|"\
"$primary_group|"\
"$total_gb|"\
"$used_gb|"\
"$free_gb|"\
"$used_pct|"\
"$free_pct"
}

##################################################
#           Function LOG_DB_DATA                 #
##################################################
function LOG_DB_DATA() {
echo "$ROWSTART|"\
"$INSTANCE_NAME|"\
"$HOST_NAME|"\
"$VERSION|"\
"$STARTUP_TIME|"\
"$STATUS|"\
"$LOGINS|"\
"$DATABASE_STATUS|"\
"$INSTANCE_ROLE|"\
"$DBID|"\
"$NAME|"\
"$CREATED|"\
"$RESETLOGS_TIME|"\
"$LOG_MODE|"\
"$OPEN_MODE|"\
"$PROTECTION_MODE|"\
"$PROTECTION_LEVEL|"\
"$DATABASE_ROLE|"\
"$FORCE_LOGGING|"\
"$PLATFORM_ID|"\
"$PLATFORM_NAME|"\
"$FLASHBACK_ON|"\
"$DB_UNIQUE_NAME|"\
"$IS_DG|"\
"$DG_TNS|"\
"$IS_RAC|"\
"$RAC_NODE|"\
"$WALLET_LOCATION|"\
"$WALLET_STATUS|"\
"$WALLET_TYPE|"\
"$TDE_TBSCOUNT|"\
"$OFFLINE_DATAFILE|"\
"$OFFLINE_TEMPFILE|"\
"$NEED_RECOVERY|"\
"$IS_PDB|"\
"$PDB_LIST|"\
"$PGA_LIMIT|"\
"$PGA_TARGET|"\
"$SGA_TARGET|"\
"$SGA_MAX|"\
"$MEMORY_MAX|"\
"$MEMORY_TARGET|"\
"$CPUCOUNT|"\
"$ALLOC_PGA_MB|"\
"$TOTAL_SGA_MB|"\
"$TOTALSIZE|"\
"$DATAFILESIZE|"\
"$TEMPFILESIZE|"\
"$SEGMENTSIZE|"\
"$ROWEND"
}

##################################################
#           Function GET_OS_DATA                 #
##################################################
function GET_OS_DATA() {

local ora_sid=$1
local ora_home=$2
local auto_database=$3
local select_op

if [ -z "$ora_sid" ] || [ -z "$ora_home" ] ; then
  LOG_ERROR $LINENO "ora_sid and ora_home can't be null"
  ora_sid='unknown'
  ora_home='unknown'
  OS_DATA=$(LOG_OS_DATA)
 #echo $OS_DATA
  return 1
fi

if [ -z "$auto_database" ]; then
  auto_database='N'
fi

if [[ ! -d "$ora_home" ]]; then
  LOG_ERROR $LINENO "ora_home doest not exist for $ora_sid"
  # In OS_DATA_default_2 1st value set to 'NO' ,means home_exist='NO'
  home_exist='NO'
  OS_DATA=$(LOG_OS_DATA)
  #echo $OS_DATA
  return 1
fi


if [[ -d "$ora_home" ]]; then
  home_exist='YES'
  os_user=$(stat -c %U $ora_home)
  primary_group=$(stat -c %G $ora_home)
  fs_info=$(df -hP $ora_home | awk 'NR==2 {print $2, $3, $4, $5}')
  total_gb=$(echo $fs_info | cut -d' ' -f1)
  used_gb=$(echo $fs_info | cut -d' ' -f2)
  free_gb=$(echo $fs_info | cut -d' ' -f3)
  used_pct=$(echo $fs_info | cut -d' ' -f4)
  used_pct=${used_pct%\%}
  free_pct=$((100 - used_pct))
  #used_pct="$used_pct%"
  #free_pct="$free_pct%"

  # Check if home is active or not by calling function CHECK_ORACLE_HOME_IN_USE.
  # This function using fuser to check.
  #home_active=$(CHECK_ORACLE_HOME_IN_USE "$ora_home")
  home_active='check_is_disable'

  if [[ -f $ora_home/bin/crsctl ]]; then
    home_type='GI'
  elif [[ -f $ora_home/bin/sqlplus ]]; then
    home_type='OH'
  elif [[ -f $ora_home/bin/emctl ]]; then
    home_type='OA'
  else
    home_type='Unknown'
  fi

  export ORACLE_SID=$ora_sid
  export ORACLE_HOME=$ora_home
  SQLP=$ORACLE_HOME/bin/sqlplus
  LSNR=$ORACLE_HOME/bin/lsnrctl
  OPAT=$ORACLE_HOME/OPatch/opatch
  EMCT=$ORACLE_HOME/bin/emctl

  case "$home_type" in
  'GI')
      if ps -ef | grep -w "asm_pmon_${ora_sid}" | grep -v "grep" > /dev/null; then
        sid_status='UP'
      else
        sid_status='DOWN'
      fi

      # Get SQLPlus version
      if [ -x  "$SQLP" ]; then
        sqlplus_version=$($SQLP -v | awk 'NR==2 {print $3}')
      else
        sqlplus_version='0.0.0.0.0'
      fi

          if [ -z "sqlplus_version" ]; then
            sqlplus_version='0.0.0.0.0'
          fi

      # Get OPatch version & Patch history & Patch Date
      if [ -x  "$OPAT" ]; then
          opatch_version=$($OPAT version | grep -i 'OPatch Version' | awk -F: '{print $2}' | xargs)
          opatch_output=$($OPAT lspatches 2>/dev/null)
          opatch_output_last=$(echo "$opatch_output" | tail -1)

          if [[ "$opatch_output" == *"OPatch succeeded"* ]]; then
              patch_history=$(echo "$opatch_output" | grep '^[0-9]' | awk '{print $1"-"$2"-"$3}' | sed 's/[^a-zA-Z0-9]*$//' | sort | paste -sd ",")
		      patch_date_output=$($OPAT lsinventory | grep -i "applied" 2>/dev/null )
			  case "$patch_date_output" in
		          Patch*applied\ on*)
				      patch_date=$(echo "$patch_date_output" | awk '{print $2 ":" $7" "$8" "$9" "$10" "$11}' | sort | paste -sd ",")
					 ;;
					*)
					  patch_date="unknown"
					 ;;
			  esac
          else
               patch_history="$opatch_output_last"
			   patch_date="$opatch_output_last"
          fi
      else
        opatch_version='None'
        patch_history='None'
		patch_date='None'
      fi

      if [ -z "$opatch_version" ] || [ -z "$patch_history" ] || [ -z "$patch_date" ]; then
          opatch_version='0.0.0.0.0'
          patch_history='nopatch'
		  patch_date='nopatch'
      fi
	   
      # Get Listener details
     case $(echo "$sqlplus_version" | awk -F'.' '{print $1}') in
       12|18|19) varf=2 ;;
       *) varf=1 ;;
     esac

         if echo "$ora_home" | grep -q "$ntfs_ora_path"; then
            tnsora_home=${ora_home#*$ntfs_ora_path}
     else
        tnsora_home="$ora_home"
         fi

      listener_data=""
      for listener_name in $(ps -ef | grep -i "$tnsora_home/bin/tnslsnr" | grep -v "grep" | awk -v var=$varf '{print $(NF-var)}')
      do
        tns_admin=$(dirname "$($LSNR status "$listener_name" | grep -i "Listener Parameter File" | awk '{print $NF}')")
        listener_details="$listener_name:$tns_admin"
        if [ -z "$listener_data" ] ; then
          listener_data="$listener_details"
        else
          listener_data="$listener_data,$listener_details"
        fi
      done

      if [ -z "$listener_data" ] ; then
        listener_data='nolistener'
      fi

          OS_DATA=$(LOG_OS_DATA)
      #echo $OS_DATA
          return 0
      ;;
  'OA')
      if [ "$($EMCT status agent | tail -1 | awk '{print $1 $2 $3}')" = 'AgentisRunning' ]; then
        agent_status='UP'
      else
        agent_status='DOWN'
      fi

          sid_status="$agent_status"

      # Get OEM Agent version
      if [ -x  "$EMCT" ]; then
        agent_version=$($EMCT status agent | grep -i "Agent Version" | awk -F':' '{print $2}' | xargs)
      else
        agent_version='0.0.0.0.0'
      fi

          if [ -z "agent_version" ]; then
            agent_version='0.0.0.0.0'
          fi

          sqlplus_version="$agent_version"

      # Get OPatch version & Patch history & Patch Date
      if [ -x  "$OPAT" ]; then
          opatch_version=$($OPAT version | grep -i 'OPatch Version' | awk -F: '{print $2}' | xargs)
          opatch_output=$($OPAT lspatches 2>/dev/null)
          opatch_output_last=$(echo "$opatch_output" | tail -1)

          if [[ "$opatch_output" == *"OPatch succeeded"* ]]; then
              patch_history=$(echo "$opatch_output" | grep '^[0-9]' | awk '{print $1"-"$2"-"$3}' | sed 's/[^a-zA-Z0-9]*$//' | sort | paste -sd ",")
		      patch_date_output=$($OPAT lsinventory | grep -i "applied" 2>/dev/null )
			  case "$patch_date_output" in
		          Patch*applied\ on*)
				      patch_date=$(echo "$patch_date_output" | awk '{print $2 ":" $7" "$8" "$9" "$10" "$11}' | sort | paste -sd ",")
					 ;;
					*)
					  patch_date="unknown"
					 ;;
			  esac
          else
               patch_history="$opatch_output_last"
			   patch_date="$opatch_output_last"
          fi
      else
        opatch_version='None'
        patch_history='None'
		patch_date='None'
      fi

      if [ -z "$opatch_version" ] || [ -z "$patch_history" ] || [ -z "$patch_date" ]; then
          opatch_version='0.0.0.0.0'
          patch_history='nopatch'
		  patch_date='nopatch'
      fi

      # Get Listener details
        listener_data='nolistener'

          OS_DATA=$(LOG_OS_DATA)
      #echo $OS_DATA
          return 0
      ;;
  'OH')
      if pgrep -xf "ora_pmon_${ora_sid}" > /dev/null; then
        sid_status='UP'
      else
        sid_status='DOWN'
      fi

      # Get SQLPlus version
      if [ -x  "$SQLP" ]; then
        sqlplus_version=$($SQLP -v | awk 'NR==2 {print $3}')
      else
        sqlplus_version='None'
      fi

          if [ -z "sqlplus_version" ]; then
            sqlplus_version='0.0.0.0.0'
          fi

          # Remove any trailing spaces
      sqlplus_version_temp=$(echo "$sqlplus_version" | sed 's/ *$//g')

      # Check the version and set db_release accordingly
      case "$sqlplus_version_temp" in
          19*)
              db_release='19c'
              ;;
          18*)
              db_release='18c'
              ;;
          12.2*)
              db_release='12cR2'
              ;;
          12.1*)
              db_release='12cR1'
              ;;
          11*)
              db_release='11g'
              ;;
          *)
              db_release='notsupported'
              ;;
      esac

      # Get OPatch version & Patch history & Patch Date
      if [ -x  "$OPAT" ]; then
          opatch_version=$($OPAT version | grep -i 'OPatch Version' | awk -F: '{print $2}' | xargs)
          opatch_output=$($OPAT lspatches 2>/dev/null)
          opatch_output_last=$(echo "$opatch_output" | tail -1)

          if [[ "$opatch_output" == *"OPatch succeeded"* ]]; then
              patch_history=$(echo "$opatch_output" | grep '^[0-9]' | awk '{print $1"-"$2"-"$3}' | sed 's/[^a-zA-Z0-9]*$//' | sort | paste -sd ",")
		      patch_date_output=$($OPAT lsinventory | grep -i "applied" 2>/dev/null )
			  case "$patch_date_output" in
		          Patch*applied\ on*)
				      patch_date=$(echo "$patch_date_output" | awk '{print $2 ":" $7" "$8" "$9" "$10" "$11}' | sort | paste -sd ",")
					 ;;
					*)
					  patch_date="unknown"
					 ;;
			  esac
          else
               patch_history="$opatch_output_last"
			   patch_date="$opatch_output_last"
          fi
      else
        opatch_version='None'
        patch_history='None'
		patch_date='None'
      fi

      if [ -z "$opatch_version" ] || [ -z "$patch_history" ] || [ -z "$patch_date" ]; then
          opatch_version='0.0.0.0.0'
          patch_history='nopatch'
		  patch_date='nopatch'
      fi

      # Get Listener details
          tnsora_home="$ora_home"
      listener_data=""
      for listener_name in $(ps -ef | grep -i "$tnsora_home/bin/tnslsnr" | grep -v "grep" | awk '{print $(NF-1)}')
      do
        tns_admin=$(dirname "$($LSNR status "$listener_name" | grep -i "Listener Parameter File" | awk '{print $NF}')")
        listener_details="$listener_name:$tns_admin"
        if [ -z "$listener_data" ] ; then
          listener_data="$listener_details"
        else
          listener_data="$listener_data,$listener_details"
        fi
      done

      if [ -z "$listener_data" ] ; then
        listener_data='nolistener'
      fi

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
      db_status="$select_op"
    elif [ -n "$sp_err" ]; then
     db_status='unknown'
     LOG_ERROR $LINENO "Unable to get the database status;[Error:$sp_err] for $ora_sid"
    elif [ -n "$ora_err" ]; then
     db_status='unknown'
     LOG_ERROR $LINENO "Unable to get the database status;[Error:$ora_err] for $ora_sid"
    elif [ -z "$select_op" ] ; then
     db_status='unknown'
     LOG_ERROR $LINENO "Unable to get the database status;[Error:SQL*Plus failed to execute.] for $ora_sid"
    else
     db_status="$Unknown_err"
     LOG_ERROR $LINENO "Error:Unknown error or result not in accepted list, Expected ($valid_keyword), Actual ($Unknown_err) for $ora_sid"
    fi

    OS_DATA=$(LOG_OS_DATA)
    #echo $OS_DATA
        return 0
    ;;
   *)
    OS_DATA=$(LOG_OS_DATA)
    #echo $OS_DATA
    return 1
    esac
fi
}

##################################################
#           Function GET_DB_DATA                 #
##################################################
function GET_DB_DATA() {

local ora_sid=$1
local ora_home=$2
local sqlp_version=$3
local select_op

export ORACLE_SID=$ora_sid
export ORACLE_HOME=$ora_home
SQLP=$ORACLE_HOME/bin/sqlplus

case $(echo "$sqlp_version" | awk -F'.' '{print $1}') in
18|19)
#LOG_MESSAGE "In 18c or 19c : $sqlp_version"
select_op="$($SQLP -S / as sysdba <<EOF
SET HEADING OFF
SET FEEDBACK OFF
SET ECHO OFF
SET PAGES 0
SET LINE 32767
alter session set nls_date_format='DD-MON-YYYY HH24:MI:SS';
WHENEVER SQLERROR EXIT SQL.SQLCODE;
WHENEVER OSERROR  EXIT SQL.SQLCODE;
SELECT
'ROWST'||'|'||
INSTANCE_NAME||'|'||
HOST_NAME||'|'||
VERSION||'|'||
STARTUP_TIME||'|'||
STATUS||'|'||
LOGINS||'|'||
DATABASE_STATUS||'|'||
INSTANCE_ROLE||'|'||
DBID||'|'||
NAME||'|'||
CREATED||'|'||
RESETLOGS_TIME||'|'||
LOG_MODE||'|'||
OPEN_MODE||'|'||
PROTECTION_MODE||'|'||
PROTECTION_LEVEL||'|'||
DATABASE_ROLE||'|'||
FORCE_LOGGING||'|'||
PLATFORM_ID||'|'||
PLATFORM_NAME||'|'||
FLASHBACK_ON||'|'||
DB_UNIQUE_NAME||'|'||
IS_DG||'|'||
DG_TNS||'|'||
IS_RAC||'|'||
RAC_NODE||'|'||
WALLET_LOCATION||'|'||
WALLET_STATUS||'|'||
WALLET_TYPE||'|'||
TDE_TBSCOUNT||'|'||
OFFLINE_DATAFILE||'|'||
OFFLINE_TEMPFILE||'|'||
NEED_RECOVERY||'|'||
IS_PDB||'|'||
PDB_LIST||'|'||
PGA_LIMIT||'|'||
PGA_TARGET||'|'||
SGA_TARGET||'|'||
SGA_MAX||'|'||
MEMORY_MAX||'|'||
MEMORY_TARGET||'|'||
CPUCOUNT||'|'||
ALLOC_PGA_MB||'|'||
TOTAL_SGA_MB||'|'||
TOTALSIZE||'|'||
DATAFILESIZE||'|'||
TEMPFILESIZE||'|'||
SEGMENTSIZE||'|'||
'ROWED'
FROM (
WITH
DB_INST_TAB AS (
SELECT
INST.INSTANCE_NAME,
INST.HOST_NAME,
INST.VERSION_FULL AS "VERSION",
INST.STARTUP_TIME,
INST.STATUS,
INST.LOGINS,
INST.DATABASE_STATUS,
INST.INSTANCE_ROLE,
INST.SHUTDOWN_PENDING,
DB.DBID,
DB.NAME,
DB.CREATED,
DB.RESETLOGS_TIME,
DB.LOG_MODE,
DB.OPEN_MODE,
DB.PROTECTION_MODE,
DB.PROTECTION_LEVEL,
DB.DATABASE_ROLE,
DB.FORCE_LOGGING,
DB.PLATFORM_ID,
DB.PLATFORM_NAME,
DB.FLASHBACK_ON,
DB.DB_UNIQUE_NAME
FROM V\$DATABASE DB,V\$INSTANCE INST ),
DG_TAB AS (
SELECT IS_DG,DG_TNS
FROM (SELECT IS_DG,DECODE(IS_DG,'YES',DG_TNS1,'None') AS "DG_TNS"
FROM (SELECT DECODE(count(*),0,'NO','YES') AS "IS_DG" FROM V\$ARCHIVE_DEST WHERE STATUS = 'VALID' and TARGET = 'STANDBY') DG1,
     (SELECT DECODE(COUNT(*),0,'',MAX(PARAM.VALUE)) AS "DG_TNS1" FROM V\$PARAMETER PARAM WHERE LOWER(PARAM.NAME)=LOWER('log_archive_config')) DG2)
),
RAC_TAB AS (
SELECT IS_RAC,RAC_NODE FROM (SELECT IS_RAC,DECODE(IS_RAC,'YES',NODE_LIST,'None') AS "RAC_NODE"
FROM (SELECT DECODE(upper(VALUE),'TRUE','YES','FALSE','NO','WARNING-DATA MISSMATCH') AS "IS_RAC" FROM V\$PARAMETER PARAM WHERE LOWER(PARAM.NAME)=LOWER('cluster_database')) RAC1,
         (SELECT LISTAGG(GINST.HOST_NAME, ',') WITHIN GROUP (ORDER BY GINST.HOST_NAME) AS "NODE_LIST" FROM GV\$INSTANCE GINST) RAC2)
),
TDE_WALLET_TAB AS (
SELECT WALLET_LOCATION,WALLET_STATUS,WALLET_TYPE,TDE_TBSCOUNT
FROM (SELECT MAX(ENCTDE.WRL_PARAMETER) AS "WALLET_LOCATION",MAX(ENCTDE.STATUS) AS "WALLET_STATUS",MAX(ENCTDE.WALLET_TYPE) AS "WALLET_TYPE" FROM V\$ENCRYPTION_WALLET ENCTDE),
         (SELECT COUNT(*) AS "TDE_TBSCOUNT" FROM DBA_TABLESPACES TSB WHERE TSB.ENCRYPTED='YES')
),
DATA_TEMP_STATUS_TAB AS (
SELECT OFFLINE_DATAFILE,OFFLINE_TEMPFILE,NEED_RECOVERY FROM
(SELECT CASE WHEN COUNT(*) > 0 THEN 'YES' ELSE 'NO' END AS "OFFLINE_DATAFILE" FROM V\$DATAFILE WHERE STATUS IN ('OFFLINE','RECOVER','SYSOFF')),
(SELECT CASE WHEN COUNT(*) > 0 THEN 'YES' ELSE 'NO' END AS "OFFLINE_TEMPFILE" FROM V\$TEMPFILE WHERE STATUS IN ('OFFLINE','RECOVER','SYSOFF')),
(SELECT CASE WHEN COUNT(*) > 0 THEN 'YES' ELSE 'NO' END AS "NEED_RECOVERY" FROM V\$RECOVER_FILE RF_CHECK)
),
PDB_TAB AS (
SELECT IS_PDB,PDB_LIST FROM (SELECT IS_PDB,DECODE(IS_PDB,'YES',PDB_NAMES,'None') AS "PDB_LIST"
FROM (SELECT UPPER(CDB) AS "IS_PDB" FROM V\$DATABASE),
(SELECT LISTAGG(NAME || ':' || OPEN_MODE, ',') WITHIN GROUP (ORDER BY NAME) AS PDB_NAMES FROM V\$PDBS))
),
RESOURCE_TAB AS (
SELECT PGA_LIMIT,PGA_TARGET,SGA_TARGET,SGA_MAX,MEMORY_MAX,MEMORY_TARGET,CPUCOUNT,ALLOC_PGA_MB,TOTAL_SGA_MB,TOTALSIZE,DATAFILESIZE,TEMPFILESIZE,SEGMENTSIZE FROM
(SELECT VALUE AS "PGA_LIMIT" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('pga_aggregate_limit')),
(SELECT VALUE AS "PGA_TARGET" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('pga_aggregate_target')),
(SELECT VALUE AS "SGA_TARGET" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('sga_target')),
(SELECT VALUE AS "SGA_MAX" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('sga_max_size')),
(SELECT VALUE AS "MEMORY_MAX" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('memory_max_target')),
(SELECT VALUE AS "MEMORY_TARGET" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('memory_target')),
(SELECT VALUE AS "CPUCOUNT" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('cpu_count')),
(select round(value/1024/1024,2) AS "ALLOC_PGA_MB" from V\$pgastat where name in ('total PGA allocated')),
(SELECT round(sum(value)/1024/1024,2) AS "TOTAL_SGA_MB" FROM V\$sga),
(SELECT TOTALSIZE,DATAFILESIZE,TEMPFILESIZE,SEGMENTSIZE FROM
(SELECT ROUND(SUM(GBSIZE),2) AS "TOTALSIZE" FROM (
SELECT SUM(BYTES)/1024/1024/1024 AS "GBSIZE" FROM V\$DATAFILE
UNION
SELECT SUM(BYTES)/1024/1024/1024 AS "GBSIZE" FROM V\$TEMPFILE
UNION
SELECT SUM(BYTES)/1024/1024/1024 AS "GBSIZE" FROM V\$LOG)),
(SELECT ROUND(SUM(BYTES)/1024/1024/1024,2) AS "DATAFILESIZE" FROM V\$DATAFILE),
(SELECT ROUND(SUM(BYTES)/1024/1024/1024,2) AS "TEMPFILESIZE" FROM V\$TEMPFILE),
(SELECT ROUND(SUM(BYTES)/1024/1024/1024,2) AS "SEGMENTSIZE" FROM DBA_SEGMENTS))
)
SELECT * FROM DB_INST_TAB,DG_TAB,RAC_TAB,TDE_WALLET_TAB,DATA_TEMP_STATUS_TAB,PDB_TAB,RESOURCE_TAB);
exit;
EOF
)"
;;
12)
#LOG_MESSAGE "In 12c : $sqlp_version"
select_op="$($SQLP -S / as sysdba <<EOF
SET HEADING OFF
SET FEEDBACK OFF
SET ECHO OFF
SET PAGES 0
SET LINE 32767
alter session set nls_date_format='DD-MON-YYYY HH24:MI:SS';
WHENEVER SQLERROR EXIT SQL.SQLCODE;
WHENEVER OSERROR  EXIT SQL.SQLCODE;
SELECT
'ROWST'||'|'||
INSTANCE_NAME||'|'||
HOST_NAME||'|'||
VERSION||'|'||
STARTUP_TIME||'|'||
STATUS||'|'||
LOGINS||'|'||
DATABASE_STATUS||'|'||
INSTANCE_ROLE||'|'||
DBID||'|'||
NAME||'|'||
CREATED||'|'||
RESETLOGS_TIME||'|'||
LOG_MODE||'|'||
OPEN_MODE||'|'||
PROTECTION_MODE||'|'||
PROTECTION_LEVEL||'|'||
DATABASE_ROLE||'|'||
FORCE_LOGGING||'|'||
PLATFORM_ID||'|'||
PLATFORM_NAME||'|'||
FLASHBACK_ON||'|'||
DB_UNIQUE_NAME||'|'||
IS_DG||'|'||
DG_TNS||'|'||
IS_RAC||'|'||
RAC_NODE||'|'||
WALLET_LOCATION||'|'||
WALLET_STATUS||'|'||
WALLET_TYPE||'|'||
TDE_TBSCOUNT||'|'||
OFFLINE_DATAFILE||'|'||
OFFLINE_TEMPFILE||'|'||
NEED_RECOVERY||'|'||
IS_PDB||'|'||
PDB_LIST||'|'||
PGA_LIMIT||'|'||
PGA_TARGET||'|'||
SGA_TARGET||'|'||
SGA_MAX||'|'||
MEMORY_MAX||'|'||
MEMORY_TARGET||'|'||
CPUCOUNT||'|'||
ALLOC_PGA_MB||'|'||
TOTAL_SGA_MB||'|'||
TOTALSIZE||'|'||
DATAFILESIZE||'|'||
TEMPFILESIZE||'|'||
SEGMENTSIZE||'|'||
'ROWED'
FROM (
WITH
DB_INST_TAB AS (
SELECT
INST.INSTANCE_NAME,
INST.HOST_NAME,
INST.VERSION,
INST.STARTUP_TIME,
INST.STATUS,
INST.LOGINS,
INST.DATABASE_STATUS,
INST.INSTANCE_ROLE,
INST.SHUTDOWN_PENDING,
DB.DBID,
DB.NAME,
DB.CREATED,
DB.RESETLOGS_TIME,
DB.LOG_MODE,
DB.OPEN_MODE,
DB.PROTECTION_MODE,
DB.PROTECTION_LEVEL,
DB.DATABASE_ROLE,
DB.FORCE_LOGGING,
DB.PLATFORM_ID,
DB.PLATFORM_NAME,
DB.FLASHBACK_ON,
DB.DB_UNIQUE_NAME
FROM V\$DATABASE DB,V\$INSTANCE INST ),
DG_TAB AS (
SELECT IS_DG,DG_TNS
FROM (SELECT IS_DG,DECODE(IS_DG,'YES',DG_TNS1,'None') AS "DG_TNS"
FROM (SELECT DECODE(count(*),0,'NO','YES') AS "IS_DG" FROM V\$ARCHIVE_DEST WHERE STATUS = 'VALID' and TARGET = 'STANDBY') DG1,
     (SELECT DECODE(COUNT(*),0,'',MAX(PARAM.VALUE)) AS "DG_TNS1" FROM V\$PARAMETER PARAM WHERE LOWER(PARAM.NAME)=LOWER('log_archive_config')) DG2)
),
RAC_TAB AS (
SELECT IS_RAC,RAC_NODE FROM (SELECT IS_RAC,DECODE(IS_RAC,'YES',NODE_LIST,'None') AS "RAC_NODE"
FROM (SELECT DECODE(upper(VALUE),'TRUE','YES','FALSE','NO','WARNING-DATA MISSMATCH') AS "IS_RAC" FROM V\$PARAMETER PARAM WHERE LOWER(PARAM.NAME)=LOWER('cluster_databASe')) RAC1,
         (SELECT LISTAGG(GINST.HOST_NAME, ',') WITHIN GROUP (ORDER BY GINST.HOST_NAME) AS "NODE_LIST" FROM GV\$INSTANCE GINST) RAC2)
),
TDE_WALLET_TAB AS (
SELECT WALLET_LOCATION,WALLET_STATUS,WALLET_TYPE,TDE_TBSCOUNT
FROM (SELECT MAX(ENCTDE.WRL_PARAMETER) AS "WALLET_LOCATION",MAX(ENCTDE.STATUS) AS "WALLET_STATUS",MAX(ENCTDE.WALLET_TYPE) AS "WALLET_TYPE" FROM V\$ENCRYPTION_WALLET ENCTDE),
         (SELECT COUNT(*) AS "TDE_TBSCOUNT" FROM DBA_TABLESPACES TSB WHERE TSB.ENCRYPTED='YES')
),
DATA_TEMP_STATUS_TAB AS (
SELECT OFFLINE_DATAFILE,OFFLINE_TEMPFILE,NEED_RECOVERY FROM
(SELECT CASE WHEN COUNT(*) > 0 THEN 'YES' ELSE 'NO' END AS "OFFLINE_DATAFILE" FROM V\$DATAFILE WHERE STATUS IN ('OFFLINE','RECOVER','SYSOFF')),
(SELECT CASE WHEN COUNT(*) > 0 THEN 'YES' ELSE 'NO' END AS "OFFLINE_TEMPFILE" FROM V\$TEMPFILE WHERE STATUS IN ('OFFLINE','RECOVER','SYSOFF')),
(SELECT CASE WHEN COUNT(*) > 0 THEN 'YES' ELSE 'NO' END AS "NEED_RECOVERY" FROM V\$RECOVER_FILE RF_CHECK)
),
PDB_TAB AS (
SELECT IS_PDB,PDB_LIST FROM (SELECT IS_PDB,DECODE(IS_PDB,'YES',PDB_NAMES,'None') AS "PDB_LIST"
FROM (SELECT UPPER(CDB) AS "IS_PDB" FROM V\$DATABASE),
(SELECT LISTAGG(NAME || ':' || OPEN_MODE, ',') WITHIN GROUP (ORDER BY NAME) AS PDB_NAMES FROM V\$PDBS))
),
RESOURCE_TAB AS (
SELECT PGA_LIMIT,PGA_TARGET,SGA_TARGET,SGA_MAX,MEMORY_MAX,MEMORY_TARGET,CPUCOUNT,ALLOC_PGA_MB,TOTAL_SGA_MB,TOTALSIZE,DATAFILESIZE,TEMPFILESIZE,SEGMENTSIZE FROM
(SELECT VALUE AS "PGA_LIMIT" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('pga_aggregate_limit')),
(SELECT VALUE AS "PGA_TARGET" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('pga_aggregate_target')),
(SELECT VALUE AS "SGA_TARGET" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('sga_target')),
(SELECT VALUE AS "SGA_MAX" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('sga_max_size')),
(SELECT VALUE AS "MEMORY_MAX" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('memory_max_target')),
(SELECT VALUE AS "MEMORY_TARGET" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('memory_target')),
(SELECT VALUE AS "CPUCOUNT" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('cpu_count')),
(select round(value/1024/1024,2) AS "ALLOC_PGA_MB" from V\$pgastat where name in ('total PGA allocated')),
(SELECT round(sum(value)/1024/1024,2) AS "TOTAL_SGA_MB" FROM V\$sga),
(SELECT TOTALSIZE,DATAFILESIZE,TEMPFILESIZE,SEGMENTSIZE FROM
(SELECT ROUND(SUM(GBSIZE),2) AS "TOTALSIZE" FROM (
SELECT SUM(BYTES)/1024/1024/1024 AS "GBSIZE" FROM V\$DATAFILE
UNION
SELECT SUM(BYTES)/1024/1024/1024 AS "GBSIZE" FROM V\$TEMPFILE
UNION
SELECT SUM(BYTES)/1024/1024/1024 AS "GBSIZE" FROM V\$LOG)),
(SELECT ROUND(SUM(BYTES)/1024/1024/1024,2) AS "DATAFILESIZE" FROM V\$DATAFILE),
(SELECT ROUND(SUM(BYTES)/1024/1024/1024,2) AS "TEMPFILESIZE" FROM V\$TEMPFILE),
(SELECT ROUND(SUM(BYTES)/1024/1024/1024,2) AS "SEGMENTSIZE" FROM DBA_SEGMENTS))
)
SELECT * FROM DB_INST_TAB,DG_TAB,RAC_TAB,TDE_WALLET_TAB,DATA_TEMP_STATUS_TAB,PDB_TAB,RESOURCE_TAB);
exit;
EOF
)"
;;
11)
#LOG_MESSAGE "In 11g : $sqlp_version"
select_op="$($SQLP -S / as sysdba <<EOF
SET HEADING OFF
SET FEEDBACK OFF
SET ECHO OFF
SET PAGES 0
SET LINE 32767
alter session set nls_date_format='DD-MON-YYYY HH24:MI:SS';
WHENEVER SQLERROR EXIT SQL.SQLCODE;
WHENEVER OSERROR  EXIT SQL.SQLCODE;
SELECT
'ROWST'||'|'||
INSTANCE_NAME||'|'||
HOST_NAME||'|'||
VERSION||'|'||
STARTUP_TIME||'|'||
STATUS||'|'||
LOGINS||'|'||
DATABASE_STATUS||'|'||
INSTANCE_ROLE||'|'||
DBID||'|'||
NAME||'|'||
CREATED||'|'||
RESETLOGS_TIME||'|'||
LOG_MODE||'|'||
OPEN_MODE||'|'||
PROTECTION_MODE||'|'||
PROTECTION_LEVEL||'|'||
DATABASE_ROLE||'|'||
FORCE_LOGGING||'|'||
PLATFORM_ID||'|'||
PLATFORM_NAME||'|'||
FLASHBACK_ON||'|'||
DB_UNIQUE_NAME||'|'||
IS_DG||'|'||
DG_TNS||'|'||
IS_RAC||'|'||
RAC_NODE||'|'||
WALLET_LOCATION||'|'||
WALLET_STATUS||'|'||
WALLET_TYPE||'|'||
TDE_TBSCOUNT||'|'||
OFFLINE_DATAFILE||'|'||
OFFLINE_TEMPFILE||'|'||
NEED_RECOVERY||'|'||
IS_PDB||'|'||
PDB_LIST||'|'||
PGA_LIMIT||'|'||
PGA_TARGET||'|'||
SGA_TARGET||'|'||
SGA_MAX||'|'||
MEMORY_MAX||'|'||
MEMORY_TARGET||'|'||
CPUCOUNT||'|'||
ALLOC_PGA_MB||'|'||
TOTAL_SGA_MB||'|'||
TOTALSIZE||'|'||
DATAFILESIZE||'|'||
TEMPFILESIZE||'|'||
SEGMENTSIZE||'|'||
'ROWED'
FROM (
WITH
DB_INST_TAB AS (
SELECT
INST.INSTANCE_NAME,
INST.HOST_NAME,
INST.VERSION,
INST.STARTUP_TIME,
INST.STATUS,
INST.LOGINS,
INST.DATABASE_STATUS,
INST.INSTANCE_ROLE,
DB.DBID,
DB.NAME,
DB.CREATED,
DB.RESETLOGS_TIME,
DB.LOG_MODE,
DB.OPEN_MODE,
DB.PROTECTION_MODE,
DB.PROTECTION_LEVEL,
DB.DATABASE_ROLE,
DB.FORCE_LOGGING,
DB.PLATFORM_ID,
DB.PLATFORM_NAME,
DB.FLASHBACK_ON,
DB.DB_UNIQUE_NAME
FROM V\$DATABASE DB,V\$INSTANCE INST ),
DG_TAB AS (
SELECT IS_DG,DG_TNS
FROM (SELECT IS_DG,DECODE(IS_DG,'YES',DG_TNS1,'None') AS "DG_TNS"
FROM (SELECT DECODE(count(*),0,'NO','YES') AS "IS_DG" FROM V\$ARCHIVE_DEST WHERE STATUS = 'VALID' and TARGET = 'STANDBY') DG1,
     (SELECT DECODE(COUNT(*),0,'',MAX(PARAM.VALUE)) AS "DG_TNS1" FROM V\$PARAMETER PARAM WHERE LOWER(PARAM.NAME)=LOWER('log_archive_config')) DG2)
),
RAC_TAB AS (
SELECT IS_RAC,RAC_NODE FROM (SELECT IS_RAC,DECODE(IS_RAC,'YES',NODE_LIST,'None') AS "RAC_NODE"
FROM (SELECT DECODE(upper(VALUE),'TRUE','YES','FALSE','NO','WARNING-DATA MISSMATCH') AS "IS_RAC" FROM V\$PARAMETER PARAM WHERE LOWER(PARAM.NAME)=LOWER('cluster_databASe')) RAC1,
         (SELECT LISTAGG(GINST.HOST_NAME, ',') WITHIN GROUP (ORDER BY GINST.HOST_NAME) AS "NODE_LIST" FROM GV\$INSTANCE GINST) RAC2)
),
TDE_WALLET_TAB AS (
SELECT WALLET_LOCATION,WALLET_STATUS,WALLET_TYPE,TDE_TBSCOUNT
FROM (SELECT MAX(ENCTDE.WRL_PARAMETER) AS "WALLET_LOCATION",MAX(ENCTDE.STATUS) AS "WALLET_STATUS",MAX('NOCOLUMNIN11G') AS "WALLET_TYPE" FROM V\$ENCRYPTION_WALLET ENCTDE),
         (SELECT COUNT(*) AS "TDE_TBSCOUNT" FROM DBA_TABLESPACES TSB WHERE TSB.ENCRYPTED='YES')
),
DATA_TEMP_STATUS_TAB AS (
SELECT OFFLINE_DATAFILE,OFFLINE_TEMPFILE,NEED_RECOVERY FROM
(SELECT CASE WHEN COUNT(*) > 0 THEN 'YES' ELSE 'NO' END AS "OFFLINE_DATAFILE" FROM V\$DATAFILE WHERE STATUS IN ('OFFLINE','RECOVER','SYSOFF')),
(SELECT CASE WHEN COUNT(*) > 0 THEN 'YES' ELSE 'NO' END AS "OFFLINE_TEMPFILE" FROM V\$TEMPFILE WHERE STATUS IN ('OFFLINE','RECOVER','SYSOFF')),
(SELECT CASE WHEN COUNT(*) > 0 THEN 'YES' ELSE 'NO' END AS "NEED_RECOVERY" FROM V\$RECOVER_FILE RF_CHECK)
),
DATA_TEMP_STATUS_TAB AS (
SELECT OFFLINE_DATAFILE,OFFLINE_TEMPFILE,NEED_RECOVERY FROM
(SELECT CASE WHEN COUNT(*) > 0 THEN 'YES' ELSE 'NO' END AS "OFFLINE_DATAFILE" FROM V\$DATAFILE WHERE STATUS IN ('OFFLINE','RECOVER','SYSOFF')),
(SELECT CASE WHEN COUNT(*) > 0 THEN 'YES' ELSE 'NO' END AS "OFFLINE_TEMPFILE" FROM V\$TEMPFILE WHERE STATUS IN ('OFFLINE','RECOVER','SYSOFF')),
(SELECT CASE WHEN COUNT(*) > 0 THEN 'YES' ELSE 'NO' END AS "NEED_RECOVERY" FROM V\$RECOVER_FILE RF_CHECK)
),
PDB_TAB AS (
SELECT 'NO' AS "IS_PDB",'None' AS "PDB_LIST" FROM DUAL
),
RESOURCE_TAB AS (
SELECT PGA_LIMIT,PGA_TARGET,SGA_TARGET,SGA_MAX,MEMORY_MAX,MEMORY_TARGET,CPUCOUNT,ALLOC_PGA_MB,TOTAL_SGA_MB,TOTALSIZE,DATAFILESIZE,TEMPFILESIZE,SEGMENTSIZE FROM
(SELECT 'NOTVALIDFOR-10G-11G' AS "PGA_LIMIT" FROM DUAL),
(SELECT VALUE AS "PGA_TARGET" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('pga_aggregate_target')),
(SELECT VALUE AS "SGA_TARGET" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('sga_target')),
(SELECT VALUE AS "SGA_MAX" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('sga_max_size')),
(SELECT VALUE AS "MEMORY_MAX" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('memory_max_target')),
(SELECT VALUE AS "MEMORY_TARGET" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('memory_target')),
(SELECT VALUE AS "CPUCOUNT" FROM V\$PARAMETER WHERE LOWER(NAME)=LOWER('cpu_count')),
(select round(value/1024/1024) AS "ALLOC_PGA_MB" from V\$pgastat where name in ('total PGA allocated')),
(SELECT round(sum(value)/1024/1024) AS "TOTAL_SGA_MB" FROM V\$sga),
(SELECT TOTALSIZE,DATAFILESIZE,TEMPFILESIZE,SEGMENTSIZE FROM
(SELECT ROUND(SUM(GBSIZE)) AS "TOTALSIZE" FROM (
SELECT SUM(BYTES)/1024/1024/1024 AS "GBSIZE" FROM V\$DATAFILE
UNION
SELECT SUM(BYTES)/1024/1024/1024 AS "GBSIZE" FROM V\$TEMPFILE
UNION
SELECT SUM(BYTES)/1024/1024/1024 AS "GBSIZE" FROM V\$LOG)),
(SELECT ROUND(SUM(BYTES)/1024/1024/1024) AS "DATAFILESIZE" FROM V\$DATAFILE),
(SELECT ROUND(SUM(BYTES)/1024/1024/1024) AS "TEMPFILESIZE" FROM V\$TEMPFILE),
(SELECT ROUND(SUM(BYTES)/1024/1024/1024) AS "SEGMENTSIZE" FROM DBA_SEGMENTS))
)
SELECT * FROM DB_INST_TAB,DG_TAB,RAC_TAB,TDE_WALLET_TAB,DATA_TEMP_STATUS_TAB,PDB_TAB,RESOURCE_TAB);
exit;
EOF
)"
;;
*)
DB_DATA="$(LOG_DB_DATA)"
#echo "$DB_DATA"
LOG_ERROR $LINENO "Unsupported database for $ora_sid , Expected (11,12,18,19), Actual ($sqlp_version)"
return 1
esac

# case "$bash_major_version" in
#  3)
#    IFS='|'
#    index=0
#    for value in "$select_op"; do
#       ADDR[index]=$value
#       ((index++))
#    done
#       ;;
#   *)
#   IFS='|' read -ra ADDR <<< "$select_op"
#   ;;
# esac
#column_count=$(( ${#ADDR[@]} ))

#LOG_MESSAGE "select_result : $select_op"
local first_val=$(echo "$select_op" | awk -F'|' '{print $1}')
local last_val=$(echo "$select_op" | awk -F'|' '{print $NF}')
local column_count=$(echo "$select_op" | awk -F'|' '{print NF}')
local actual_column_count=$(( ${#DB_COLUMNS[@]} ))

local sp_err="$(echo "$select_op" | grep '^.*SP2-[0-9]\{4\}:' | head -n1)"
local ora_err="$(echo "$select_op" | grep '^.*ORA-[0-9]\{5\}:' | head -n1)"

if [ "$first_val" = 'ROWST' ] && [ "$last_val" = 'ROWED' ] && [ "$column_count" = "$actual_column_count" ]; then
  DB_DATA="$select_op"
  #echo "$DB_DATA"
elif [ -n "$sp_err" ]; then
  DB_DATA="$(LOG_DB_DATA)"
  #echo "$DB_DATA"
  LOG_ERROR $LINENO "Unable to get the db data;[Error:$sp_err] for $ora_sid"
elif [ -n "$ora_err" ]; then
  DB_DATA="$(LOG_DB_DATA)"
  #echo "$DB_DATA"
  LOG_ERROR $LINENO "Unable to get the db data;[Error:$ora_err] for $ora_sid"
elif [ -z "$select_op" ] ; then
  DB_DATA="$(LOG_DB_DATA)"
  #echo "$DB_DATA"
  LOG_ERROR $LINENO "Unable to get the db data;[Error:$ora_err] for $ora_sid"
else
  DB_DATA="$(LOG_DB_DATA)"
  #echo "$DB_DATA"
  LOG_ERROR $LINENO "Unable to get the db data;[Error:Unknown Error] for $ora_sid"
fi

return 0
}

LOG_MESSAGE "Execution start on $(hostname) at $(date)"
LOG_MESSAGE "Logfile => $log_file"
LOG_MESSAGE "**********************************"

grep "^[A-Za-z+]" "$ORATAB" | grep -v "^$" | while read -r line
do
DB_SID=$(echo "$line" | cut -d':' -f1)
DB_HOME=$(echo "$line" | cut -d':' -f2)
AUTO_START=$(echo "$line" | cut -d':' -f3)

# Rest function veriables.
RESET_OS_DATA
RESET_DB_DATA

LOG_MESSAGE "ORACLE_HOME SET TO $DB_HOME"
LOG_MESSAGE "ORACLE_SID SET TO $DB_SID"

# Call function to get os data.
LOG_MESSAGE "Collecting OS related metadata."
GET_OS_DATA "$DB_SID" "$DB_HOME" "$AUTO_START"

# Call function to get db data.
LOG_MESSAGE "Collecting Database related metadata."
if [ "$home_exist" = 'YES' ] && [ "$sid_status" = 'UP' ] && [ "$home_type" = 'OH' ] && [ "$db_status" = 'OPEN' ]; then
  GET_DB_DATA "$DB_SID" "$DB_HOME" "$sqlplus_version"
else
  DB_DATA="$(LOG_DB_DATA)"
  #echo "$DB_DATA"
fi

# Merage Key,OS and DB data , Print the data.
DBI_KEY=${DB_SID}@$(hostname | cut -d'.' -f1)
OS_DB_DATA="$DBI_KEY|$OS_DATA|$OS_ENV_DATA|$DB_DATA"

LOG_RESULT "$OS_DB_DATA"
echo "$OS_DB_DATA"

# Reset the key veriables to avoid any duplicate executions.
unset DB_SID
unset DB_HOME
unset AUTO_START
unset DBI_KEY
done
LOG_MESSAGE "Execution end on $(hostname) at $(date)"
exit;
