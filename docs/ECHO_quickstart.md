# ECHO cookbook-style quick start

This guide provides copy-ready examples for running ECHO on a SLURM cluster from three common starting points:


1. [unaligned BAM or FASTQ](#recipe-1-start-from-unaligned-bam-or-fastq);
2. [aligned BAM or CRAM](#recipe-2-start-from-aligned-bam-or-cram);
3. [POD5](#recipe-3-start-from-pod5).

The examples use the repeat catalogues bundled with ECHO and assume that the workflow is run from the root directory of the cloned repository.

> [!IMPORTANT]
> ECHO uses two independent configuration layers:
>
> - the **project configuration** defines the samples, input files, reference genome, repeat catalogues and analysis parameters;
> - the **execution profile** defines how Snakemake runs jobs on the local computer or cluster, including the scheduler, partitions, CPUs, memory and Singularity bind mounts.
>
> The project configuration is normally created for each analysis. The execution profile is adapted to the computing environment and can then be reused across projects.

For the full reference documentation, see:

- [Project configuration](configuration.md)
- [Repeat catalogues](repeat_catalogs.md)
- [Output files](output.md)
- [Tools used by ECHO](tools.md)

---

## Contents

- [Before you begin](#before-you-begin)
- [Install ECHO and the repeat catalogues](#install-echo-and-the-repeat-catalogues)
- [Configure SLURM execution](#configure-slurm-execution)
- [Recipe 1: start from unaligned BAM or FASTQ](#recipe-1-start-from-unaligned-bam-or-fastq)
- [Recipe 2: start from aligned BAM or CRAM](#recipe-2-start-from-aligned-bam-or-cram)
- [Recipe 3: start from POD5](#recipe-3-start-from-pod5)
- [Use a manifest for many samples](#use-a-manifest-for-many-samples)
- [Validate the workflow](#validate-the-workflow)
- [Run ECHO](#run-echo)
- [Monitor and resume the workflow](#monitor-and-resume-the-workflow)
- [Find the main outputs](#find-the-main-outputs)
- [Use custom repeat catalogues](#use-custom-repeat-catalogues)
- [Common problems](#common-problems)

---

## Before you begin

### Required software

ECHO requires:

- Singularity `>=3.7` and `<4.0`;
- Snakemake `>=9.0`;

Check the available software:

```bash
snakemake --version
singularity --version
conda --version
sbatch --version
```

### Information needed from the cluster administrator

Before adapting the ECHO profile, determine:

- the CPU partition;
- the GPU partition (when starting from POD5);
- the maximum permitted job duration;
- the maximum memory and CPU allocation per job;
- the recommended number of simultaneously submitted jobs;
- slurm account (optional);
- where long-running Snakemake controller processes should be started.

> [!NOTE]
> Cluster names, partitions, and resource limits are specific to the site computational infrastructure. Values shown in the supplied ECHO profile are examples and must be reviewed before use.

## Install ECHO and the repeat catalogues

Install ECHO in a directory visible from the cluster compute nodes:

```bash
git clone https://github.com/leenput/ECHO-pipeline.git
cd ECHO-pipeline

bash scripts/download_repeat_catalogs.sh
```

The downloaded catalogues are stored under:

```text
resources/echoDB_v1/
```

The `--use-bundled-db` option used below selects compatible TR and TE catalogues from this directory.

> [!IMPORTANT]
> Run the configuration and Snakemake commands from the root of the ECHO repository. Several bundled-resource paths are written relative to this directory.

---


## Configure SLURM execution

This is normally a one-time setup for each computing environment.

### 1. Copy the supplied HPC profile

Do not edit the distributed template directly. Make a cluster-specific copy:

```bash
cp -r profiles/HPC_profile profiles/my_cluster
```

Open the copied profile:

```bash
nano profiles/my_cluster/config.yaml
```

Replace `my_cluster` with a short name for your computing environment.

### 2. Set Singularity bind mounts

The supplied profile contains a placeholder:

```yaml
singularity-args: "-B /path/to/projects/{project_name}/"
```

Replace it with the filesystem roots containing:

- the ECHO repository and bundled catalogues;
- the input data;
- the reference genome;
- the output directory;
- any temporary or scratch directory required by the cluster.

For example:

```yaml
singularity-args: "-B /path/to/ECHO-pipeline,/data,/references,/projects,/scratch"
```

All files used by ECHO must be accessible inside the Singularity containers.

Use absolute paths and bind the relevant parent directories rather than individual files.

### 3. Set the CPU partition

The supplied profile uses the example partition name `research`. Replace **all** relevant occurrences of:

```yaml
slurm_partition: "research"
```

> [!IMPORTANT]
> Rule-specific `slurm_partition` entries override the default partition, so changing only the entry under `default-resources` is not sufficient when the rule-specific entries still contain the example value.

### 4. Add a SLURM account when required

Some clusters require an account for job submission. Add it under `default-resources`:

```yaml
default-resources:
  slurm_account: "your_account"
  slurm_partition: "compute"
  mem: "24G"
  runtime: 5000
  threads: 24
```

Omit `slurm_account` when the cluster does not require it or does not allow users to set it explicitly.

### 5. Review job concurrency

The supplied profile contains:

```yaml
jobs: 8
```

This limits the number of SLURM jobs managed concurrently by Snakemake. It does not set the number of CPUs used by each job.

Start with a value permitted by local cluster policy. Increasing it can allow more independent samples or workflow rules to run simultaneously.

### 6. Review rule-specific resources

The supplied profile contains starting resource requests for individual rules. The largest memory requests currently include:

| Component | Memory request in supplied profile |
|---|---:|
| LongPhase phasing | 200 GB |
| TE calling | 128 GB |
| SNP/indel calling | 96 GB |
| Basecalling | 64 GB |
| TR calling | 28 GB |

Review the complete `set-resources` and `set-threads` sections before running ECHO.

When a rule requires a different partition, set it explicitly:

```yaml
set-resources:
  longphase_phase:
    slurm_partition: "research"
    mem: "200G"
    runtime: 600
```

The `runtime` values are specified in minutes.

### 7. Configure GPU resources for POD5 input

The supplied profile requests three GPUs for the `basecalling` rule:

```yaml
basecalling:
  slurm_partition: "gpu"
  gpu: 3
  mem: "64G"
  runtime: 11520
```

When starting from POD5:

- replace `gpu` with the correct GPU partition;
- adjust `gpu`, memory and runtime to the available hardware and cluster policy.

When starting from uBAM, FASTQ, BAM or CRAM, the basecalling rule is not scheduled and these GPU settings are not used.

### 8. Keep the profile reusable across projects

The supplied profile contains a default project configuration:

```yaml
configfile: "configs/project_config.yaml"
```

The recipes below supply the project configuration explicitly with `--configfile`. The command-line value overrides the value in the profile, allowing the same cluster profile to be reused for multiple projects.

---


# Recipe 1: start from unaligned BAM or FASTQ

Use this recipe when ECHO should perform read preprocessing, alignment, variant calling, phasing and downstream repeat analyses.

All samples in one run must use the same `start_from` value.

## Option A: unaligned BAM

Set the project-specific paths:

```bash
SAMPLE="SAMPLE1"
INPUT_UBAM="/absolute/path/to/SAMPLE1_unaligned.bam"
REFERENCE="/absolute/path/to/GRCh38.fa"
OUTPUT_DIR="/absolute/path/to/results/echo_project"
PROJECT_CONFIG="${ECHO_DIR}/configs/echo_project_from_ubam.yaml"
```

Check the starting files:

```bash
ls -lh "${INPUT_UBAM}"
ls -lh "${REFERENCE}"
```

Generate the project configuration:

```bash
cd "${ECHO_DIR}"

python scripts/make_config_tiny.py init \
  --output "${PROJECT_CONFIG}" \
  --sample-input "${SAMPLE}" "${INPUT_UBAM}" \
  --start-from ubam \
  --output-dir "${OUTPUT_DIR}" \
  --reference "${REFERENCE}" \
  --reference-name GRCh38 \
  --use-bundled-db
```

By default, ECHO:

- converts the uBAM to FASTQ;
- filters reads below Q7 or 500 bp;
- performs pre- and post-filtering QC;
- aligns reads to the configured reference;
- calls small variants and structural variants;
- phases variants and haplotags the alignment;
- performs TR and TE genotyping and methylation analyses.

## Option B: FASTQ

Set the project-specific paths:

```bash
SAMPLE="SAMPLE1"
INPUT_FASTQ="/absolute/path/to/SAMPLE1.fastq"
REFERENCE="/absolute/path/to/GRCh38.fa"
OUTPUT_DIR="/absolute/path/to/results/echo_project"
PROJECT_CONFIG="${ECHO_DIR}/configs/echo_project_from_fastq.yaml"
```

Generate the project configuration:

```bash
cd "${ECHO_DIR}"

python scripts/make_config_tiny.py init \
  --output "${PROJECT_CONFIG}" \
  --sample-input "${SAMPLE}" "${INPUT_FASTQ}" \
  --start-from fastq \
  --output-dir "${OUTPUT_DIR}" \
  --reference "${REFERENCE}" \
  --reference-name GRCh38 \
  --use-bundled-db
```

For FASTQ input, ECHO starts with FASTQ QC and filtering and then performs alignment and all downstream analyses.

### Change the read-filtering thresholds

The default thresholds are:

```text
minimum read quality: 7
minimum read length: 500 bp
```

Override them during configuration generation:

```bash
python scripts/make_config_tiny.py init \
  --output "${PROJECT_CONFIG}" \
  --sample-input "${SAMPLE}" "${INPUT_FASTQ}" \
  --start-from fastq \
  --output-dir "${OUTPUT_DIR}" \
  --reference "${REFERENCE}" \
  --reference-name GRCh38 \
  --use-bundled-db \
  --min-read-quality 10 \
  --min-read-length 1000
```

Setting both thresholds to `0` disables read filtering:

```bash
--min-read-quality 0 \
--min-read-length 0
```

---

# Recipe 2: start from aligned BAM or CRAM

Use this recipe when the reads have already been aligned to the reference genome.

ECHO skips uBAM conversion, FASTQ QC/filtering and alignment, but still performs variant calling, phasing and the downstream repeat and methylation analyses.

## Option A: aligned BAM

Set the project-specific paths:

```bash
SAMPLE="SAMPLE1"
INPUT_BAM="/absolute/path/to/SAMPLE1_aligned.bam"
REFERENCE="/absolute/path/to/GRCh38.fa"
OUTPUT_DIR="/absolute/path/to/results/echo_project"
PROJECT_CONFIG="${ECHO_DIR}/configs/echo_project_from_bam.yaml"
```

Check the BAM and reference:

```bash
ls -lh "${INPUT_BAM}"
ls -lh "${REFERENCE}"
```

Generate the project configuration:

```bash
cd "${ECHO_DIR}"

python scripts/make_config_tiny.py init \
  --output "${PROJECT_CONFIG}" \
  --sample-input "${SAMPLE}" "${INPUT_BAM}" \
  --start-from bam \
  --output-dir "${OUTPUT_DIR}" \
  --reference "${REFERENCE}" \
  --reference-name GRCh38 \
  --use-bundled-db
```

For BAM input:

- the supplied BAM is symlinked into ECHO's `01_alignment/` directory;
- the BAM itself is not copied;
- ECHO uses an adjacent `<BAM>.bai` index when present;
- otherwise, ECHO creates an index with `samtools index`.

The BAM must be coordinate-sorted and aligned against the configured reference assembly.

## Option B: aligned CRAM

Set the project-specific paths:

```bash
SAMPLE="SAMPLE1"
INPUT_CRAM="/absolute/path/to/SAMPLE1_aligned.cram"
REFERENCE="/absolute/path/to/GRCh38.fa"
OUTPUT_DIR="/absolute/path/to/results/echo_project"
PROJECT_CONFIG="${ECHO_DIR}/configs/echo_project_from_cram.yaml"
```

Generate the project configuration:

```bash
cd "${ECHO_DIR}"

python scripts/make_config_tiny.py init \
  --output "${PROJECT_CONFIG}" \
  --sample-input "${SAMPLE}" "${INPUT_CRAM}" \
  --start-from cram \
  --output-dir "${OUTPUT_DIR}" \
  --reference "${REFERENCE}" \
  --reference-name GRCh38 \
  --use-bundled-db
```

For CRAM input:

- the configured reference must be the same reference used to create the CRAM;
- ECHO decodes the CRAM into a real BAM under `01_alignment/`;
- sufficient storage must therefore be available for the decoded BAM and its index;
- the CRAM is expected to contain coordinate-sorted align

---

# Recipe 3: start from POD5

Use this recipe when ECHO should perform Dorado basecalling before the steps described in Recipe 1.

First ensure that the GPU partition and GPU resource request in the SLURM profile have been adapted to the cluster.

Set the project-specific paths:

```bash
SAMPLE="SAMPLE1"
INPUT_POD5="/absolute/path/to/SAMPLE1_pod5_directory"
REFERENCE="/absolute/path/to/GRCh38.fa"
OUTPUT_DIR="/absolute/path/to/results/echo_project"
PROJECT_CONFIG="${ECHO_DIR}/configs/echo_project_from_pod5.yaml"
```

The input path must be a directory containing `.pod5` files:

Generate the project configuration:

```bash
cd "${ECHO_DIR}"

python scripts/make_config_tiny.py init \
  --output "${PROJECT_CONFIG}" \
  --sample-input "${SAMPLE}" "${INPUT_POD5}" \
  --start-from pod5 \
  --output-dir "${OUTPUT_DIR}" \
  --reference "${REFERENCE}" \
  --reference-name GRCh38 \
  --use-bundled-db
```

The current ECHO basecalling rule uses Dorado with the `sup,5mCG_5hmCG` model and writes an unaligned BAM before continuing with FASTQ conversion, QC, alignment and downstream analyses.ments.

---

---

## Add multiple samples

Repeat `--sample-input SAMPLE PATH` once per sample:

```bash
python scripts/make_config_tiny.py init \
  --output configs/echo_multi_sample_project.yaml \
  --sample-input SAMPLE1 /absolute/path/to/SAMPLE1.bam \
  --sample-input SAMPLE2 /absolute/path/to/SAMPLE2.bam \
  --sample-input SAMPLE3 /absolute/path/to/SAMPLE3.bam \
  --start-from bam \
  --output-dir /absolute/path/to/results/echo_multi_sample_project \
  --reference /absolute/path/to/GRCh38.fa \
  --reference-name GRCh38 \
  --use-bundled-db
```

Sample identifiers must be unique.

---

## Use a manifest for many samples

For larger projects, a manifest is easier to maintain than a long command.

Create a tab-separated file:

```bash
nano configs/echo_project_samples.tsv
```

For uBAM, FASTQ, CRAM or POD5 input:

```text
sample	input
SAMPLE1	/absolute/path/to/SAMPLE1.bam
SAMPLE2	/absolute/path/to/SAMPLE2.bam
```

For aligned BAM input, an optional `input_index` column may be included:

```text
sample	input	input_index
SAMPLE1	/absolute/path/to/SAMPLE1.bam	/absolute/path/to/SAMPLE1.bam.bai
SAMPLE2	/absolute/path/to/SAMPLE2.bam	/absolute/path/to/SAMPLE2.bam.bai
```

Generate a project YAML with the appropriate recipe, then replace the `sample_inputs` section with:

```yaml
manifest: "/absolute/path/to/ECHO-pipeline/configs/echo_project_samples.tsv"
```

The `start_from` setting remains global and therefore applies to every sample listed in the manifest.

> [!NOTE]
> When both `manifest` and `sample_inputs` are present, ECHO uses the manifest.

---


## Inspect the generated project configuration

After any recipe, inspect the generated YAML:

```bash
less "${PROJECT_CONFIG}"
```

Check at least:

```yaml
start_from:
sample_inputs:
output_dir:
reference:
reference_name:
reference_TE:
tr_catalog:
type_of_tr:
te_catalog:
type_of_te:
fastq_filtering:
tr_methylation:
```

For GRCh38 with `--use-bundled-db`, the default analysis uses:

- the genome-wide Adotto LongTR catalogue;
- the genome-wide TE catalogue;
- CpG-containing STR filtering for downstream TR methylation;
- 250 bp flanking regions;
- a 1000 bp repeat-consensus extension.

See [configuration.md](configuration.md) for all available options.

---
## Validate the workflow

Always perform a dry run before submitting the complete workflow.

From the ECHO repository root:

```bash
cd "${ECHO_DIR}"

snakemake \
  --snakefile workflow/snakefile \
  --profile profiles/my_cluster \
  --configfile "${PROJECT_CONFIG}" \
  --dry-run \
  --printshellcmds
```
The dry run should finish without configuration errors or missing-input errors.

Check that the planned rules match the selected input type:

| Input type | Steps that should not be scheduled |
|---|---|
| `pod5` | none of the upstream steps |
| `ubam` | Dorado basecalling |
| `fastq` | Dorado basecalling and uBAM-to-FASTQ conversion |
| `bam` | basecalling, uBAM-to-FASTQ conversion, FASTQ QC/filtering and alignment |
| `cram` | basecalling, uBAM-to-FASTQ conversion, FASTQ QC/filtering and alignment; CRAM-to-BAM conversion is scheduled |

For a compact dry-run summary:

```bash
snakemake \
  --snakefile workflow/snakefile \
  --profile profiles/my_cluster \
  --configfile "${PROJECT_CONFIG}" \
  --dry-run \
  --quiet
```


---

## Run ECHO

After the dry run completes successfully:

```bash
cd "${ECHO_DIR}"

snakemake \
  --snakefile workflow/snakefile \
  --profile profiles/my_cluster \
  --configfile "${PROJECT_CONFIG}"
```

The Snakemake controller process must remain active while it submits and monitors cluster jobs. Start it in the location recommended by the cluster administrators, such as a persistent login session, an interactive allocation or a dedicated workflow node.

---

## Monitor and resume the workflow

### View SLURM jobs

```bash
squeue -u "${USER}"
```

A more detailed view:

```bash
squeue -u "${USER}" \
  --format="%.18i %.12P %.30j %.8T %.10M %.6D %R"
```

### Inspect ECHO logs

List rule-level logs:

```bash
find "${OUTPUT_DIR}/logs" -type f | sort
```

Inspect the end of a failed rule log:

```bash
tail -n 100 /path/to/relevant_rule.log
```

### Inspect benchmark files

```bash
find "${OUTPUT_DIR}/benchmarks" -type f | sort
```

### Resume after interruption or failure

After correcting the cause of a failed job, rerun the same command:

```bash
snakemake \
  --snakefile workflow/snakefile \
  --profile profiles/my_cluster \
  --configfile "${PROJECT_CONFIG}"
```

Snakemake will reuse completed outputs. The supplied profile also enables:

```yaml
rerun-incomplete: true
```

which causes incomplete outputs to be recreated.

---

## Find the main outputs

The ECHO project directory is organised as follows:

```text
<OUTPUT_DIR>/
├── 00_raw_data/
├── 01_alignment/
├── 02_variant_calling/
├── 03_phasing/
├── 04_methylation_calling/
├── 05_non_ref_TE_calling/
├── 06_TR_calling/
├── 07_TR_methylation_calling/
├── 08_TE_methylation_calling/
├── benchmarks/
├── logs/
└── qc/
```

Important results include:

| Analysis | Main location |
|---|---|
| Aligned BAM | `01_alignment/<sample>/<reference>/` |
| Small and structural variants | `02_variant_calling/` |
| Phased and haplotagged BAM | `03_phasing/<sample>/<reference>/` |
| Genome-wide methylation pile-ups | `04_methylation_calling/<sample>/<reference>/` |
| Non-reference TE calls | `05_non_ref_TE_calling/<sample>/<reference>/` |
| LongTR genotypes | `06_TR_calling/<sample>/` |
| TR methylation VCF and summary | `07_TR_methylation_calling/<sample>/<reference>/<TR_type>/` |
| Reference and non-reference TE methylation | `08_TE_methylation_calling/<sample>/<reference>/` |

See [output.md](output.md) for the detailed directory structure and file descriptions.

---

## Use custom repeat catalogues

To replace both bundled catalogues, provide custom BED files and labels:

```bash
python scripts/make_config_tiny.py init \
  --output "${PROJECT_CONFIG}" \
  --sample-input "${SAMPLE}" "${INPUT_BAM}" \
  --start-from bam \
  --output-dir "${OUTPUT_DIR}" \
  --reference "${REFERENCE}" \
  --reference-name GRCh38 \
  --tr-catalog /absolute/path/to/custom_TR_catalog.bed \
  --te-catalog /absolute/path/to/custom_TE_catalog.bed \
  --tr-type custom_TR_set \
  --te-type custom_TE_set
```

The `--tr-type` and `--te-type` values are labels used in output directory and file names.

To enable CpG filtering with a custom TR catalogue, also provide a matched CpG-STR BED file:

```bash
--cpg-filter \
--cpg-str-bed /absolute/path/to/matched_CpG_STR_catalog.bed
```

See [repeat_catalogs.md](repeat_catalogs.md) and [configuration.md](configuration.md) before using custom resources.

---

## Common problems

### `MissingInputException`

Check that:

- all paths are absolute;
- the input file or POD5 directory exists;
- the reference path is correct;
- the selected `start_from` value matches the input;
- the project is being run from the ECHO repository root;
- all paths are visible on the compute nodes.

### A file exists on the host but is missing inside the container

Add the relevant filesystem root to `singularity-args` in the execution profile.

For example:

```yaml
singularity-args: "-B /data,/references,/projects,/path/to/ECHO-pipeline"
```

### SLURM rejects jobs immediately

Check:

- `slurm_partition`;
- `slurm_account`;
- memory and runtime limits;
- the number of requested GPUs;
- whether the requested resources are available on that partition.

### A job is killed for exceeding memory or runtime

Inspect the corresponding benchmark and log files, then increase the rule-specific `mem` or `runtime` value in the copied profile.

Example:

```yaml
set-resources:
  TR_calling:
    mem: "40G"
    runtime: 2880
```

Perform another dry run before restarting.

### BAM indexing fails

Confirm that the BAM is coordinate-sorted:

```bash
samtools quickcheck -v /absolute/path/to/sample.bam
samtools view -H /absolute/path/to/sample.bam | grep '^@HD'
```

Provide an existing `.bai` in the manifest, place it next to the BAM as `<BAM>.bai`, or allow ECHO to create the index.

### CRAM conversion fails

Confirm that:

- the CRAM is coordinate-sorted;
- the configured FASTA is the exact reference used to encode the CRAM;
- the reference and CRAM are visible inside the container;
- sufficient storage is available for the decoded BAM.

### Configuration generation fails

The helper refuses to write a YAML file when required reference or catalogue resources are missing. Read every reported path carefully and rerun the command after correcting it.

---

## Optional: test the installation first

The ECHO Zenodo record provides:

- a small smoke-test dataset for technical validation;
- an HG002 15× example output dataset for inspecting the expected folder structure and results.

See the **Test data** section of the main [README](../README.md) before running a large dataset.

---

## Next steps

After the first successful run:

- review the [configuration reference](configuration.md) before changing analysis parameters;
- review the [repeat catalogue documentation](repeat_catalogs.md) before selecting a targeted or custom repeat set;
- use the [output reference](output.md) to identify the main result files;
- inspect `benchmarks/` and `logs/` when adapting cluster resources.


