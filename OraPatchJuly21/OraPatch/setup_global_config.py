import os
import yaml
import shutil
from datetime import datetime

def create_global_config():
    try:
        # Get the current working directory
        base_dir = os.getcwd()

        # Define the paths
        paths = {
            "BASE_DIR": base_dir,
            "CONFIG_DIR": os.path.join(base_dir, "Config"),
            "PATCHTASK_DIR": os.path.join(base_dir, "PatchTask"),
            "PATCHDB_DIR": os.path.join(base_dir, "PatchDB"),
            "SERVERLIST_DIR": os.path.join(base_dir, "ServerList"),
            "SQLITEDB_DIR": os.path.join(base_dir, "SQLiteDB"),
            "LOCK_DIR": os.path.join(base_dir, "Lock"),
            "CSV_DIR": os.path.join(base_dir, "Csv"),
            "HTML_DIR": os.path.join(base_dir, "Html"),
            "TEMP_DIR": os.path.join(base_dir, "Temp"),
            "LOG_DIR": os.path.join(base_dir, "Logs"),
            "SHELL_DIR": os.path.join(base_dir, "ShellScripts"),
            "BACKUP_DIR": os.path.join(base_dir, "Backup"),
            "TO_RECIPIENT_EMAIL": "hemendra.singh_ext@novartis.com",
            "CC_RECIPIENT_EMAIL": "hemendra.singh_ext@novartis.com,hemendra.singh_ext@novartis.com,hemendra.singh_ext@novartis.com",
            "SENDER_EMAIL": "hemendra.singh_ext@novartis.com",
            "MASTER_DB": "orapatch_metadata_sqlite_db.db",
            "CURRENT_PATCH_CYCLE": "H1_2023",
            # add more paths as needed...
        }

        # Backup the existing global_config.yaml file
        config_dir = os.path.join(base_dir, "Config")
        backup_dir = os.path.join(base_dir, "Backup")
        if not os.path.exists(config_dir):
            os.makedirs(config_dir)
        if not os.path.exists(backup_dir):
            os.makedirs(backup_dir)

        config_file_path = os.path.join(config_dir, "global_config.yaml")
        if os.path.exists(config_file_path):
            timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
            backup_file_path = os.path.join(backup_dir, f"global_config_{timestamp}.yaml")
            shutil.copy(config_file_path, backup_file_path)

        # Write the paths to the global_config.yaml file
        with open(config_file_path, "w") as file:
            yaml.dump(paths, file, default_flow_style=False)

    except Exception as e:
        print(f"An error occurred: {str(e)}")

if __name__ == "__main__":
    create_global_config()
