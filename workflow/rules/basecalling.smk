# rules/basecalling.smk

rule basecalling:
    input:
        pod5_dir=get_pod5_dir
    output:
        unaligned_bam=f"{OUTPUT_DIR}/00_raw_data/basecalled/ubam/{{sample}}/{{sample}}_unaligned.bam",
        summary_file=f"{OUTPUT_DIR}/qc/basecalling/{{sample}}/{{sample}}_summary.tsv"
    singularity:
        "docker://nanoporetech/dorado:shae423e761540b9d08b526a1eb32faf498f32e8f22"
    log:
        f"{OUTPUT_DIR}/logs/snakemake_rules/basecalling/{{sample}}.log"
    benchmark:
        f"{OUTPUT_DIR}/benchmarks/basecalling/{{sample}}_basecalling.tsv"
    shell:
        """
        (
            dorado basecaller sup,5mCG_5hmCG {input.pod5_dir} --trim > {output.unaligned_bam}
            dorado summary {output.unaligned_bam} > {output.summary_file}
        ) > {log} 2>&1
        """

