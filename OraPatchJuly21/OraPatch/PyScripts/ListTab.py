import sqlite3
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

query = """
select
name
from
sqlite_master
where
type='table'
"""
conn = sqlite3.connect(SQLITE_DB)
cursor = conn.cursor()
cursor.execute(query)
rows = cursor.fetchall()
print(rows)

