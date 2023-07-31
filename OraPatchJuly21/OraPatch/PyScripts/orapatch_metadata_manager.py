import os
import csv
import sys
import html
import yaml
import sqlite3
import smtplib
import datetime
import subprocess
import socket
import concurrent.futures
from jinja2 import Environment, FileSystemLoader
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders
import paramiko

COMMASPACE = ', '

# Define a default inventory key at the module level
inventory_key = None

def get_yaml_location():
    # Get the absolute path of the current script
    script_location = os.path.abspath(__file__)

    # Get the parent directory of the current script
    parent_directory = os.path.dirname(script_location)

    # Get the base directory
    base_directory = os.path.dirname(parent_directory)

    # Construct the path to the YAML file
    yaml_file_location = os.path.join(base_directory, "Config", "global_config.yaml")

    return yaml_file_location

global_config = get_yaml_location()

# Define the recipient email and the path to script & lockfile as variables
# Read configuration from YAML file
timestamp_tag = datetime.datetime.now().strftime("_%Y%m%d%H%M%S")

with open(global_config, "r") as f:
    config = yaml.safe_load(f)

PROGRAM_NAME = os.path.splitext(os.path.basename(__file__))[0]
SENDER_EMAIL = config["SENDER_EMAIL"]
SQLITE_DB = os.path.join(config["SQLITEDB_DIR"], config["MASTER_DB"])
SCRIPT_FQFN = os.path.join(config["SHELL_DIR"], "db_inventory.sh")
MAIL_TEMPLATE_DIR = config["HTML_DIR"]
MAIL_TEMPLATE_FILE = "db_inventory_mail_template.html"
MAIL_BODY = os.path.join(config["HTML_DIR"], "db_inventory_mail_body.html")
LOCKFILE = os.path.join(config["LOCK_DIR"], f"{PROGRAM_NAME}.lck")
SERVER_LIST = os.path.join(config["SERVERLIST_DIR"], "database_server_list.lst")
DB_INVENTORY = os.path.join(config["CSV_DIR"], f"db_inventory{timestamp_tag}.csv")
EXECUTION_SUMMARY = os.path.join(config["CSV_DIR"], f"db_inventory_execution_summary{timestamp_tag}.csv")
TO_RECIPIENT = config["TO_RECIPIENT_EMAIL"]
CC_RECIPIENT = config["CC_RECIPIENT_EMAIL"]

# rest of the code remains the same

def send_email(to, subject, html_content, files=[], cc=None):
    if cc is None:
        cc = []

    # Replace with your own email address
    sender = SENDER_EMAIL

    # Create a MIMEMultipart object
    msg = MIMEMultipart()

    # Set the sender, recipient, and subject of the email
    msg["From"] = sender
    msg["To"] = COMMASPACE.join([to])
    msg["CC"] = COMMASPACE.join(cc)
    msg["Subject"] = subject

    # Attach the body content as HTML
    msg.attach(MIMEText(html_content, 'html'))

    # Attach files as attachments, if any
    for file in files:
        with open(file, "rb") as f:
            part = MIMEBase("application", "octet-stream")
            part.set_payload(f.read())
        encoders.encode_base64(part)
        part.add_header("Content-Disposition", f"attachment; filename={os.path.basename(file)}")
        msg.attach(part)

    # Create an SMTP object and send the email
    try:
        smtp = smtplib.SMTP("localhost")
        smtp.sendmail(sender, [to] + cc, msg.as_string())
    except smtplib.SMTPException as e:
        print("Error: unable to send email due to SMTPException")
        print(e)
    finally:
        smtp.close()

def check_ssh(server):
    print(f"INFO :: {datetime.datetime.now():%Y-%m-%d %H:%M:%S} :: Verifying SSH connectivity for {server}")
    try:
        # Initialize the SSH client
        client = paramiko.SSHClient()
        # Load known host keys
        client.set_missing_host_key_policy(paramiko.WarningPolicy())
        client.load_system_host_keys()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        # Connect to the server
        client.connect(hostname=server, timeout=120)
    except (paramiko.AuthenticationException,
            paramiko.SSHException,
            paramiko.BadHostKeyException,
            Exception) as e:
        print(e)
        return False
    else:
        # If the connection is successful
        client.close()
        return True

def run_script_over_ssh(server, script_path):
    start_time = datetime.datetime.now()
    print(f"INFO :: {datetime.datetime.now():%Y-%m-%d %H:%M:%S} :: Executing script {SCRIPT_FQFN} on {server}")

    try:
        ssh = paramiko.SSHClient()
        #ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        # Load known host keys
        ssh.load_system_host_keys()
        ssh.connect(server, timeout=120)

        with open(script_path, 'rb') as script_file:
            script_data = script_file.read()

        stdin, stdout, stderr = ssh.exec_command('bash -s', timeout=120)
        #stdin, stdout, stderr = ssh.exec_command('bash -s', timeout=2)
        stdin.write(script_data)
        stdin.flush()
        stdin.channel.shutdown_write()

        output, error = stdout.read().decode(), stderr.read().decode()
        returncode = stdout.channel.recv_exit_status()

        ssh.close()

        end_time = datetime.datetime.now()

        if returncode == 0:
            output_lines = [line.split('|') for line in output.splitlines()]
            return server, True, "Shell Script Execution Successful", start_time, end_time, output_lines
        else:
            error_message = "Shell Script Execution Unsuccessful: " + error.strip()
            return server, False, error_message, start_time, end_time, []

    except Exception as e:
        end_time = datetime.datetime.now()
        error_message = "Shell Script Execution Unsuccessful: " + str(e)
        return server, False, error_message, start_time, end_time, []


def save_to_sqlite(conn, cursor, server, data_rows, mode):
    # Define table name based on the mode
    table_name = f"TAB_{mode.upper()}"

    # Loop through each row in data_rows
    for row in data_rows:
        # Add the new InventoryKey to the row if mode is CreateInventory
        if mode == 'CreateInventory':
            row = [inventory_key] + row

        # Construct the SQL query with appropriate placeholders for values
        query = f"INSERT INTO {table_name} VALUES (? " + ", ?" * (len(row) - 1) + ")"

        # Execute the query with the row values
        cursor.execute(query, row)

    # Commit the changes to the database
    conn.commit()


def save_results_to_sqlite(conn, cursor, results):
    # Executing multiple SQL statements
    cursor.executemany(
        '''
        INSERT INTO execution_results
        (server, status, message, start_time, end_time)
        VALUES (?, ?, ?, ?, ?)
        ''',
        [
            (
                result['server'],
                result['status'],
                result['message'],
                result['start_time'],
                result['end_time']
            )
            for result in results
        ]
    )
    # Committing the changes to the database
    conn.commit()

def main(mode):
    if os.path.exists(LOCKFILE):
        print("Another instance of this script is already running. Exiting.")
        sys.exit(1)

    try:
        open(LOCKFILE, 'a').close()
        with open(SERVER_LIST, "r") as f:
            servers = f.read().splitlines()

        script_path = SCRIPT_FQFN

        results = []

        #ssh_results = {server: check_ssh(server) for server in servers}

        conn = sqlite3.connect(SQLITE_DB)  # Creates a SQLite database file
        cursor = conn.cursor()

        # Define table name based on the mode
        table_name = f"TAB_{mode.upper()}"

        # For PrePatch and PostPatch modes, drop the table if it exists
        if mode in ['PrePatch', 'PostPatch']:
            cursor.execute(f'DROP TABLE IF EXISTS {table_name}')

        # Define table structure based on the mode
        if mode == 'CreateInventory':
            cursor.execute(f'''
            CREATE TABLE IF NOT EXISTS {table_name}(
            INVENTORYKEY TEXT,
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
            PATCH_DATE TEXT,
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
        else:
            cursor.execute(f'''
            CREATE TABLE {table_name}(
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
            PATCH_DATE TEXT,
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
        # Truncate table if it exists and create table
        cursor.execute('DROP TABLE IF EXISTS execution_results')
        cursor.execute('''
            CREATE TABLE execution_results(
            server TEXT,
            status TEXT,
            message TEXT,
            start_time TEXT,
            end_time TEXT
            )
        ''')
        conn.commit()

        # Initialize a ThreadPoolExecutor with a maximum of 5 workers
        # This allows us to run multiple tasks concurrently
        # Generate a new InventoryKey if mode is CreateInventory
        global inventory_key
        if mode == 'CreateInventory':
            inventory_key = 'INVKEY' + datetime.datetime.now().strftime('%Y%m%d%H%M%S')

        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            # Create a dictionary to store server and its corresponding check_ssh Future object
            ssh_futures = {server: executor.submit(check_ssh, server) for server in servers}

            # Dictionary to store server and its corresponding run_script_over_ssh Future object
            script_futures = {}

            ssh_results = {server: ssh_future.result() for server, ssh_future in ssh_futures.items()}
            for server, ssh_future in ssh_futures.items():
                for completed_future in concurrent.futures.as_completed(ssh_futures.values()):
                    if ssh_future == completed_future:
                        break
                is_ssh_success = ssh_future.result()
                if is_ssh_success:
                    script_futures[server] = executor.submit(run_script_over_ssh, server, script_path)
                else:
                    results.append({
                        "server": server,
                        "status": False,
                        "message": "SSH connection failed",
                        "start_time": datetime.datetime.now(),
                        "end_time": datetime.datetime.now()
                    })

            # Loop through each Future object as they complete
            for server, script_future in script_futures.items():
                for completed_future in concurrent.futures.as_completed(script_futures.values()):
                    if script_future == completed_future:
                        break
                server, status, message, start_time, end_time, output = script_future.result()

                # Append the result to the 'results' list
                results.append({
                    "server": server,
                    "status": status,
                    "message": message,
                    "start_time": start_time,
                    "end_time": end_time
                })

                # If the script execution was successful (status is True), save the output to a SQLite database
                if status:
                    data_rows = [[server] + row for row in output]
                    save_to_sqlite(conn, cursor, server, data_rows, mode)  # pass mode as an argument

        # Loop through each item in ssh_results again
        for server, is_ssh_success in ssh_results.items():

            # If the SSH connection was unsuccessful (is_ssh_success is False), add a record to the 'results' list indicating this
            if not is_ssh_success:
                results.append({
                    "server": server,
                    "status": False,
                    "message": "SSH connection failed",
                    "start_time": datetime.datetime.now(),
                    "end_time": datetime.datetime.now()
                })

        # Save the execution results to a SQLite database
        save_results_to_sqlite(conn, cursor, results)

        # Export data from SQLite to CSV (patch_os_db_data)
        # Define table name and CSV file name based on the mode
        table_name = f"TAB_{mode.upper()}"
        CSV_FILE_PATH = os.path.join(config["CSV_DIR"], f"{table_name}{timestamp_tag}.csv")

        # Export data from SQLite to CSV
        if mode == "CreateInventory":
            # In CreateInventory mode, select only rows with the current inventory key
            cursor.execute(f"SELECT * FROM {table_name} WHERE INVENTORYKEY = '{inventory_key}'")
        else:
            cursor.execute(f"SELECT * FROM {table_name}")

        rows = cursor.fetchall()

        with open(CSV_FILE_PATH, 'w', newline='') as csv_file:
            writer = csv.writer(csv_file)

            # Write headers
            writer.writerow([description[0] for description in cursor.description])

            # Write rows
            writer.writerows(rows)

        # Export data from execution_results to CSV
        cursor.execute("SELECT * FROM execution_results")
        rows = cursor.fetchall()

        with open(EXECUTION_SUMMARY, 'w', newline='') as csv_file:
            writer = csv.writer(csv_file)

            # Write headers
            writer.writerow([description[0] for description in cursor.description])

            # Write rows
            writer.writerows(rows)

        # Send email with the attached reports (CSV file and execution_summary.csv)
        end_datetime_tmp = datetime.datetime.now()
        template_vars = {
            'recipient_email': TO_RECIPIENT,
            'program_name': __file__,
            'host_server': socket.gethostname(),
            'program_mode': mode,
            'number_of_servers': len(servers),
            'start_datetime': start_time.strftime('%Y-%m-%d %H:%M:%S'),
            'end_datetime': end_datetime_tmp.strftime('%Y-%m-%d %H:%M:%S'),
            'script_name': __file__,
            'script_path': __file__,
            'results': results
        }

        # Render the email body from the template
        env = Environment(loader=FileSystemLoader(MAIL_TEMPLATE_DIR))
        template = env.get_template(MAIL_TEMPLATE_FILE)
        email_body = template.render(template_vars)

        #def send_email(to, subject, template_name, template_vars, files=[]):
        MAIL_SUBJECT = f"Oracle-{mode}-Info"
        send_email(
            TO_RECIPIENT,
            MAIL_SUBJECT,
            email_body,  # pass the rendered HTML string here
            [CSV_FILE_PATH, EXECUTION_SUMMARY],
            [CC_RECIPIENT]
        )

    # Remove the lockfile
    finally:
        os.remove(LOCKFILE)

if __name__ == "__main__":
    # get the mode from command line arguments
    mode = sys.argv[1] if len(sys.argv) > 1 else None

    # check the mode and raise an exception if it's not valid
    if mode not in ['PrePatch', 'PostPatch', 'CreateInventory']:
        raise ValueError('Invalid mode. The mode should be one of "PrePatch", "PostPatch", or "CreateInventory"')

    main(mode)

