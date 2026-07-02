# cli.py
import argparse

def parse_args():
    p = argparse.ArgumentParser(
        description="Create a Snakemake config.yaml for the ECHO repeatome pipeline."
    )

    sub = p.add_subparsers(dest="cmd", required=True)

    init = sub.add_parser("init", help="Create a new config.yaml")

    # required outputs
    init.add_argument("--output", required=True, help="Path to write config.yaml")

    # samples: one --sample-input per sample, mapping a sample ID to the path of
    # its starting file (a .pod5 directory, .ubam, .fastq, aligned .bam, or
    # aligned .cram).
    init.add_argument("--sample-input", nargs=2, action="append", required=True,
                      metavar=("SAMPLE", "PATH"), dest="sample_input",
                      help="Sample ID and path to its input file "
                           "(repeat for multiple samples)")

    # pipeline control
    init.add_argument("--start-from",
                      choices=["pod5", "ubam", "fastq", "bam", "cram"],
                      required=True)

    init.add_argument("--output-dir", required=True)

    # reference genome
    init.add_argument("--reference", required=True,
                      help="Reference genome FASTA")
    init.add_argument("--reference-name",
                      choices=["GRCh38", "chm13v2"],
                      default="GRCh38")

    # catalog selection
    init.add_argument("--use-bundled-db", action="store_true",
                      help="Use ECHO-provided catalogs is resources/echoDB_v1")

    init.add_argument("--tr-catalog",
                      help="Custom TR catalog BED (disables ECHO defaults)")
    init.add_argument("--te-catalog",
                      help="Custom TE catalog BED (disables ECHO defaults)")

    init.add_argument(
        "--tr-type",
        default=None,
        help="TR type label used for output folders. In --use-bundled-db mode this must be one of the following:" 
             "genome-wide, genome-wide-hipstr, genome-wide-str-cpg, genome-wide-vntr-cpg, pathogenic, forensic."
              "With custom catalogs, any label is allowed (e.g. custom_pathogenic)."
    )
    init.add_argument(
        "--te-type",
        default=None,
        help="TE type label used for output folders. In --use-bundled-db mode this must be one of: "
              "all, LINE, SINE, LTR, DNA, helitron, retroposon."
              "With custom catalogs, any label is allowed (e.g. my_own_catalog)"
    )

    # CpG filtering
    init.add_argument("--cpg-filter", action="store_true")
    init.add_argument("--no-cpg-filter", dest="cpg_filter", action="store_false")
    init.set_defaults(cpg_filter=None)

    init.add_argument("--cpg-str-bed",
                      help="CpG STR BED (required for custom catalogs + cpg-filter)")

    # read filtering
    init.add_argument("--min-read-quality", type=int, default=7)
    init.add_argument("--min-read-length", type=int, default=500)

    # analysis params
    init.add_argument("--flanking-length-bp", type=int, default=250)
    init.add_argument("--extension-repeat-consensus", type=int, default=1000)

    return p.parse_args()

