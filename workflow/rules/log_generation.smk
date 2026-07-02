# rules/log_generation.smk

# Load packages
#from datetime import datetime
 
#Create timestamp for log file
#if "LOGTIMESTAMP" not in globals():
#    LOGTIMESTAMP = datetime.now().strftime("%Y_%m_%dT%H%M")

#LOGTIMESTAMP = datetime.now().strftime("%Y_%m_%dT%H%M")
#LOGFILE = f"{OUTPUT_DIR}/logs/logfile_{LOGTIMESTAMP}.txt"

from datetime import datetime
import uuid
import os
import json

RUN_ID_FILE = ".snakemake/run_id.json"

if os.path.exists(RUN_ID_FILE):
    with open(RUN_ID_FILE) as f:
        RUN_ID = json.load(f)["run_id"]
else:
    RUN_ID = datetime.now().strftime("%Y_%m_%d_T%H%M%S") + "_" + uuid.uuid4().hex[:8]
    os.makedirs(os.path.dirname(RUN_ID_FILE), exist_ok=True)
    with open(RUN_ID_FILE, "w") as f:
        json.dump({"run_id": RUN_ID}, f)

config["run_id"] = RUN_ID


RUN_ID = config["run_id"]
LOGFILE = f"{OUTPUT_DIR}/logs/logfile_{RUN_ID}.txt"

all_inputs.append(LOGFILE)

rule create_log:
    output:
        logfile = LOGFILE
    run:
        import subprocess
        from datetime import datetime
        import socket
        import sys
        import snakemake
        import yaml
        import os
        from pathlib import Path

        log_path = output.logfile
        os.makedirs(os.path.dirname(log_path), exist_ok=True)        

        def get_git_info(cmd, default="NA"):
            """Helper to run git commands safely."""
            try:
                return subprocess.check_output(cmd, shell=True, text=True).strip()
            except subprocess.CalledProcessError:
                return default

        # Collect system info
        run_id = RUN_ID
        hostname = socket.gethostname()
        datetime_now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        # Collect Git info
        git_version = get_git_info("git describe --tags --abbrev=0")
        git_commit = get_git_info("git rev-parse HEAD")
        git_branch = get_git_info("git rev-parse --abbrev-ref HEAD")
        git_remote = get_git_info("git config --get remote.origin.url")

        # Collect environment info
        python_version = sys.version.split()[0]  # e.g. "3.10.14"
        snakemake_version = snakemake.__version__


        with open(log_path, "w") as f:
            f.write("================ Pipeline Execution Log ================\n")
            f.write(f"Unique Run ID: {run_id}\n")
            f.write(f"Date & Time: {datetime_now}\n")
            f.write(f"Executed on Server: {hostname}\n\n")
            
            f.write("--------------- SOFTWARE ENVIRONMENT -------------------\n")
            f.write(f"Snakemake version: {snakemake_version}\n")
            f.write(f"Python version: {python_version}\n\n")

            f.write("--------------- GIT REPOSITORY INFO --------------------\n")
            f.write(f"ECHO version: {git_version}\n")
            f.write(f"ECHO git commit Hash: {git_commit}\n")
            f.write(f"ECHO git branch: {git_branch}\n")
            f.write(f"ECHO github remote URL: {git_remote}\n\n")

            f.write("--------------- CONFIGURATION PARAMETERS ---------------\n")
            f.write(f"SAMPLES: {SAMPLES}\n")
            f.write(f"START_FROM: {START_FROM}\n")
            f.write(f"OUTPUT_DIR: {OUTPUT_DIR}\n")
            f.write(f"REFERENCE: {REFERENCE}\n")
            f.write(f"REFERENCE_TE: {REFERENCE_TE}\n")
            f.write(f"TR_CATALOG: {TR_CATALOG}\n")
            f.write(f"TE_CATALOG: {TE_CATALOG}\n")
            f.write(f"FLANKING_LENGTH_BP: {FLANKING_LENGTH_BP}\n")
            f.write(f"CONSENSUS_EXTENSION: {CONSENSUS_EXTENSION}\n")
            f.write(f"TYPE_OF_TE: {TYPE_OF_TE}\n")
            f.write(f"TYPE_OF_TR: {TYPE_OF_TR}\n")
    
