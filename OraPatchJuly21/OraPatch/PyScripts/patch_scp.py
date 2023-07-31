import os
import sys
import yaml
import paramiko
import time
import sqlite3
import datetime
import argparse
import logging
from scp import SCPClient
from concurrent.futures import ThreadPoolExecutor

# Set up logging

"""
logging.basicConfig(level=logging.INFO, format='%(asctime)s :: %(levelname)s :: %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
logging.basicConfig(level=logging.INFO,
                    format='%(asctime)s :: %(levelname)s :: %(threadName)s :: %(message)s',
                    datefmt='%Y-%m-%d %H:%M:%S')
"""

START_TIME = datetime.datetime.now()
TIMESTAMP_TAG = datetime.datetime.now().strftime("_%Y%m%d%H%M%S")
DEFAULT_DELAY = 0
PROMPT_MODE = False
#PROMPT_MODE = True
DISK_USAGE_THRESHOLD = 95
SOFTWARE_DIR = "/u01/software"
MAX_WORKERS = 5  # Number of parallel tasks.
patch_scp_status = {}


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
SCRIPT_FQFN = os.path.join(config["SHELL_DIR"], "db_inventory.sh")
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
PATCHDB_YAML = config["PATCHDB_DIR"]
LOGFILE_DIR = config["LOG_DIR"]


# Set up logging
logging.getLogger("paramiko").setLevel(logging.WARNING)
log_file = os.path.join(config["LOG_DIR"], f"{PROGRAM_NAME}{TIMESTAMP_TAG}.log")
logging.basicConfig(level=logging.INFO,
                    format='%(asctime)s :: %(levelname)s :: %(threadName)s :: %(message)s',
                    datefmt='%Y-%m-%d %H:%M:%S',
                    handlers=[
                        logging.StreamHandler(sys.stdout),  # log to the console
                        logging.FileHandler(log_file)  # log to a file
                    ])


def process_server(server_name, inventory_key):
    logging.info(f"Entering process_server with server_name={server_name}, inventory_key={inventory_key}")
    patch_scp_status[server_name] = {"start_time": datetime.datetime.now().isoformat()}
    inventory_key_directory = os.path.join(PATCHDB_YAML, inventory_key)
    server_filename = f'{server_name.split(".")[0].lower()}.yaml'
    file_path = os.path.join(inventory_key_directory, server_filename)
    try:
        logging.info(f"Attempting to open YAML file at {file_path}")
        with open(file_path, 'r') as file:
            data = yaml.safe_load(file)
        logging.info(f"Successfully opened YAML file at {file_path}")
    except yaml.YAMLError as exc:
        logging.error(exc)
        return False
    except FileNotFoundError:
        logging.error(f"File not found: {file_path}")
        return False

    files_to_transfer = []

    for home in data['oraclehomes']:
        for patch in home['PatchName'].values():
            if patch['apply'] == "Y" and patch['PatchZip']:
                files_to_transfer.append(patch['PatchZip'])
        if home['opatch']['OpatchZip']:
            files_to_transfer.append(home['opatch']['OpatchZip'])

    total_size = sum(os.path.getsize(file) for file in files_to_transfer if os.path.isfile(file))

    with paramiko.SSHClient() as ssh:
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(server_name)

        available_space = check_remote_disk_space(ssh, SOFTWARE_DIR, total_size)
        logging.info(f"=== Space Info ===")
        logging.info(f"Database Server : {server_name}")
        logging.info(f"Available space : {available_space / 1024 / 1024}MB")
        logging.info(f"Required space  : {total_size / 1024 / 1024}MB")
        delay()

        if available_space >= total_size:
            transfer_files(ssh, files_to_transfer, server_name)
            space_check_result = True
        else:
            logging.info(f"Insufficient space in the remote directory.")
            space_check_result = False

    patch_scp_status[server_name]["end_time"] = datetime.datetime.now().isoformat()
    patch_scp_status[server_name]["status"] = "Success" if space_check_result else "Failed"

    logging.info(f"Exiting process_server with server_name={server_name}, inventory_key={inventory_key}")
    return space_check_result


def check_remote_disk_space(ssh, path, required_space):
    stdin, stdout, stderr = ssh.exec_command(f'df -k {path}')
    stdout.channel.recv_exit_status()
    lines = stdout.readlines()

    # When the filesystem name is split over two lines, join them
    if len(lines[1].split()) < 6:
        lines[1:3] = [' '.join(lines[1:3])]

    columns = lines[1].split()
    available_space = int(columns[3]) * 1024  # Convert from KB to Bytes
    total_space = int(columns[1]) * 1024  # Convert from KB to Bytes
    percent_used_after_copy = ((total_space - available_space + required_space) / total_space) * 100

    return available_space if percent_used_after_copy < DISK_USAGE_THRESHOLD else 0


def transfer_files(ssh, files_to_transfer, server_name):
    scp = SCPClient(ssh.get_transport())
    for file in files_to_transfer:
        remote_path = os.path.dirname(file)
        ssh.exec_command(f'mkdir -p {remote_path}')  # Create directory if doesn't exist
        source_file = f"{file}"
        remote_server = f"{server_name}"
        remote_filepath = f"{remote_path}"
        if prompt_task_execution("Patch scp", source_file, remote_server, remote_filepath):
            logging.info(f"Transferring file {file} to {server_name}@{remote_path}")
            scp.put(file, remote_path)
            logging.info(f"Unzipping file {remote_path}/{os.path.basename(file)} on {server_name} at {remote_path}")
            stdin, stdout, stderr = ssh.exec_command(f'unzip -oq {remote_path}/{os.path.basename(file)} -d {remote_path}')  # Unzip file
            while not stdout.channel.exit_status_ready():  # Wait for the unzip command to complete
                delay()
        else:
            return


def prompt_task_execution(task, source_file, remote_server, remote_filepath):
    logging.info(f"=== User Confirmation for Task Execution ===")
    logging.info(f"Task Name       : {task}")
    logging.info(f"Database Server : {remote_server}")
    logging.info(f"Source File     : {source_file}")
    logging.info(f"Target Path     : {remote_filepath}")
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
        process_server_result = process_server(server, inventory_key)
        logging.info(f"Result of process_server for {server}: {process_server_result}")
        if not process_server_result:  # Handle error case
            logging.info(f"Skipping server {server_name} due to errors.")
            patch_scp_status[server_name]["status"] = "Failed"
    except Exception as e:
            logging.error(f"An error occurred while processing server {server_name}: {str(e)}")
            patch_scp_status[server_name]["status"] = "Error"


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

    for server, status in patch_scp_status.items():
        logging.info(f"Server: {server}, Start Time: {status['start_time']}, End Time: {status['end_time']}, Status: {status['status']}")

