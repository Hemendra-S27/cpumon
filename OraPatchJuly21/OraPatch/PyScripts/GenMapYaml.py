import sqlite3
import yaml
import os
import datetime
import sys
import argparse
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s :: %(levelname)s :: %(message)s', datefmt='%Y-%m-%d %H:%M:%S')

START_TIME = datetime.datetime.now()
TIMESTAMP_TAG = datetime.datetime.now().strftime("_%Y%m%d%H%M%S")

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
TO_RECIPIENT = config["TO_RECIPIENT_EMAIL"]
CC_RECIPIENT = config["CC_RECIPIENT_EMAIL"]

def create_conn():
    """Function to create a database connection."""
    conn = sqlite3.connect(SQLITE_DB)
    return conn

def close_conn(conn):
    """Function to close a database connection."""
    if conn:
        conn.close()

def generate_oraclehome_dict(row):
    """Function to generate the dictionary for an Oracle home."""
    return {
        'OraHome': row[1],
        'SidList': row[2],
        'parameters': {
            'db_release': row[3],
            'home_active': row[4],
            'home_exist': row[5],
            'home_type': row[6],
            'need_to_patch': row[7],
            'opatch_version': row[8],
            'os_name': row[9],
            'os_release': row[10],
            'sqlplus_version': row[11]
        },
        'PatchName': {
            'psu': {
                'apply': row[12],
                'PatchHome': row[13],
                'PatchZip': row[14],
            },
            'jdk': {
                'apply': row[15],
                'PatchHome': row[16],
                'PatchZip': row[17],
            },
            'ojvm': {
                'apply': row[18],
                'PatchHome': row[19],
                'PatchZip': row[20],
            },
            'perl': {
                'apply': row[21],
                'PatchHome': row[22],
                'PatchZip': row[23],
            }
        },
        'opatch': {
            'OpatchZip': row[24],
        }
    }

def write_yaml(server_data, inventory_key_directory, server):
    server_filename = f'{server.split(".")[0].lower()}.yaml'
    file_path = os.path.join(inventory_key_directory, server_filename)
    with open(file_path, 'w') as file:
        yaml.dump(server_data, file, default_flow_style=False, sort_keys=False)
        logging.info(f"Patch config YAML {file_path} created for {server}")
        
def main(inventory_key):
    # Ensure all string values are output in quotes
    yaml.add_representer(str, lambda dumper, data: dumper.represent_scalar('tag:yaml.org,2002:str', data, style='"'))

    # Create directory outside of the loop
    inventory_key_directory = os.path.join(PATCHDB_YAML, inventory_key)
    os.makedirs(inventory_key_directory, exist_ok=True)
    
    conn = create_conn()
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT * FROM PATCH_MAP")
        rows = cursor.fetchall()

        previous_server = None
        ora_home_list = []
        server_data = {}

        for row in rows:
            if row[0] == previous_server:
                ora_home_list.append(generate_oraclehome_dict(row))
            else:
                if server_data:
                    write_yaml(server_data, inventory_key_directory, previous_server)

                cursor.execute("SELECT DISTINCT ORAINV FROM TAB_CREATEINVENTORY WHERE DBI_HOST = ? and INVENTORYKEY = ?", (row[0], inventory_key))
                ora_inv_rows = cursor.fetchall()
                ora_inv = ora_inv_rows[0][0] if ora_inv_rows else None

                server_data = {
                    'globalparams': {
                        'InventoryKey': inventory_key, 
                        'BkpLoc': BKP_LOC,
                        'OraInv': ora_inv
                    },
                    'oraclehomes': []
                }
                ora_home_list = server_data['oraclehomes']
                ora_home_list.append(generate_oraclehome_dict(row))

            previous_server = row[0]

        if server_data:
            write_yaml(server_data, inventory_key_directory, previous_server)
    except Exception as e:
        logging.error(f"Patch config YAML creation failed. An error occurred: {str(e)}")
    finally:
        close_conn(conn)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('inventory_key', help='Inventory key to use in the SQL query')
    args = parser.parse_args()

    main(args.inventory_key)
