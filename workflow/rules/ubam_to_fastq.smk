# rules/ubam_to_fastq.smk

# conversion of ubam to fastq
rule ubam_to_fastq:
    input:
        unaligned_bam=get_input_ubam
    output:
        fastq=f"{OUTPUT_DIR}/00_raw_data/basecalled/fastq/{{sample}}/{{sample}}.fastq"
    log:
        f"{OUTPUT_DIR}/logs/snakemake_rules/ubam_to_fastq/{{sample}}.log"
    threads: 24
    singularity:
        "docker://staphb/samtools:1.22"
    benchmark:
        f"{OUTPUT_DIR}/benchmarks/ubam_to_fastq/{{sample}}_ubam_to_fastq.tsv"
    shell:
        """
        samtools fastq -@ {threads} -T 'MM,ML' {input.unaligned_bam} > {output.fastq} 2> {log}
        """

