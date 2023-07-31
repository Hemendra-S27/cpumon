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


# Function to check Oracle services status
check_oracle_services() {
    # Check Oracle DB
	LOG_MESSAGE "Checking pmon."
    ORACLE_DB_STATUS=$(ps -ef | grep pmon | grep -v grep)
    
    # Check Oracle listener
	LOG_MESSAGE "Checking tnslsnr."
    ORACLE_LISTENER_STATUS=$(ps -ef | grep -i "tns" | grep -v "grep" | grep -v "netns")
    
    # Check Oracle Agent
	LOG_MESSAGE "Checking Oracle Agent."
    ORACLE_AGENT_STATUS=$(ps -ef | grep -i [e]magent | grep -v grep)
    
    # If any service is down, return NO
    if [ -z "$ORACLE_DB_STATUS" ] || [ -z "$ORACLE_LISTENER_STATUS" ] || [ -z "$ORACLE_AGENT_STATUS" ]; then
	    LOG_MESSAGE "Oracle service active on server => NO"
        LOG_RESULT "NO"
        return 1
    fi

    # If we got here, all services are running
	LOG_MESSAGE "Oracle service active on server => YES"
    LOG_RESULT "YES"
    return 0
}

# Use the function
LOG_MESSAGE "Checking if any oracle services are active on server."
check_oracle_services
exit $?
