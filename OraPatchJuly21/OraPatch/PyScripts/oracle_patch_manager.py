import yaml
import sys
import threading
import paramiko
import os
import sqlite3
from datetime import datetime
import pandas as pd


# python run_script.py servername1
# python run_script.py servername2

#PROMPT_MODE = True
PROMPT_MODE = False

ssh = paramiko.SSHClient()
ssh.load_system_host_keys()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())


def select_all_from_table(table_name):
    # Connect to database
    pd.set_option('display.max_rows', None)
    pd.set_option('display.max_columns', None)
    
    db = sqlite3.connect('os_db_data.db')

    # Use pandas to execute the query and get the result.
    df = pd.read_sql_query(f"SELECT * FROM {table_name}", db)

    # Close the connection
    db.close()

    # Return the Data.
    return df

def save_to_sqlite(data_rows):
        conn = sqlite3.connect('oratab_db.db')  # Creates a SQLite database file
        cursor = conn.cursor()
        cursor.execute('DROP TABLE IF EXISTS oratab_db')
        cursor.execute('''
        CREATE TABLE IF NOT EXISTS oratab_db(
            DBI_HOST TEXT,
            DBI_KEY TEXT,
            ORA_SID TEXT,
            ORA_HOME TEXT,
            AUTO_START TEXT,
            HOME_EXIST TEXT,
            HOME_ACTIVE TEXT,
            HOME_TYPE TEXT,
            SID_STATUS TEXT,
            DB_STATUS TEXT,
            SQLPLUS_VERSION TEXT,
            DB_RELEASE TEXT,
            OPATCH_VERSION TEXT,
            PATCH_HISTORY TEXT,
            LISTENER_DATA TEXT,
            OS_USER TEXT,
            PRIMARY_GROUP TEXT,
            TOTAL_GB TEXT,
            USED_GB TEXT,
            FREE_GB TEXT,
            USED_PCT TEXT,
            FREE_PCT TEXT,
            OS_NAME TEXT,
            OS_KERNEL TEXT,
            OS_SHELL TEXT,
            SERVER_CPU TEXT,
            SERVER_RAM TEXT,
            JCHEM_STATUS TEXT,
            ORAINV TEXT,
            ROWSTART TEXT,
            INSTANCE_NAME TEXT,
            HOST_NAME TEXT,
            VERSION TEXT,
            STARTUP_TIME TEXT,
            STATUS TEXT,
            LOGINS TEXT,
            DATABASE_STATUS TEXT,
            INSTANCE_ROLE TEXT,
            DBID TEXT,
            NAME TEXT,
            CREATED TEXT,
            RESETLOGS_TIME TEXT,
            LOG_MODE TEXT,
            OPEN_MODE TEXT,
            PROTECTION_MODE TEXT,
            PROTECTION_LEVEL TEXT,
            DATABASE_ROLE TEXT,
            FORCE_LOGGING TEXT,
            PLATFORM_ID TEXT,
            PLATFORM_NAME TEXT,
            FLASHBACK_ON TEXT,
            DB_UNIQUE_NAME TEXT,
            IS_DG TEXT,
            DG_TNS TEXT,
            IS_RAC TEXT,
            RAC_NODE TEXT,
            WALLET_LOCATION TEXT,
            WALLET_STATUS TEXT,
            WALLET_TYPE TEXT,
            TDE_TBSCOUNT TEXT,
            OFFLINE_DATAFILE TEXT,
            OFFLINE_TEMPFILE TEXT,
            NEED_RECOVERY TEXT,
            IS_PDB TEXT,
            PDB_LIST TEXT,
            PGA_LIMIT TEXT,
            PGA_TARGET TEXT,
            SGA_TARGET TEXT,
            SGA_MAX TEXT,
            MEMORY_MAX TEXT,
            MEMORY_TARGET TEXT,
            CPUCOUNT TEXT,
            ALLOC_PGA_MB TEXT,
            TOTAL_SGA_MB TEXT,
            TOTALSIZE TEXT,
            DATAFILESIZE TEXT,
            TEMPFILESIZE TEXT,
            SEGMENTSIZE TEXT,
            ROWEND TEXT
        )
        ''')
        for row in data_rows:
            # Construct the SQL query with appropriate placeholders for values
            print(row)
            query = "INSERT INTO oratab_db VALUES (? " + ", ?" * (len(row) - 1) + ")"
        
            # Execute the query with the row values
            cursor.execute(query, row)
        
        # Commit the changes to the database
        conn.commit()
        

def connect_to_server(server):
    """
    Connect to the specified server via SSH
    """
    try:
        ssh.connect(server, timeout=120)
    except paramiko.AuthenticationException:
        print(f"Authentication failed for {server}")
        return False
    except paramiko.SSHException as e:
        print(f"Error connecting to {server}: {str(e)}")
        return False
    except Exception as e:
        print(f"Unexpected error for {server}: {str(e)}")
        return False

    return True

def run_script(script_task, script_fqfn, src_type="local"):
    script_path, script_args = script_fqfn.split(" ",1)
    if src_type == 'local':
        run_local_script(script_task, script_path, script_args)
    elif src_type == 'remote':
        run_remote_script(script_task, script_path, script_args)
    else:
        print(f"Invalid script type: {script_args}")

def run_local_script(script_task, script_path, script_args):
    with open(script_path, 'rb') as script_file:
        script_data = script_file.read()

    stdin, stdout, stderr = ssh.exec_command(f'bash -s - {script_args}')
    stdin.write(script_data)
    stdin.flush()
    stdin.channel.shutdown_write()

    # Create threads for stdout and stderr
    create_threads(script_task, stdout, stderr)

def run_remote_script(script_task, script_path, script_args):
    stdin, stdout, stderr = ssh.exec_command(f'{script_path} {script_args}')
    create_threads(script_task, stdout, stderr)

def create_threads(script_task, stdout, stderr):
    stdout_thread = threading.Thread(target=print_output, args=(script_task, stdout,))
    stdout_thread.start()

    stderr_thread = threading.Thread(target=print_output, args=(script_task, stderr,))
    stderr_thread.start()

    stdout_thread.join()
    stderr_thread.join()

def print_output(script_task, stream):
    task_results = []
    for line in iter(stream.readline, ""):
        parse_line = line.split("::")[0]
        filter_result = line.split("::")[2]
        if parse_line == 'RESULT':
            #print(script_task)
            #print(line, end="")
            task_results.append(filter_result)
    #print(task_results)
    save_to_sqlite(task_results)
    #df = select_all_from_table(oratab_db)
    #print(df)

def prompt_task_execution(task, full_command):
    print(f"""
==================== Task Execution Prompt ====================
Task Name: {task}
Command: {full_command}

Type 'y' to execute , 'exit' to quit.
==============================================================
    """)
    while PROMPT_MODE:
        user_input = input("\nType 'y' to execute , 'exit' to quit: ").lower()
        if user_input == 'y':
            return True
        elif user_input == 'exit':
            exit()
        else:
            print("Invalid input! Please type 'y' to execute , 'exit' to quit.")

    return True  # If PROMPT_MODE is False, this will immediately return True

def load_yaml_file(yaml_path):
    try:
        with open(yaml_path, 'r') as yaml_file:
            yaml_data = yaml.safe_load(yaml_file)
        return yaml_data
    except FileNotFoundError:
        print(f"File not found: {yaml_path}")
        return None
    except yaml.YAMLError as err:
        print(f"Error parsing YAML file: {err}")
        return None

def format_arguments(task, ora_home, bkp_loc, ora_inv, opatch_zip, sid_list=None, patch_name=None, patch_home=None, db_action=None):
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
        elif arg == 'DbAction' and db_action:    # Add this line for DbAction
            formatted_arg = f'-{arg} {db_action}' # Add this line for DbAction
        else:
            formatted_arg = f'-{arg} None'
        #print(f"formatted arg: {formatted_arg}")
        arg_strs.append(formatted_arg)
    #print(f"Final formatted arg: {arg_strs}")
    return arg_strs

def create_task_info(task, arg_strs):
    script_fqfn = task['path'] + ' ' + ' '.join(arg_strs)
    return {'task_name': task['name'], 'script_fqfn': script_fqfn, 'execute': task['execute'], 'script_type': task['type']}

def process_server(server):
    # Create lock file
    lock_file = f"/tmp/{server}.lock"
    if os.path.exists(lock_file):
        print(f"Lock file exists for server {server}, another instance may be running. Exiting.")
        return
    else:
        open(lock_file, 'a').close()

    try:
        patch_tasks = load_yaml_file('/u01/home/oracle/OraPatch_Stage/Patch/config/patch_task.yaml')
        patch_homes = load_yaml_file(f'/u01/home/oracle/OraPatch_Stage/Patch/patchdb/{server}.yaml')
        global_params = patch_homes['globalparams']
        bkp_loc = global_params['BkpLoc']
        ora_inv = global_params['OraInv']
        oracle_homes = patch_homes['oraclehomes']

        for homes in oracle_homes:
            #print(f"Current Home: {homes}")
            task_info_list = []
            ora_home = homes['OraHome']
            sid_list = homes['SidList']
            #print(f"sid list: {sid_list}")
            patch_names = homes['PatchName']
            opatch_zip = homes['opatch']['OpatchZip']

            for task in patch_tasks['tasks']:
                if task['execute'] == 'Y':
                    if task['name'] == 'prereq_checkconflict' or task['name'] == 'patch_apply':
                        for patch_name, patch_details in patch_names.items():
                            if patch_details['apply'] == 'Y':
                                patch_home = patch_details['PatchHome']
                                patch_zip = patch_details['PatchZip']
                                #arg_strs = format_arguments(task, ora_home, bkp_loc, ora_inv, opatch_zip, patch_name, patch_home, sid_list)
                                #arg_strs = format_arguments(task, ora_home, bkp_loc, ora_inv, opatch_zip, sid_list, patch_name, patch_home)
                                #arg_strs = format_arguments(task, ora_home, bkp_loc,          opatch_zip, patch_name, patch_home, sid_list)
                                arg_strs = format_arguments(task, ora_home, bkp_loc, ora_inv, opatch_zip, sid_list=sid_list, patch_name=patch_name, patch_home=patch_home)
                                task_info_list.append(create_task_info(task, arg_strs))

                   # Check if the task name is one of 'db_start', 'db_stop', 'db_start_upg_mode'
                    elif task['name'] in ['db_start', 'db_stop', 'db_start_upg_mode']:
                        # Determine the db_action based on the task name
                        if task['name'] == 'db_start':
                            db_action = 'dbstart'
                        elif task['name'] == 'db_stop':
                            db_action = 'dbstop'
                        elif task['name'] == 'db_start_upg_mode':
                            db_action = 'dbstartupg'

                        # format the arguments needed for this task
                        arg_strs = format_arguments(task, ora_home, bkp_loc, ora_inv, opatch_zip, sid_list=sid_list, db_action=db_action)

                        # append this task's information to the task_info_list
                        task_info_list.append(create_task_info(task, arg_strs))
                    elif task['arguments']:
                        #arg_strs = format_arguments(task, ora_home, bkp_loc, ora_inv, opatch_zip)
                        #arg_strs = format_arguments(task, ora_home, bkp_loc, ora_inv, sid_list, opatch_zip)
                        #arg_strs = format_arguments(task, ora_home, bkp_loc,          opatch_zip)
                        arg_strs = format_arguments(task, ora_home, bkp_loc, ora_inv, opatch_zip, sid_list=sid_list)
                        #print(sid_list)
                        #print(arg_strs)
                        task_info_list.append(create_task_info(task, arg_strs))
                    else:
                        arg_strs = ''
                        task_info_list.append(create_task_info(task, arg_strs))


            print(f"For Oracle Home: {ora_home}")
            for task_info in task_info_list:
                if prompt_task_execution(task_info['task_name'], task_info['script_fqfn']):
                    # Connect to the server
                    if not connect_to_server(server):
                        print(f"Cannot connect to server: {server}")
                        return

                    task_start_time = datetime.now()  # Start time assigned here
                    print(f"""
==================== Preparing to run Task ====================
Server: {server}
Task Name: {task_info['task_name']}
Script: {task_info['script_fqfn']}
Execute: {task_info['execute']}
Script Type: {task_info['script_type']}
Start Time: [{task_start_time.strftime('%Y-%m-%d %H:%M:%S')}]
===============================================================
""")

                    # Run the script on the server
                    run_script(task_info['task_name'], task_info['script_fqfn'], task_info['script_type'])
                    task_end_time = datetime.now()
                    print(f"End Time: {task_end_time.strftime('%Y-%m-%d %H:%M:%S')}\n")

                    # Disconnect from the server
                    ssh.close()
                    print(f"Disconnected from server: {server}")
    except Exception as e:
        print(f"An error occurred: {str(e)}")
    finally:
        # Remove the lock file
        os.remove(lock_file)
        print(f"Removed the lock file.")

if __name__ == "__main__":
    server_name = sys.argv[1]
    server = server_name.split(".")[0].lower() # server name without domain in lower case.
    process_server(server)

