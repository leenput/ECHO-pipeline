# rules/setup_and_targets.smk

configfile: "config.yaml"

# Config Params
SAMPLES = config["samples"]
START_FROM = config.get("start_from", "pod5")
RESUME_FROM_PHASED = bool(
    config.get("resume_from_phased", False)
)
OUTPUT_DIR = config["output_dir"]
INPUT_DIR = config["input_dir"]
REFERENCE = config["reference"]
REFERENCE_NAME = config["reference_name"]
REFERENCE_TE = config["reference_TE"]
MIN_READ_QUAL = config["fastq_filtering"]["min_read_quality"]
MIN_READ_LENGTH = config["fastq_filtering"]["min_read_length"]
TR_CATALOG = config["tr_catalog"]
TE_CATALOG = config["te_catalog"]
FLANKING_LENGTH_BP = config["flanking_length_bp"]
CONSENSUS_EXTENSION = config["extension_repeat_consensus"]
TYPE_OF_TE = config["type_of_te"]
TYPE_OF_TR = config["type_of_tr"]
CATALOGS=["upstream", "downstream", "full"]
TR_METH = config.get("tr_methylation", {}) or {}
FILTER_TO_CPG_STR = bool(TR_METH.get("filter_to_cpg_str", False))
CPG_STR_BED = TR_METH.get("cpg_str_bed", None)

if FILTER_TO_CPG_STR and not CPG_STR_BED:
    print("ERROR: tr_methylation.filter_to_cpg_str=true but tr_methylation.cpg_str_bed is missing.")
    exit(1)

# Load packages
from datetime import datetime
from pathlib import Path
import os
import csv
import re

# Create directory to store logs
os.makedirs(f"{OUTPUT_DIR}/logs", exist_ok=True)

# ID system tmp location
SYS_TMP = os.getenv('TMP')
if SYS_TMP is None:
    SYS_TMP = '/tmp'

CLAIR3_TMP_ROOT = str(Path(workflow.basedir) / ".tmp" / "clair3")


# local rules
localrules: cp_catalogue

# step 07 TR vcf chunking
from datetime import datetime
LOGTIMESTAMP = datetime.now().strftime("%Y_%m_%dT%H%M")
N_VCF_CHUNKS=10

# Get the absolute path to the Snakefile's directory for launching custom scripts
WORKFLOW_ROOT = Path(workflow.basedir)
REF_TE_METH_CPG_RES_SCRIPT_PATH = WORKFLOW_ROOT / "scripts/ref_TE_cpg_res.sh"
REF_TE_METH_AVERAGES_SCRIPT_PATH = WORKFLOW_ROOT / "scripts/ref_TE_avg_meth.sh"
TLDR_METH_SCRIPT_PATH = WORKFLOW_ROOT / "scripts/TLDR-methylation_v2.sh"
SEX_SCRIPT_PATH = WORKFLOW_ROOT / "scripts/sex_from_cramino.py"

# Check if read quality filtering is on or off (if both MIN_READ_QUAL and MIN_READ_LENGTH variables are 0, filtering is skipped)
DO_FILTER = (MIN_READ_QUAL > 0) or (MIN_READ_LENGTH > 0)

# Take into account filtering the longTR VCF prior to methylation analysis
TR_VCF_FOR_METH = f"{OUTPUT_DIR}/06_TR_calling/{{sample}}/{REFERENCE_NAME}/{{sample}}_{REFERENCE_NAME}_TRs_{TYPE_OF_TR}_for_methylation.vcf.gz"

# Where to read *raw* FASTQs from (when START_FROM == "fastq").
# Falls back to the pipeline's default OUTPUT location if not provided.
FASTQ_DIR = config.get("fastq_dir", f"{OUTPUT_DIR}/00_raw_data/basecalled/fastq")


# helper functions
def raw_fastq(wc):
    return f"{FASTQ_DIR}/{wc.sample}/{wc.sample}.fastq"

def fastq_for_pipeline(wc):
    if DO_FILTER:
        return f"{OUTPUT_DIR}/00_raw_data/basecalled/fastq/{wc.sample}/{wc.sample}_filtered.fastq"
    else:
        return f"{OUTPUT_DIR}/00_raw_data/basecalled/fastq/{wc.sample}/{wc.sample}.fastq"

def get_haploid_chromosomes(csv_path):
    with open(csv_path) as f:
        reader = csv.DictReader(f)
        row = next(reader) # only one row expected
    # Strip quotes/spaces: "chrM,chrX,chrY" -> chrM,chrX,chrY
    haploid = row["haploid_chromosomes"].strip().strip('"').replace(" ", "")
    return haploid


#Define outputs files
all_inputs = []

#all_inputs.append(LOGFILE)


if not RESUME_FROM_PHASED: 

    if START_FROM == "pod5":
        all_inputs.extend([
            expand(f"{OUTPUT_DIR}/00_raw_data/basecalled/ubam/{{sample}}/{{sample}}_unaligned.bam", sample=SAMPLES),
            expand(f"{OUTPUT_DIR}/qc/basecalling/{{sample}}/{{sample}}_summary.tsv", sample=SAMPLES),
        ])
    elif START_FROM == "ubam":
        all_inputs.extend([
            expand(f"{OUTPUT_DIR}/qc/fastq/pre_filtering/{{sample}}/{{sample}}_fastq_NanoPlot-report.html", sample=SAMPLES),
        ])
    elif START_FROM == "fastq":
        all_inputs.extend([
            expand(f"{OUTPUT_DIR}/qc/fastq/pre_filtering/{{sample}}/{{sample}}_fastq_NanoPlot-report.html", sample=SAMPLES),
            expand(f"{OUTPUT_DIR}/01_alignment/{{sample}}/{REFERENCE_NAME}/{{sample}}_{REFERENCE_NAME}_sorted.bam", sample=SAMPLES)
        ])
    elif START_FROM == "bam":
        # no basecalling or alignment outputs expected
        pass
    else:
        print(f"ERROR: Invalid 'start_from' value in config.yaml: {START_FROM}")
        exit(1)


#Add filtered fastq output when filtering is applied
if (
    not RESUME_FROM_PHASED
    and START_FROM == "fastq" 
    and DO_FILTER
):
    all_inputs.extend([
        expand(f"{OUTPUT_DIR}/00_raw_data/basecalled/fastq/{{sample}}/{{sample}}_filtered.fastq", sample=SAMPLES)
    ])


#Default file outputs independent from which input file is used
all_inputs.extend([
    expand(f"{OUTPUT_DIR}/qc/phased_bam/{{sample}}/{REFERENCE_NAME}/nanoplot/{{sample}}_{REFERENCE_NAME}_phased_bam_NanoPlot-report.html", sample=SAMPLES),
    expand(f"{OUTPUT_DIR}/07_TR_methylation_calling/{{sample}}/{REFERENCE_NAME}/{TYPE_OF_TR}/{{sample}}_{REFERENCE_NAME}_TRs_{TYPE_OF_TR}_TR_methylation_summary.tsv", sample=SAMPLES),
    expand(f"{OUTPUT_DIR}/08_TE_methylation_calling/{{sample}}/{REFERENCE_NAME}/non_ref_TE/{{sample}}_{REFERENCE_NAME}.table.pass.summary.meth.phased.txt", sample=SAMPLES),
    expand(f"{OUTPUT_DIR}/08_TE_methylation_calling/{{sample}}/{REFERENCE_NAME}/ref_TE/{TYPE_OF_TE}/cpg_resolution/mod_phased/{{sample}}_{REFERENCE_NAME}_{TYPE_OF_TE}_{{catalog}}_pileup_{{pileup}}.bed", sample=SAMPLES, catalog=CATALOGS, pileup=["1", "2"]),
    expand(f"{OUTPUT_DIR}/08_TE_methylation_calling/{{sample}}/{REFERENCE_NAME}/ref_TE/{TYPE_OF_TE}/cpg_resolution/mod_unphased/{{sample}}_{REFERENCE_NAME}_{TYPE_OF_TE}_{{catalog}}_pileup_unphased.bed", sample=SAMPLES, catalog=CATALOGS),
    expand(f"{OUTPUT_DIR}/08_TE_methylation_calling/{{sample}}/{REFERENCE_NAME}/ref_TE/{TYPE_OF_TE}/{{sample}}_{REFERENCE_NAME}_methylation_summary.bed", sample=SAMPLES),
    REFERENCE
])


