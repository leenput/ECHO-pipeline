# validate_config.py
from pathlib import Path

def _file_exists(p):
    return p and Path(p).is_file()

def validate_config(cfg):
    errors = []

    for k in ["output_dir", "reference"]:
        if k not in cfg:
            errors.append(f"Missing required field: {k}")

    # Samples/inputs are declared via a manifest or an inline sample_inputs
    # mapping (the manifest takes priority if both are given).
    manifest = cfg.get("manifest")
    sample_inputs = cfg.get("sample_inputs")

    if not (manifest or sample_inputs):
        errors.append(
            "No samples defined: provide either a 'manifest' or a "
            "'sample_inputs' mapping.")

    if manifest and not _file_exists(manifest):
        errors.append(f"manifest file not found: {manifest}")

    if not _file_exists(cfg["reference"]):
        errors.append(f"reference FASTA not found: {cfg['reference']}")

    for f in ["tr_catalog", "te_catalog", "reference_TE"]:
        if not _file_exists(cfg.get(f)):
            errors.append(f"{f} file not found: {cfg.get(f)}")

    tm = cfg.get("tr_methylation", {})
    if tm.get("filter_to_cpg_str"):
        if not _file_exists(tm.get("cpg_str_bed")):
            errors.append("CpG STR BED missing or invalid")

    return errors

