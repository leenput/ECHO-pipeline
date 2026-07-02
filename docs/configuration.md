# Configuration of the ECHO pipeline

ECHO is configured using a project-level `project_config.yaml` file, which is generated
automatically using the helper script `make_config_tiny.py`.

This document provides a **detailed reference** for generating, validating, and
customising the configuration used by the ECHO pipeline.

---

## Overview

Pipeline configuration in ECHO consists of two components:

1. A **project configuration file** (`configs/project_config.yaml`)  
   Defines samples, input/output locations, reference genome, repeat catalogs,
   and analysis parameters.

2. A **Snakemake execution profile**  (`profiles/*/config.yaml`)
   Defines how jobs are submitted to the compute environment (scheduler, resources,
   Singularity settings).

This document focuses on the **project configuration file**.
Profile configuration is described briefly where relevant, but cluster-specific
details are documented in the README.

---

## Generating a configuration file

Configuration files are generated using the following command:

`python scripts/make_config_tiny.py init [OPTIONS]`

The script performs the following steps:

- parses command-line arguments
- builds an internal configuration dictionary
- validates all required paths and parameters
- writes a YAML configuration file if validation succeeds

If validation fails, the script exits with an error and **no YAML file is written**.

---

## Required arguments

The following arguments must always be supplied:

- `init`  
  Subcommand to initialise a new configuration

- `--output`  
  Path where the generated YAML file will be written

- `--sample-input SAMPLE PATH`  
  A sample identifier and the path to its starting file. Repeat the flag once
  per sample (e.g. `--sample-input HG002 /data/HG002.bam --sample-input HG003 /data/HG003.bam`).
  `PATH` must match `--start-from` (a `.pod5` directory, `.ubam`, `.fastq`,
  `.bam`, or `.cram`) and may live anywhere on disk with any filename.

- `--start-from`  
  Input data type: `pod5`, `ubam`, `fastq`, `bam`, or `cram`

- `--output-dir`  
  Project output directory

- `--reference`  
  Path to the reference genome FASTA file

- `--reference-name`  
  Reference build identifier: `GRCh38` or `chm13v2`

---

## Using bundled ECHO repeat catalogs (recommended)

By default, ECHO can use the repeat catalogs bundled with the repository
in `resources/echoDB_v1`.

This mode is enabled with the `--use-bundled-db` flag.

Example usage:

```
python scripts/make_config_tiny.py init \  
  --output config.yaml \
  --sample-input HG002 /path/to/HG002.fastq \
  --sample-input HG003 /path/to/HG003.fastq \
  --start-from fastq \
  --output-dir /path/to/project \
  --reference /path/to/GRCh38.fa \
  --reference-name GRCh38 \
  --use-bundled-db
```

In bundled mode, the script automatically:

- selects appropriate TR and TE catalogs based on the reference build
- enables CpG STR filtering for TR methylation analysis (where compatible)
- fills in default read filtering and analysis parameters

---

## Using custom TR and TE catalogs

Custom repeat catalogs can be supplied using BED files.

When using custom catalogs, the following arguments are **required**:

- `--tr-catalog`  
  Path to a custom TR BED file

- `--te-catalog`  
  Path to a custom TE BED file

- `--tr-type`  
  Label used for TR-related output directories

- `--te-type`  
  Label used for TE-related output directories

Example usage:

```
python scripts/make_config_tiny.py init \
  --output config.yaml \
  --sample-input SAMPLE1 /path/to/sample1.ubam \
  --sample-input SAMPLE2 /path/to/sample2.ubam \
  --start-from ubam \
  --output-dir /path/to/results \
  --reference /path/to/chm13v2.fa \
  --reference-name chm13v2 \
  --tr-catalog /path/to/my_TRs.bed \
  --te-catalog /path/to/my_TEs.bed \
  --tr-type my_TR_label \
  --te-type my_TE_label
```

The `tr-type` and `te-type` labels are used exclusively for naming output
directories and do not affect analysis logic.

---

## Supported TR and TE types in bundled mode

### Tandem repeat (TR) types

When `--use-bundled-db` is enabled, `--tr-type` must be one of:

- `genome-wide`
- `genome-wide-hipstr`
- `genome-wide-str-cpg`
- `genome-wide-vntr-cpg`
- `pathogenic`
- `forensic`

If `--tr-type` is not provided, it defaults to `genome-wide`.

### Transposable element (TE) types

When `--use-bundled-db` is enabled, `--te-type` must be one of:

- `all`
- `LINE`
- `SINE`
- `LTR`
- `DNA`
- `helitron`
- `retroposon`

If `--te-type` is not provided, it defaults to `all`.

---

## Reference-build–specific behaviour

### GRCh38

- All bundled TR types are supported
- Genome-wide and class-specific TE catalogs are available

### chm13v2 (T2T-CHM13v2)

- Bundled TR support is currently limited to `pathogenic`
- All TE catalogs are supported
- Other TR analyses require custom TR catalogs

---

## CpG STR filtering for TR methylation analysis

ECHO supports optional filtering of TR methylation analysis to STRs
containing CpG sites.

This behaviour is controlled using:

- `--cpg-filter`
- `--no-cpg-filter`

### Default behaviour

- Bundled database mode: CpG filtering is enabled by default
- Custom catalog mode: CpG filtering is disabled by default

### Automatic disabling

CpG filtering is automatically disabled if:

- a CpG-filtered TR catalog is selected for genotyping (`genome-wide-str-cpg` or `genome-wide-vntr-cpg`)
- an incompatible bundled TR type is selected (e.g. `pathogenic` or `forensic`)

A warning is printed when this occurs.

### Custom catalogs with CpG filtering

If CpG filtering is enabled with custom catalogs, you must also provide:

- `--cpg-str-bed`  
  Path to a BED file containing CpG STR loci compatible with the TR catalog

If this file is missing, configuration generation will fail.

---

## Read filtering parameters (optional)

The following parameters populate the `fastq_filtering` section of the YAML file:

- `--min-read-quality` (default: 7)
- `--min-read-length` (default: 500)

---

## Analysis parameters (optional)

The following parameters control downstream TR and TE analysis:

- `--flanking-length-bp` (default: 250)
- `--extension-repeat-consensus` (default: 1000)

---

## Validation performed before writing YAML

Before writing the configuration file, the script validates that:

- `input-dir` exists and is a directory
- `reference` exists and is a file
- selected TR and TE catalog files exist
- the TE reference FASTA exists
- if CpG filtering is enabled, the CpG STR BED file exists

If any check fails, the script exits with an error and **no configuration file
is written**.

---

## Next steps

After generating a valid `config.yaml`, ensure that:

- the selected Snakemake profile points to this file
- cluster-specific settings (scheduler, resources, Singularity mounts) are correct

See the main README and associated docs for details on configuring and using execution profiles.

