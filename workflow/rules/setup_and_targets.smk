# rules/setup_and_targets.smk

configfile: "config.yaml"

# Config Params
START_FROM = config.get("start_from", "pod5")
OUTPUT_DIR = config["output_dir"]
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


# ==================================================================
# INPUT RESOLUTION
# ------------------------------------------------------------------
# Samples and the location of each sample's starting file can be
# provided in two ways (the manifest takes priority if both are given):
#
#   1. manifest:      a TSV/CSV file with one row per sample and at
#                     least the columns 'sample' and 'input'
#                     (optional 'input_index' for aligned BAMs).
#   2. sample_inputs: an inline mapping in the config of
#                     sample_name -> /path/to/input.
#
# A single global 'start_from' applies to every sample in the run.
# 'input' points directly at the starting file for that sample
# (a .pod5 directory, a .ubam, a .fastq, an aligned .bam, or an
# aligned .cram); it can live anywhere on disk with any filename.
# ==================================================================

VALID_START_FROM = {"pod5", "ubam", "fastq", "bam", "cram"}

if START_FROM not in VALID_START_FROM:
    raise WorkflowError(
        f"Invalid 'start_from' value: {START_FROM!r}. "
        f"Choose one of: {', '.join(sorted(VALID_START_FROM))}."
    )


def _load_manifest(path):
    """Parse a TSV/CSV manifest into an ordered {sample: {input, index}} dict.
    Blank lines and lines beginning with '#' (comments) are ignored; the first
    remaining line is treated as the header."""
    if not os.path.isfile(path):
        raise WorkflowError(f"manifest file not found: {path}")

    with open(path, newline="") as fh:
        lines = [ln for ln in fh
                 if ln.strip() and not ln.lstrip().startswith("#")]

    if not lines:
        raise WorkflowError(f"manifest is empty (no header row): {path}")

    delimiter = "\t" if "\t" in lines[0] else ","
    reader = csv.DictReader(lines, delimiter=delimiter)

    if reader.fieldnames is None:
        raise WorkflowError(f"manifest is empty: {path}")

    # normalise header names (case/space-insensitive)
    norm = {name: (name or "").strip().lower() for name in reader.fieldnames}

    table = {}
    for i, raw in enumerate(reader, start=2):  # row 1 is the header
        row = {norm[k]: (v.strip() if isinstance(v, str) else v)
               for k, v in raw.items() if k in norm}
        sample = row.get("sample") or row.get("sample_id") or row.get("name")
        input_path = row.get("input") or row.get("path")
        index_path = row.get("input_index") or row.get("index") or None

        if not sample:
            raise WorkflowError(
                f"manifest {path}: row {i} is missing a 'sample' value.")
        if not input_path:
            raise WorkflowError(
                f"manifest {path}: sample {sample!r} is missing an 'input' path.")
        if sample in table:
            raise WorkflowError(
                f"manifest {path}: duplicate sample {sample!r}.")

        table[sample] = {"input": input_path, "index": index_path or None}

    if not table:
        raise WorkflowError(f"manifest contains no samples: {path}")
    return table


# ---- Build the sample -> input table from the chosen source ----
MANIFEST = config.get("manifest")
SAMPLE_INPUTS_CFG = config.get("sample_inputs")

if MANIFEST:
    SAMPLE_INPUTS = _load_manifest(MANIFEST)
elif isinstance(SAMPLE_INPUTS_CFG, dict) and SAMPLE_INPUTS_CFG:
    SAMPLE_INPUTS = {s: {"input": p, "index": None}
                     for s, p in SAMPLE_INPUTS_CFG.items()}
else:
    raise WorkflowError(
        "No samples defined. Provide either a 'manifest' or a "
        "'sample_inputs' mapping in the config.")

SAMPLES = list(SAMPLE_INPUTS.keys())


# ---- Canonical / source paths for aligned BAM inputs ----
def _canonical_bam(sample):
    """Where the rest of the pipeline expects the aligned BAM to be."""
    return f"{OUTPUT_DIR}/01_alignment/{sample}/{REFERENCE_NAME}/{sample}_{REFERENCE_NAME}_sorted.bam"

def _source_bam(sample):
    """Where the user's aligned BAM actually is (the path they provided)."""
    return SAMPLE_INPUTS[sample]["input"]

def _source_cram(sample):
    """Where the user's aligned CRAM actually is (the path they provided)."""
    return SAMPLE_INPUTS[sample]["input"]


# ---- Sample subsets (needed to keep the alignment / bam-ingest rules
#      unambiguous). With a single global start_from these are either all
#      or none, but they are computed generically. ----
ALIGN_SAMPLES = [s for s in SAMPLES if START_FROM not in ("bam", "cram")]
# Ingest (symlink) a BAM only when its source differs from the canonical
# output location; if they are identical the file already sits where it is
# needed and no rule — and no symlink-to-itself — is required.
BAM_INGEST_SAMPLES = [
    s for s in SAMPLES
    if START_FROM == "bam"
    and os.path.abspath(_source_bam(s)) != os.path.abspath(_canonical_bam(s))
]
# Decode a user-supplied aligned CRAM into the canonical sorted BAM. A CRAM is
# reference-compressed and cannot be symlinked like a BAM, so every cram-mode
# sample is materialised into a real BAM by the cram_to_bam rule.
CRAM_CONVERT_SAMPLES = [s for s in SAMPLES if START_FROM == "cram"]


def samples_regex(sample_list):
    """Anchored alternation for use in per-rule wildcard_constraints.
    Falls back to a token that cannot match any real sample when empty."""
    return "|".join(re.escape(s) for s in sample_list) if sample_list else "__no_sample__"


# ==================================================================
# INPUT RESOLVER FUNCTIONS (used as rule inputs)
# ==================================================================

def get_pod5_dir(wc):
    """pod5 directory for basecalling (the path the user provided)."""
    return SAMPLE_INPUTS[wc.sample]["input"]


def get_input_ubam(wc):
    """uBAM feeding ubam_to_fastq.
    For pod5 runs this is the basecalling output; for ubam runs it is the
    user-provided file."""
    if START_FROM == "pod5":
        # produced by the basecalling rule into the output tree
        return f"{OUTPUT_DIR}/00_raw_data/basecalled/ubam/{wc.sample}/{wc.sample}_unaligned.bam"
    return SAMPLE_INPUTS[wc.sample]["input"]


def raw_fastq(wc):
    """Unfiltered FASTQ used for pre-filtering QC and for filtering.
    For fastq runs this is the user-provided file; for pod5/ubam runs it is
    produced by ubam_to_fastq at the canonical location."""
    if START_FROM == "fastq":
        return SAMPLE_INPUTS[wc.sample]["input"]
    return f"{OUTPUT_DIR}/00_raw_data/basecalled/fastq/{wc.sample}/{wc.sample}.fastq"


def fastq_for_pipeline(wc):
    """FASTQ handed to the aligner: filtered when filtering is on, otherwise
    the raw FASTQ resolved above."""
    if DO_FILTER:
        return f"{OUTPUT_DIR}/00_raw_data/basecalled/fastq/{wc.sample}/{wc.sample}_filtered.fastq"
    return raw_fastq(wc)


def get_input_bam(wc):
    """User-provided aligned BAM (only used by the ingest_bam rule)."""
    return _source_bam(wc.sample)


def get_input_cram(wc):
    """User-provided aligned CRAM (only used by the cram_to_bam rule)."""
    return _source_cram(wc.sample)


def get_input_bai(wc):
    """Path to a user-provided BAM index, if any, else empty string.
    Tried in order: explicit 'input_index', then '<source_bam>.bai' next to it."""
    entry = SAMPLE_INPUTS[wc.sample]
    if entry["index"]:
        return entry["index"]
    candidate = _source_bam(wc.sample) + ".bai"
    if os.path.exists(candidate):
        return candidate
    return ""

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
elif START_FROM in ("bam", "cram"):
    # no basecalling or alignment outputs expected; the canonical sorted BAM is
    # produced on demand (symlinked for bam, decoded for cram) by the DAG.
    pass
else:
    print(f"ERROR: Invalid 'start_from' value in config.yaml: {START_FROM}")
    exit(1)


#Add filtered fastq output when filtering is applied
if START_FROM == "fastq" and DO_FILTER:
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


