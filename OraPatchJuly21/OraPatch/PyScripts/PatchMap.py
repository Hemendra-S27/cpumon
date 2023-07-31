import argparse
import concurrent.futures
import csv
import datetime
import html
import os
import smtplib
import socket
import sqlite3
import subprocess
import sys
from collections import OrderedDict
from email import encoders
from email.mime.base import MIMEBase
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import pandas as pd
import paramiko
import yaml
from jinja2 import Environment, FileSystemLoader
COMMASPACE = ', '

start_time = datetime.datetime.now()
timestamp_tag = datetime.datetime.now().strftime("_%Y%m%d%H%M%S")

def load_config():
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
DB_INVENTORY = os.path.join(config["CSV_DIR"], f"db_inventory{timestamp_tag}.csv")
DB_PATCH_MAP_INVENTORY = os.path.join(config["CSV_DIR"], f"db_patch_map_inventory{timestamp_tag}.csv")
EXECUTION_SUMMARY = os.path.join(config["CSV_DIR"], f"db_inventory_execution_summary{timestamp_tag}.csv")
PATCH_CYCLE = config["CURRENT_PATCH_CYCLE"]
TO_RECIPIENT = config["TO_RECIPIENT_EMAIL"]
CC_RECIPIENT = config["CC_RECIPIENT_EMAIL"]

"""
QUERY
"""

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

def execute_sql_query(query, table_name, db=SQLITE_DB):
    try:
        with sqlite3.connect(db) as conn:
            cursor = conn.cursor()
            cursor.execute(query)
            df = pd.read_sql_query(query, conn)
            cursor.execute(f'DROP TABLE IF EXISTS {table_name}')
            df.to_sql(table_name, conn, if_exists='replace', index=False)
    except sqlite3.Error as error:
        print("An error occurred:", error.args[0])
    finally:
        if conn:
            conn.close()  # Ensure the connection is closed even if an error occurred

def load_data_into_tables(inventory_key):
    # Load data into tables
    execute_sql_query(query_1, 'PATCH_MAP_STAGE')
    execute_sql_query(query_2, 'PATCH_MAP')

def load_data_to_csv_and_send_email():
    try:
        with open(DB_PATCH_MAP_INVENTORY, 'w', newline='') as csv_file:
            writer = csv.writer(csv_file)
            conn = sqlite3.connect(SQLITE_DB)
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM PATCH_MAP")
            rows = cursor.fetchall()

            # Write headers
            writer.writerow([description[0] for description in cursor.description])

            # Write rows
            writer.writerows(rows)
    except sqlite3.Error as error:
        print("An error occurred:", error.args[0])
    finally:
        if conn:
            conn.close()  # Ensure the connection is closed even if an error occurred

        # Send email with the attached reports (CSV file and execution_summary.csv)
        end_datetime_tmp = datetime.datetime.now()
        template_vars = {
            'recipient_email': TO_RECIPIENT,
            'program_name': __file__,
            'host_server': socket.gethostname(),
            'start_datetime': start_time.strftime('%Y-%m-%d %H:%M:%S'),
            'end_datetime': end_datetime_tmp.strftime('%Y-%m-%d %H:%M:%S')
        }

        # Render the email body from the template
        env = Environment(loader=FileSystemLoader(MAIL_TEMPLATE_DIR))
        template = env.get_template(MAIL_TEMPLATE_FILE)
        email_body = template.render(template_vars)

        MAIL_SUBJECT = f"Oracle-db-patch-map"
        send_email(
            TO_RECIPIENT,
            MAIL_SUBJECT,
            email_body,  # pass the rendered HTML string here
            [DB_PATCH_MAP_INVENTORY],
            [CC_RECIPIENT]
        )


def create_patch_map(inventory_key):
    load_data_into_tables(inventory_key)
    load_data_to_csv_and_send_email()


if __name__ == "__main__":
    # use argparse to handle command line arguments
    parser = argparse.ArgumentParser(description='Create patch map.')
    parser.add_argument('inventory_key', type=str, help='Inventory Key')
    args = parser.parse_args()

    inventory_key = args.inventory_key

    query_1 = f"""
    WITH DB_Data_With_Release AS (
        SELECT
            DBI_HOST AS SERVERNAME,
            DBI_KEY,
            ORA_SID AS SID,
            ORA_HOME AS ORACLE_HOME,
            AUTO_START,
            HOME_EXIST,
            HOME_ACTIVE,
            HOME_TYPE,
            SID_STATUS,
            DB_STATUS,
            SQLPLUS_VERSION,
            OPATCH_VERSION,
            OS_NAME,
            CASE
                WHEN OS_NAME = 'Linux' THEN 'RedHat'
                ELSE 'notsupported'
            END AS OS_RELEASE,
            VERSION,
            DB_RELEASE
        FROM
            TAB_CREATEINVENTORY WHERE INVENTORYKEY = '{inventory_key}'
    )
    SELECT
        ddr.SERVERNAME,
        ddr.DBI_KEY,
        ddr.SID,
        ddr.ORACLE_HOME,
        ddr.AUTO_START,
        ddr.HOME_EXIST,
        ddr.HOME_ACTIVE,
        ddr.HOME_TYPE,
        ddr.SID_STATUS,
        ddr.DB_STATUS,
        ddr.SQLPLUS_VERSION,
        ddr.OPATCH_VERSION,
        ddr.OS_NAME,
        ddr.OS_RELEASE,
        ddr.VERSION,
        ddr.DB_RELEASE,
        CASE
            WHEN pcm.PSU = 'Y' OR pcm.JDK = 'Y' OR pcm.OJVM = 'Y' OR pcm.PERL = 'Y' THEN 'Y'
            ELSE 'N'
        END AS NEED_TO_PATCH,
        GROUP_CONCAT(pcm.PSU) AS PSU,
        GROUP_CONCAT(
            CASE
                WHEN pcm.PSU = 'Y' AND PZ.PRODUCT='RDBMS'
                THEN pz.BASE_DIR || pz.BASE_SUB_DIR || '/' || pz.OS_NAME || '/' || pz.DB_RELEASE || '/' || pz.PATCH_CYCLE || '/' || pz.PATCH_HOME_DIR || '/' || pz.PATCH_FILE
                ELSE NULL
            END
        ) AS PSU_ZIP_PATH,
        GROUP_CONCAT(
            CASE
                WHEN pcm.PSU = 'Y' AND PZ.PRODUCT='RDBMS'
                THEN pz.BASE_DIR || pz.BASE_SUB_DIR || '/' || pz.OS_NAME || '/' || pz.DB_RELEASE || '/' || pz.PATCH_CYCLE || '/' || pz.PATCH_HOME_DIR || '/' || pz.PATCH_NUMBER
                ELSE NULL
            END
        ) AS PSU_UNZIP_PATH,
        GROUP_CONCAT(pcm.JDK) AS JDK,
        GROUP_CONCAT(
            CASE
                WHEN pcm.JDK = 'Y' AND PZ.PRODUCT='JDK'
                THEN pz.BASE_DIR || pz.BASE_SUB_DIR || '/' || pz.OS_NAME || '/' || pz.DB_RELEASE || '/' || pz.PATCH_CYCLE || '/' || pz.PATCH_HOME_DIR || '/' || pz.PATCH_FILE
                ELSE NULL
            END
        ) AS JDK_ZIP_PATH,
        GROUP_CONCAT(
            CASE
                WHEN pcm.JDK = 'Y' AND PZ.PRODUCT='JDK'
                THEN pz.BASE_DIR || pz.BASE_SUB_DIR || '/' || pz.OS_NAME || '/' || pz.DB_RELEASE || '/' || pz.PATCH_CYCLE || '/' || pz.PATCH_HOME_DIR || '/' || pz.PATCH_NUMBER
                ELSE NULL
            END
        ) AS JDK_UNZIP_PATH,
        GROUP_CONCAT(pcm.OJVM) AS OJVM,
        GROUP_CONCAT(
            CASE
                WHEN pcm.OJVM = 'Y' AND PZ.PRODUCT='OJVM'
                THEN pz.BASE_DIR || pz.BASE_SUB_DIR || '/' || pz.OS_NAME || '/' || pz.DB_RELEASE || '/' || pz.PATCH_CYCLE || '/' || pz.PATCH_HOME_DIR || '/' || pz.PATCH_FILE
                ELSE NULL
            END
        ) AS OJVM_ZIP_PATH,
        GROUP_CONCAT(
            CASE
                WHEN pcm.OJVM = 'Y' AND PZ.PRODUCT='OJVM'
                THEN pz.BASE_DIR || pz.BASE_SUB_DIR || '/' || pz.OS_NAME || '/' || pz.DB_RELEASE || '/' || pz.PATCH_CYCLE || '/' || '/' || pz.PATCH_HOME_DIR || '/' || pz.PATCH_NUMBER
                ELSE NULL
            END
        ) AS OJVM_UNZIP_PATH,
        GROUP_CONCAT(pcm.PERL) AS PERL,
        GROUP_CONCAT(
            CASE
                WHEN pcm.PERL = 'Y' AND PZ.PRODUCT='PERL'
                THEN pz.BASE_DIR || pz.BASE_SUB_DIR || '/' || pz.OS_NAME || '/' || pz.DB_RELEASE || '/' || pz.PATCH_CYCLE || '/' || pz.PATCH_HOME_DIR || '/' || pz.PATCH_FILE
                ELSE NULL
            END
        ) AS PERL_ZIP_PATH,
        GROUP_CONCAT(
            CASE
                WHEN pcm.PERL = 'Y' AND PZ.PRODUCT='PERL'
                THEN pz.BASE_DIR || pz.BASE_SUB_DIR || '/' || pz.OS_NAME || '/' || pz.DB_RELEASE || '/' || pz.PATCH_CYCLE || '/' || '/' || pz.PATCH_HOME_DIR || '/' || pz.PATCH_NUMBER
                ELSE NULL
            END
        ) AS PERL_UNZIP_PATH
    FROM
        DB_Data_With_Release ddr
    JOIN
        PATCH_ZIP pz
    ON
        ddr.DB_RELEASE = pz.DB_RELEASE
    AND
        ddr.OS_RELEASE = pz.OS_NAME
    JOIN
        PATCH_COMPATABILITY_MATRIX pcm
    ON
        ddr.DB_RELEASE = pcm.VERSION
    AND pz.PATCH_CYCLE='{PATCH_CYCLE}'
    AND pcm.PATCH_CYCLE='{PATCH_CYCLE}'
    AND pz.OS_NAME = pcm.PLATFORM
    GROUP BY
        ddr.SERVERNAME,
        ddr.DBI_KEY,
        ddr.SID
    """

    query_2 = f"""
    SELECT
        SERVERNAME,
        ORACLE_HOME,
        GROUP_CONCAT(SID) as SID,
        DB_RELEASE,
        HOME_ACTIVE,
        HOME_EXIST,
        HOME_TYPE,
        NEED_TO_PATCH,
        OPATCH_VERSION,
        OS_NAME,
        OS_RELEASE,
        SQLPLUS_VERSION,
        SUBSTRING(PSU, 1, 1) AS PSU,
        PSU_UNZIP_PATH,
        PSU_ZIP_PATH,
        SUBSTRING(JDK, 1, 1) AS JDK,
        JDK_UNZIP_PATH,
        JDK_ZIP_PATH,
        SUBSTRING(OJVM, 1, 1) AS OJVM,
        OJVM_UNZIP_PATH,
        OJVM_ZIP_PATH,
        SUBSTRING(PERL, 1, 1) AS PERL,
        PERL_UNZIP_PATH,
        PERL_ZIP_PATH,
    substr(PSU_ZIP_PATH, 1, instr(PSU_ZIP_PATH, 'patching/') + 8) || OS_RELEASE || '/' || DB_RELEASE || '/{PATCH_CYCLE}/opatch/opatch.zip' AS OPATCH_ZIP_PATH
    FROM
        PATCH_MAP_STAGE
    GROUP BY
        SERVERNAME, ORACLE_HOME;
    """

    try:
        create_patch_map(inventory_key)
    except Exception as e:
        print(f"An error occurred: {str(e)}")
        sys.exit(1)

