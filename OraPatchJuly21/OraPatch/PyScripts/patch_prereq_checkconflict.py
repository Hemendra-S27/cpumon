import yaml
import sys
import threading
import paramiko
import os
import time
import sqlite3
import datetime
import argparse
import logging
from concurrent.futures import ThreadPoolExecutor

# python run_script.py servername1
# python run_script.py servername2

#PROMPT_MODE = True
PROMPT_MODE = False

DEFAULT_DELAY = 0
START_TIME = datetime.datetime.now()
TIMESTAMP_TAG = datetime.datetime.now().strftime("_%Y%m%d%H%M%S")
MAX_WORKERS = 1  # Number of parallel tasks.
patch_pre_status = {}  # Global dictionary to hold start time, end time, and status for each server

def delay(seconds=None):
    if seconds is None:
        seconds = DEFAULT_DELAY
    time.sleep(seconds)


def load_config():
    """Function to load configuration from a yaml file."""
    script_location = os.path.abspath(__file__)
    parent_directory = os.path.dirname(script_location)
    base_directory = os.path.dirname(parent_directory)
    yaml_file_location = os.path.join(base_directory, "Config", "global_config.yaml")
    with open(yaml_file_location, "r") as f:
        config = yaml.safe_load(f)
    return config

config = load_config()

PROGRAM_NAME = os.path.splitext(os.path.basename(__file__))[0]
SENDER_EMAIL = config["SENDER_EMAIL"]
SQLITE_DB = os.path.join(config["SQLITEDB_DIR"], config["MASTER_DB"])
shell_program_name = os.path.join(config["SHELL_DIR"], "db_inventory.sh")
MAIL_TEMPLATE_DIR = config["HTML_DIR"]
MAIL_TEMPLATE_FILE = "db_patch_map_inventory_mail_template.html"
MAIL_BODY = os.path.join(config["HTML_DIR"], "db_inventory_mail_body.html")
LOCKFILE = os.path.join(config["LOCK_DIR"], f"{PROGRAM_NAME}.lck")
SERVER_LIST = os.path.join(config["SERVERLIST_DIR"], "database_server_list.lst")
DB_INVENTORY = os.path.join(config["CSV_DIR"], f"db_inventory{TIMESTAMP_TAG}.csv")
DB_PATCH_MAP_INVENTORY = os.path.join(config["CSV_DIR"], f"db_patch_map_inventory{TIMESTAMP_TAG}.csv")
EXECUTION_SUMMARY = os.path.join(config["CSV_DIR"], f"db_inventory_execution_summary{TIMESTAMP_TAG}.csv")
PATCH_CYCLE = config["CURRENT_PATCH_CYCLE"]
BKP_LOC = config.get("BKP_LOC", '/u01/software/bkp_dir')
PATCH_TASK_DIR = '/u01/home/oracle/OraPatch_Stage/PatchTask'
PATCHDB_YAML = config["PATCHDB_DIR"]
SCRIPT_DIR = config["SHELL_DIR"]
LOGFILE_DIR = config["LOG_DIR"]

# Set up logging
logging.getLogger("paramiko").setLevel(logging.WARNING)
log_file = os.path.join(config["LOCK_DIR"], f"{PROGRAM_NAME}{TIMESTAMP_TAG}.log")
logging.basicConfig(level=logging.INFO,
                    format='%(asctime)s :: %(levelname)s :: %(threadName)s :: %(message)s',
                    datefmt='%Y-%m-%d %H:%M:%S',
                    handlers=[
                        logging.StreamHandler(sys.stdout),  # log to the console
                        logging.FileHandler(log_file)  # log to a file
                    ])

ssh = paramiko.SSHClient()
ssh.load_system_host_keys()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

def connect_to_server(server_name):
    """
    Connect to the specified server via SSH
    """
    try:
        ssh.connect(server_name, timeout=60)
    except paramiko.AuthenticationException:
        logging.error(f"Authentication failed for {server_name}")
        return False
    except paramiko.SSHException as e:
        logging.error(f"Error connecting to {server_name}: {str(e)}")
        return False
    except Exception as e:
        logging.error(f"Unexpected error for {server_name}: {str(e)}")
        return False

    return True

def run_script(server_name, shell_program_name, src_type="local"):
    script_name, *script_args = shell_program_name.split(" ",1)
    script_args = script_args[0] if script_args else ""
    script_path = os.path.join(SCRIPT_DIR, script_name)

    if src_type == 'local':
        run_local_script(server_name, script_path, script_args)
    elif src_type == 'remote':
        run_remote_script(server_name, script_path, script_args)
    else:
        logging.info(f"Invalid script type: {script_args}")

def run_local_script(server_name, script_path, script_args):
    with open(script_path, 'rb') as script_file:
        script_data = script_file.read()

    stdin, stdout, stderr = ssh.exec_command(f'bash -s - {script_args}')
    stdin.write(script_data)
    stdin.flush()
    stdin.channel.shutdown_write()

    # Create threads for stdout and stderr
    create_threads(server_name, stdout, stderr)

def run_remote_script(server_name, script_path, script_args):
    stdin, stdout, stderr = ssh.exec_command(f'{script_path} {script_args}')
    create_threads(server_name, stdout, stderr)

"""
def create_threads(server_name, stdout, stderr):
    stdout_thread = threading.Thread(target=print_output, args=(server_name, stdout))
    stdout_thread.start()

    stderr_thread = threading.Thread(target=print_output, args=(server_name, stderr))
    stderr_thread.start()

    stdout_thread.join()
    stderr_thread.join()
"""

def create_threads(server_name, stdout, stderr):
    stdout_thread = threading.Thread(target=print_output, args=(server_name, stdout, "stdout"))
    stdout_thread.start()

    stderr_thread = threading.Thread(target=print_output, args=(server_name, stderr, "stderr"))
    stderr_thread.start()

    stdout_thread.join()
    stderr_thread.join()


def print_output(server_name, stream, stream_type):
    # Define a logger for this server
    server_logger = logging.getLogger(f"{server_name}_{stream_type}")
    server_logger.setLevel(logging.INFO)

    # Determine the log file based on the stream type
    if stream_type == "stdout":
        log_file = os.path.join(config["LOG_DIR"], f"{server_name}_stdout{TIMESTAMP_TAG}.log")
    elif stream_type == "stderr":
        log_file = os.path.join(config["LOG_DIR"], f"{server_name}_stderr{TIMESTAMP_TAG}.log")

    # Create a file handler for this server's log
    file_handler = logging.FileHandler(log_file)
    file_handler.setLevel(logging.INFO)

    # Add the handler to the logger
    server_logger.addHandler(file_handler)

    for line in iter(stream.readline, ""):
        line = line.strip()
        server_logger.info(line)

    # Remove the handler after use to prevent logging to closed files
    server_logger.removeHandler(file_handler)


def load_yaml_file(yaml_path):
    try:
        with open(yaml_path, 'r') as yaml_file:
            yaml_data = yaml.safe_load(yaml_file)
        return yaml_data
    except FileNotFoundError:
        logging.error(f"File not found: {yaml_path}")
        return None
    except yaml.YAMLError as err:
        logging.error(f"Error parsing YAML file: {err}")
        return None

def format_arguments(task, ora_home, bkp_loc, ora_inv, opatch_zip, sid_list=None, patch_name=None, patch_home=None):
    arg_strs = []
    for arg in task['arguments']:
        #print(f"Processing: {arg}")
        if arg == 'start' or arg == 'stop':
            formatted_arg = f'{arg}'
        elif arg == 'OraHome':
            formatted_arg = f'-{arg} {ora_home}'
        elif arg == 'BkpLoc':
            formatted_arg = f'-{arg} {bkp_loc}'
        elif arg == 'OraInv':
            formatted_arg = f'-{arg} {ora_inv}'
        elif arg == 'OpatchZip':
            formatted_arg = f'-{arg} {opatch_zip}'
        elif arg == 'PatchName' and patch_name:
            formatted_arg = f'-{arg} {patch_name}'
        elif arg == 'PatchHome' and patch_home:
            formatted_arg = f'-{arg} {patch_home}'
        elif arg == 'SidList' and sid_list:
            formatted_arg = f'-{arg} {sid_list}'
        else:
            formatted_arg = f'-{arg} None'
        arg_strs.append(formatted_arg)
    return arg_strs


def create_task_info(task, arg_strs):
    shell_program_name = task['path'] + ' ' + ' '.join(arg_strs)
    return {'task_name': task['name'], 'shell_program_name': shell_program_name, 'execute': task['execute'], 'script_type': task['type']}

"""
def create_task_info(task, arg_strs):
    logging.info(f"task['path']: {task['path']}")
    logging.info(f"arg_strs: {arg_strs}")
    shell_program_name = task['path'] + ' ' + ' '.join(arg_strs)
    logging.info(f"shell_program_name: {shell_program_name}")
    return {'task_name': task['name'], 'shell_program_name': shell_program_name, 'execute': task['execute'], 'script_type': task['type']}
"""

def process_server(server_name, inventory_key):
    # Create lock file
    lock_file = f"/tmp/{server_name}.lock"
    if os.path.exists(lock_file):
        logging.info(f"Lock file exists for server {server_name}, another instance may be running. Exiting.")
        return
    else:
        open(lock_file, 'a').close()

    try:
        inventory_key_directory = os.path.join(PATCHDB_YAML, inventory_key)
        server_filename = f'{server_name.split(".")[0].lower()}.yaml'
        file_path = os.path.join(inventory_key_directory, server_filename)
        patch_tasks = load_yaml_file(os.path.join(PATCH_TASK_DIR, 'patch_prereq.yaml'))
        patch_homes = load_yaml_file(file_path)
        #patch_tasks = load_yaml_file('patch_prereq.yaml')
        #patch_homes = load_yaml_file(f'{server_name}.yaml')
        global_params = patch_homes['globalparams']
        inv_key = global_params['InventoryKey']
        bkp_loc = global_params['BkpLoc']
        ora_inv = global_params['OraInv']
        oracle_homes = patch_homes['oraclehomes']

        for homes in oracle_homes:
            task_info_list = []
            ora_home = homes['OraHome']
            sid_list = homes['SidList']
            patch_names = homes['PatchName']
            opatch_zip = homes['opatch']['OpatchZip']

            for task in patch_tasks['tasks']:
                if task['execute'] == 'Y':
                    if task['name'] == 'prereq_checkconflict':
                        for patch_name, patch_details in patch_names.items():
                            if patch_details['apply'] == 'Y':
                                patch_home = patch_details['PatchHome']
                                patch_zip = patch_details['PatchZip']
                                arg_strs = format_arguments(task, ora_home, bkp_loc, ora_inv, opatch_zip, sid_list=sid_list, patch_name=patch_name, patch_home=patch_home)
                                task_info_list.append(create_task_info(task, arg_strs))

                    elif task['name'] == 'copy_opatch':
                        arg_strs = format_arguments(task, ora_home, bkp_loc, ora_inv, opatch_zip, sid_list=sid_list)
                        task_info_list.append(create_task_info(task, arg_strs))

            logging.info(f"For Oracle Home: {ora_home}")
            for task_info in task_info_list:
                taskname = task_info['task_name']
                remote_server = f"{server_name}"
                shell_program_name = task_info['shell_program_name']
                script_execute = task_info['execute']
                script_type = task_info['script_type']
                if prompt_task_execution(taskname, remote_server, shell_program_name, script_execute, script_type):
                #if prompt_task_execution(task_info['task_name'], task_info['shell_program_name']):
                    # Connect to the server
                    if not connect_to_server(server_name):
                        logging.info(f"Cannot connect to server: {server_name}")
                        return

                    task_start_time = datetime.datetime.now()  # Start time assigned here
                    logging.info(f"=== Task Info ===")
                    logging.info(f"Database Server : {server_name}")
                    logging.info(f"Task Name           : {taskname}")

                    # Run the script on the server
                    run_script(server_name, task_info['shell_program_name'], task_info['script_type'])
                    task_end_time = datetime.datetime.now()
                    logging.info(f"End Time: {task_end_time.strftime('%Y-%m-%d %H:%M:%S')}\n")

                    # Disconnect from the server
                    ssh.close()
                    logging.info(f"Disconnected from server: {server_name}")
        return True
    except Exception as e:
        logging.error(f"An error occurred: {str(e)}")
        return False
    finally:
        # Remove the lock file
        os.remove(lock_file)
        logging.info(f"Removed the lock file.")

def prompt_task_execution(taskname, remote_server, shell_program_name, script_execute, script_type):
    logging.info(f"=== User Confirmation for Task Execution ===")
    logging.info(f"Task Name           : {taskname}")
    logging.info(f"Database Server     : {remote_server}")
    logging.info(f"Script File         : {shell_program_name}")
    logging.info(f"Script Execurte     : {script_execute}")
    logging.info(f"Script Type         : {script_type}")
    delay()

    if not PROMPT_MODE:
        return True

    while True:
        user_input = input("\nType 'y' to execute , 'exit' to quit: ").lower()
        if user_input == 'y':
            return True
        elif user_input == 'exit':
            print("Terminating program.")
            sys.exit(0)  # Use sys.exit instead of raising SystemExit directly
        else:
            logging.info("Invalid input! Please type 'y' to execute , 'exit' to quit.")


def parse_args():
    parser = argparse.ArgumentParser(description='Process server.')
    parser.add_argument('filename', help='the file with server names')
    parser.add_argument('inventory_key', help='the inventory key')
    return parser.parse_args()


def worker(server_name, inventory_key):
    server = server_name.strip().split(".")[0].lower()
    try:
        # Store the start time in the dictionary
        patch_pre_status[server] = {'start_time': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

        process_server_result = process_server(server, inventory_key)
        if process_server_result:
            logging.info(f"Processing of server {server} was Successful.")
            patch_pre_status[server]['status'] = 'Successful'
        else:
            logging.error(f"Processing of server {server} was Unsuccessful.")
            patch_pre_status[server]['status'] = 'Unsuccessful'
    except Exception as e:
        logging.error(f"An error occurred while processing server {server_name}: {str(e)}")
        patch_pre_status[server]['status'] = 'Error'
    finally:
        # Store the end time in the dictionary
        patch_pre_status[server]['end_time'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

if __name__ == "__main__":
    args = parse_args()
    try:
        with open(args.filename, 'r') as file:
            if PROMPT_MODE:
                # Run serially
                for server_name in file:
                    worker(server_name.strip(), args.inventory_key)
            else:
                # Run in parallel
                with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                    for server_name in file:
                        executor.submit(worker, server_name.strip(), args.inventory_key)
    except FileNotFoundError:
        logging.info(f"File not found: {args.filename}")
        sys.exit(1)

    for server, status in patch_pre_status.items():
        logging.info(f"Server: {server}, Start Time: {status['start_time']}, End Time: {status['end_time']}, Status: {status['status']}")

