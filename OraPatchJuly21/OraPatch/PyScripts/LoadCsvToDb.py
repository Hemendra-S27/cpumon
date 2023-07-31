import csv
import sqlite3
import os
import re
import sys
import yaml
import datetime


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
RECIPIENT_EMAIL = config["RECIPIENT_EMAIL"]
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
PATCH_CYCLE = config["CURRENT_PATCH_CYCLE"]

def sanitize_identifier(identifier):
    """
    Strips leading and trailing spaces, replaces non-alphanumeric characters and leading digits with underscores,
    then makes the identifier uppercase, and finally removes leading and trailing underscores.
    """
    identifier = identifier.strip()  # Strip leading and trailing spaces
    identifier = re.sub('\W|^(?=\d)', '_', identifier)  # Replace non-alphanumeric characters and leading digits with underscores
    identifier = identifier.upper()  # Make the identifier uppercase
    identifier = identifier.strip('_')  # Strip leading and trailing underscores
    return identifier


def create_table_from_csv(csv_file, db_file):
    """
    Reads a CSV file and creates a corresponding SQLite database table.
    If the table already exists, it's dropped and a new one is created.
    """

    # Check that the input file is a CSV file
    if not csv_file.lower().endswith('.csv'):
        raise ValueError(f'Invalid file format: {csv_file}. A CSV file is expected.')

    # Extract table name from CSV file name (excluding file extension)
    table_name = os.path.splitext(os.path.basename(csv_file))[0]
    table_name = sanitize_identifier(table_name)

    # Read CSV file and get headers
    with open(csv_file, 'r') as file:
        csv_reader = csv.reader(file)
        headers = next(csv_reader)

    # Sanitize column names
    headers = [sanitize_identifier(header) for header in headers]

    # Create SQLite connection and cursor
    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()

    # Drop the table if it already exists
    drop_table_query = f'DROP TABLE IF EXISTS "{table_name}"'
    cursor.execute(drop_table_query)
    conn.commit()

    # Create table
    columns = ', '.join([f'"{header}" TEXT' for header in headers])
    create_table_query = f'CREATE TABLE IF NOT EXISTS "{table_name}" ({columns})'
    cursor.execute(create_table_query)
    conn.commit()

    # Insert data into table
    with open(csv_file, 'r') as file:
        csv_reader = csv.reader(file)
        # Skip headers
        next(csv_reader)

        insert_query = f'INSERT INTO "{table_name}" VALUES ({",".join(["?"] * len(headers))})'
        cursor.executemany(insert_query, csv_reader)
        conn.commit()

    # Get the count of rows loaded
    cursor.execute(f'SELECT COUNT(*) FROM "{table_name}"')
    rows_loaded = cursor.fetchone()[0]

    # Close connection
    conn.close()

    # Print the table name, column names, and the number of rows loaded
    print(f"Table '{table_name}' created with columns {headers}.")
    print(f"Number of rows loaded: {rows_loaded}")


if __name__ == "__main__":
    # The script expects the CSV file as a command line argument
    if len(sys.argv) != 2:
        print("Please provide a CSV file as a command line argument.")
        sys.exit(1)
    else:
        csv_file = sys.argv[1]
        
        # Check if the file exists. If not, try to find it in the current directory.
        if not os.path.isfile(csv_file):
            csv_file = os.path.join(os.getcwd(), csv_file)
            if not os.path.isfile(csv_file):
                print(f"File {csv_file} does not exist.")
                sys.exit(1)
                
                
        try:
            create_table_from_csv(csv_file, SQLITE_DB)
        except Exception as e:
            print(f"An error occurred: {str(e)}")
            sys.exit(1)
