# build_config.py
from pathlib import Path
import sys

DB_ROOT = Path("resources/echoDB_v1")

BUNDLED_TR_TYPES = {
    "genome-wide",
    "genome-wide-hipstr",
    "genome-wide-str-cpg",
    "genome-wide-vntr-cpg",
    "pathogenic",
    "forensic",
}
BUNDLED_TE_TYPES = {"all", "LINE", "SINE", "LTR", "DNA", "helitron", "retroposon"}


def build_config(args):
    cfg = {}

    # ---- basic fields (always present) ----
    cfg["start_from"] = args.start_from

    # inline sample -> input mapping (one entry per --sample-input)
    sample_inputs = {}
    for sample, path in args.sample_input:
        if sample in sample_inputs:
            raise ValueError(f"duplicate sample in --sample-input: {sample!r}")
        sample_inputs[sample] = path
    cfg["sample_inputs"] = sample_inputs

    cfg["output_dir"] = args.output_dir
    cfg["reference"] = args.reference
    cfg["reference_name"] = args.reference_name

    cfg["fastq_filtering"] = {
        "min_read_quality": args.min_read_quality,
        "min_read_length": args.min_read_length,
    }

    cfg["flanking_length_bp"] = args.flanking_length_bp
    cfg["extension_repeat_consensus"] = args.extension_repeat_consensus

    # ---- reference TE (ALWAYS bundled) ----
    cfg["reference_TE"] = str(DB_ROOT / "TEs/teref.ont.human.fa")

    # ---- catalog logic ----
    if args.use_bundled_db:
        build = args.reference_name

        tr_type = args.tr_type or "genome-wide"
        te_type = args.te_type or "all"

        if tr_type not in BUNDLED_TR_TYPES:
            raise ValueError(f"--tr-type {tr_type!r} not supported with --use-bundled-db. Choose from {sorted(BUNDLED_TR_TYPES)}")
        if te_type not in BUNDLED_TE_TYPES:
            raise ValueError(f"--te-type {te_type!r} not supported with --use-bundled-db. Choose from {sorted(BUNDLED_TE_TYPES)}")

        cfg["type_of_tr"] = tr_type
        cfg["type_of_te"] = te_type

        if build == "GRCh38":
            if tr_type == "genome-wide":
                cfg["tr_catalog"] = str(DB_ROOT / "TRs/GRCh38/genome-wide/adotto_longTR.bed")
            elif tr_type == "genome-wide-hipstr":
                cfg["tr_catalog"] = str(DB_ROOT / "TRs/GRCh38/genome-wide/hipstr_reference_longTR.bed")
            elif tr_type == "pathogenic":
                cfg["tr_catalog"] = str(DB_ROOT / "TRs/GRCh38/pathogenic/STRchive-disease-loci.v2.2.1.GRCh38.longTR.bed")
            elif tr_type == "forensic":
                cfg["tr_catalog"] = str(DB_ROOT / "TRs/GRCh38/forensic/STRbase_GRCh38_STRloci_longTR.bed")
            elif tr_type == "genome-wide-str-cpg":
                cfg["tr_catalog"] = str(DB_ROOT / "TRs/GRCh38/genome-wide-str-cpg/adotto_longTR_STR_cpgmotif.bed")
            elif tr_type == "genome-wide-vntr-cpg":
                cfg["tr_catalog"] = str(DB_ROOT / "TRs/GRCh38/genome-wide-vntr-cpg/adotto_longTR_VNTR_cpgmotif.bed")
            else:
                raise ValueError(f"Unknown --tr-type: {tr_type}")

            if te_type == "all":
                cfg["te_catalog"] = str(DB_ROOT / "TEs/GRCh38/GRCh38_TEs_all.bed")
            else:
                cfg["te_catalog"] = str(
                    DB_ROOT / f"TEs/GRCh38/TE_classes/GRCh38_TEs_{te_type}.bed"
                )
        elif build == "chm13v2":
            if tr_type != "pathogenic":
                raise ValueError(
                    "Bundled DB for chm13v2 currently supports only --tr-type pathogenic. "
                    "For other TR types, provide --tr-catalog (or disable --use-bundled-db)."
                )
            # Path to your bundled CHM13 pathogenic TR catalog (adjust to your real filename)
            cfg["tr_catalog"] = str(
                DB_ROOT / "TRs/T2T-CHM13v2/pathogenic/STRchive-disease-loci.v2.2.1.T2T-CHM13.longTR.bed"
            )

            # TE handling for CHM13v2:            
            if te_type == "all":
                cfg["te_catalog"] = str(DB_ROOT / "TEs/T2T-CHM13v2/T2T-CHM13_TEs_all.bed")
            else:
                cfg["te_catalog"] = str(
                    DB_ROOT / f"TEs/T2T-CHM13v2/TE_classes/T2T-CHM13_TEs_{te_type}.bed"
                )

        else:
            raise ValueError("Bundled TR DB only supports GRCh38/T2T-CHM13v2 for now")

    else:
        # custom catalogs
        if not args.tr_catalog or not args.te_catalog:
            raise ValueError("Custom catalogs require --tr-catalog AND --te-catalog")

        cfg["tr_catalog"] = args.tr_catalog
        cfg["te_catalog"] = args.te_catalog

        if not args.tr_type or not args.te_type:
            raise ValueError("Custom catalogs require --tr-type and --te-type (used for output folder names).")
        
        cfg["type_of_tr"] = args.tr_type
        cfg["type_of_te"] = args.te_type

    # normalize for the rest of the function (works for both branches)
    tr_type = cfg["type_of_tr"]
    te_type = cfg["type_of_te"]

    # ---- CpG filtering ----
    cfg["tr_methylation"] = {}

   
     # Decide whether CpG filtering is enabled: 
     # - use bundled DB: default ON (unless user explicitly disables or if incompatible)
     # - custom catalogs: default OFF (unless user explicitly enables)
   
    if args.use_bundled_db:
        enable_cpg = True if args.cpg_filter is None else bool(args.cpg_filter)
    else:
        enable_cpg = False if args.cpg_filter is None else bool(args.cpg_filter)

    # If the user already selected a CpG-filtered TR catalog,
    # do NOT apply CpG filtering again
    if tr_type in ("genome-wide-str-cpg", "genome-wide-vntr-cpg"):
        if enable_cpg:
            print(
                f"WARNING: TR catalog '{tr_type}' is already CpG-filtered. "
                "Disabling CpG filtering step.",
                file=sys.stderr,
            )
        enable_cpg = False

    # Determine CpG STR BED (only if filtering is enabled)
    cpg_bed = None

    if enable_cpg:
        if args.use_bundled_db:
            # Bundled defaults depend on which bundled TR catalog you selected
            # IMPORTANT: We only consider CpG STR filtering "compatible" for genome-wide catalogs.
            if tr_type == "genome-wide":
                cpg_bed = DB_ROOT / "TRs/GRCh38/genome-wide-str-cpg/adotto_longTR_STR_cpgmotif.bed"
            elif tr_type == "genome-wide-hipstr":
                cpg_bed = DB_ROOT / "TRs/GRCh38/genome-wide-str-cpg/hipstr_reference_longTR_STR_cpgmotif.bed"
            else:
                # Pathogenic/forensic: bundled CpG bed is NOT matched -> disable automatically
                print(
                    f"WARNING: CpG STR filtering is not compatible with bundled TR type '{tr_type}'. "
                    "Disabling CpG filtering. (Use a matched --cpg-str-bed with custom catalogs if needed.)",
                    file=sys.stderr,
                )
                enable_cpg = False
                cpg_bed = None

        else:
            # Custom catalogs: user MUST provide a matched CpG STR bed
            if not args.cpg_str_bed:
                raise ValueError(
                    "ERROR: --cpg-filter was enabled with custom catalogs, but --cpg-str-bed was not provided. "
                    "Provide a CpG STR BED matched to your TR catalog, or disable CpG filtering."
                )
            cpg_bed = Path(args.cpg_str_bed)

    # Write to config
    cfg["tr_methylation"]["filter_to_cpg_str"] = bool(enable_cpg)
    cfg["tr_methylation"]["cpg_str_bed"] = str(cpg_bed) if enable_cpg and cpg_bed else None

    return cfg 
