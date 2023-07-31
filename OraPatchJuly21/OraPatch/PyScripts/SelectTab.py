import sqlite3
import sys
import pandas as pd
import yaml
import os
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


SQLITE_DB = os.path.join(config["SQLITEDB_DIR"], config["MASTER_DB"])

# Set display options.

pd.set_option('display.max_rows', None)
pd.set_option('display.max_columns', None)

def select_all_from_table(table_name):
    # Connect to database
    db = sqlite3.connect(SQLITE_DB)

    # Use pandas to execute the query and get the result.
    df = pd.read_sql_query(f"SELECT * FROM {table_name}", db)

    # Close the connection
    db.close()

    # Return the Data.
    return df

if __name__ == "__main__":
    # Get the table name from cmd.
    table_name = sys.argv[1]

    # Execute the function & print the result.
    df = select_all_from_table(table_name)
    print(df)

