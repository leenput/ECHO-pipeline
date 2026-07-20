# rules/alignment.smk

# alignment
rule alignment:
    input:
        fastq=fastq_for_pipeline,
        reference=ancient(REFERENCE)
    output:
        sam=temp(f"{OUTPUT_DIR}/01_alignment/{{sample}}/{REFERENCE_NAME}/{{sample}}.sam")
    log:
        f"{OUTPUT_DIR}/logs/snakemake_rules/alignment/{{sample}}.log"
    threads: 80
    singularity:
        "docker://quay.io/biocontainers/minimap2:2.30--h577a1d6_0"
    benchmark:
        f"{OUTPUT_DIR}/benchmarks/alignment/{{sample}}_alignment.tsv"
    shell:
        """
         minimap2 -ax map-ont -y -2 -t {threads} {input.reference} {input.fastq} > {output.sam} 2> {log}
        """

# SAM convert, sort and index
rule bam_sort_index:
    # Only samples aligned inside the pipeline (start_from not in bam/cram).
    # Aligned BAMs supplied by the user are handled by ingest_bam, and aligned
    # CRAMs by cram_to_bam; constraining the wildcard keeps these rules from
    # clashing on the same canonical output path.
    wildcard_constraints:
        sample=samples_regex(ALIGN_SAMPLES)
    input:
        sam=f"{OUTPUT_DIR}/01_alignment/{{sample}}/{REFERENCE_NAME}/{{sample}}.sam"
    output:
        bam=f"{OUTPUT_DIR}/01_alignment/{{sample}}/{REFERENCE_NAME}/{{sample}}_{REFERENCE_NAME}_sorted.bam",
        bai=f"{OUTPUT_DIR}/01_alignment/{{sample}}/{REFERENCE_NAME}/{{sample}}_{REFERENCE_NAME}_sorted.bam.bai"
    threads: 24
    singularity:
        "docker://staphb/samtools:1.22"
    log:
        f"{OUTPUT_DIR}/logs/snakemake_rules/sort_index/{{sample}}.log"
    benchmark:
        f"{OUTPUT_DIR}/benchmarks/alignment/{{sample}}_bam_sort_index.tsv"
    shell:
        """
        (
            samtools sort -@ {threads} {input.sam} > {output.bam}
            samtools index {output.bam}
        ) > {log} 2>&1
        """


# Ingest a user-supplied *aligned* BAM (start_from == "bam").
# The rest of the pipeline reads the aligned BAM from a single canonical
# location; this rule makes the user's file appear there without moving or
# copying the data: it symlinks the BAM into place and provides the index by
# symlinking a user-supplied .bai (from the manifest 'input_index' column or a
# '<bam>.bai' sitting next to it) or, if none is found, building one with
# 'samtools index'. Only samples in BAM_INGEST_SAMPLES match (see the wildcard
# constraint), so this never competes with bam_sort_index.
rule ingest_bam:
    wildcard_constraints:
        sample=samples_regex(BAM_INGEST_SAMPLES)
    input:
        bam=get_input_bam
    output:
        bam=f"{OUTPUT_DIR}/01_alignment/{{sample}}/{REFERENCE_NAME}/{{sample}}_{REFERENCE_NAME}_sorted.bam",
        bai=f"{OUTPUT_DIR}/01_alignment/{{sample}}/{REFERENCE_NAME}/{{sample}}_{REFERENCE_NAME}_sorted.bam.bai"
    params:
        user_bai=get_input_bai
    log:
        f"{OUTPUT_DIR}/logs/snakemake_rules/ingest_bam/{{sample}}.log"
    threads: 8
    singularity:
        "docker://staphb/samtools:1.22"
    benchmark:
        f"{OUTPUT_DIR}/benchmarks/alignment/{{sample}}_ingest_bam.tsv"
    shell:
        """
        (
            set -euo pipefail
            src_bam=$(readlink -f "{input.bam}")
            ln -sf "$src_bam" "{output.bam}"

            if [ -n "{params.user_bai}" ] && [ -e "{params.user_bai}" ]; then
                src_bai=$(readlink -f "{params.user_bai}")
                ln -sf "$src_bai" "{output.bai}"
            else
                echo "No index supplied for {input.bam}; building one with samtools index." >&2
                samtools index -@ {threads} "{output.bam}"
            fi
        ) > {log} 2>&1
        """


# Decode a user-supplied *aligned* CRAM (start_from == "cram") into the canonical
# sorted BAM the rest of the pipeline expects. Unlike ingest_bam, a CRAM is
# reference-compressed and cannot simply be symlinked: it must be decoded against
# the same reference it was aligned to, so a real BAM (+ index) is materialised
# at the canonical location. The CRAM is assumed to be coordinate-sorted (as
# produced by any aligner); samtools index will fail loudly otherwise. Only
# samples in CRAM_CONVERT_SAMPLES match (see the wildcard constraint), so this
# never competes with bam_sort_index or ingest_bam.
rule cram_to_bam:
    wildcard_constraints:
        sample=samples_regex(CRAM_CONVERT_SAMPLES)
    input:
        cram=get_input_cram,
        reference=ancient(REFERENCE)
    output:
        bam=f"{OUTPUT_DIR}/01_alignment/{{sample}}/{REFERENCE_NAME}/{{sample}}_{REFERENCE_NAME}_sorted.bam",
        bai=f"{OUTPUT_DIR}/01_alignment/{{sample}}/{REFERENCE_NAME}/{{sample}}_{REFERENCE_NAME}_sorted.bam.bai"
    log:
        f"{OUTPUT_DIR}/logs/snakemake_rules/cram_to_bam/{{sample}}.log"
    threads: 24
    singularity:
        "docker://staphb/samtools:1.22"
    benchmark:
        f"{OUTPUT_DIR}/benchmarks/alignment/{{sample}}_cram_to_bam.tsv"
    shell:
        """
        (
            set -euo pipefail
            samtools view -b -@ {threads} -T "{input.reference}" -o "{output.bam}" "{input.cram}"
            samtools index -@ {threads} "{output.bam}"
        ) > {log} 2>&1
        """


