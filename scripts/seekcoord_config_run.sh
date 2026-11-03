#!/usr/bin/env bash
set -euo pipefail

# Run SeekcoordTools from a per-job shell config file.
# This script is intended for production callers such as PMSystem: the caller
# writes one small job.env file, and this adapter translates it to the existing
# SeekcoordTools_run.sh workflow arguments.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNNER="${REPO_DIR}/SeekcoordTools_run.sh"

show_help() {
  cat <<'EOF'
=====================================================================
SeekcoordTools CONFIG Runner
=====================================================================

USAGE:
  bash SeekcoordTools_run.sh CONFIG <job.env> [--dry-run]
  bash SeekcoordTools_run.sh CONFIG --config <job.env> [--dry-run]

CONFIG FORMAT:
  Shell env format. Required fields:

    SEEKCOORD_RUN_WORKFLOW=FF              # FF, FFPE, SN, or reanalysis
    SEEKCOORD_CHIP_NUMBER=ST110250_A1
    SEEKCOORD_CASNO=case_name
    SEEKCOORD_CHEMISTRY=BBV2.4
    SEEKCOORD_SPECIES=Mus_musculus
    SEEKCOORD_METHOD=gene_expr             # gene_expr, image, ssDNA, or HE
    SEEKCOORD_MODE=strna                   # strna or scrna

  Optional fields:

    SEEKCOORD_SAMPLE_NAME=sample_label
    SEEKCOORD_THREAD=32
    SEEKCOORD_BIN=50
    SEEKCOORD_PIXEL_SIZE=0.5
    SEEKCOORD_CELL_NUM=50000
    SEEKCOORD_FASTQ_NAME=ST110250_A1
    SEEKCOORD_FASTQ_DIR=/path/to/fastq
    SEEKCOORD_MASK_DIR=/path/to/ST_mask
    SEEKCOORD_IMAGE_DIR=/path/to/images
    SEEKCOORD_REFERENCE_DIR=/path/to/reference

  Boolean options accept 1/0, true/false, yes/no, on/off:

    SEEKCOORD_RESUME_EXISTING=1
    SEEKCOORD_RESOLVE_MULTIGENE_UMI=1
    SEEKCOORD_GENE_MASK_FILTER=1
    SEEKCOORD_ENABLE_CAVITY_FILTER=1
    SEEKCOORD_CAVITY_APPLY=1
    SEEKCOORD_ENABLE_STARDIST_CELL_SEGMENT=1

  Extra arguments can be appended as a bash array:

    SEEKCOORD_EXTRA_ARGS=(--cavity-mask-preset adipose)

NOTES:
  Machine/account-level paths still belong in configs/seekcoord.env or
  SEEKCOORD_CONFIG. Per-job files should contain sample-level parameters.
EOF
}

die() {
  echo "ERROR: $*" >&2
  echo "Run 'bash ${REPO_DIR}/SeekcoordTools_run.sh CONFIG --help' for usage." >&2
  exit 1
}

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

truthy() {
  case "$(lowercase "${1:-}")" in
    1|true|yes|y|on|enable|enabled)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

get_first() {
  local name value
  for name in "$@"; do
    value="${!name-}"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done
  return 1
}

require_value() {
  local label="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    die "Missing required config value: ${label}"
  fi
}

append_value_arg() {
  local option="$1"
  local value="$2"
  if [[ -n "$value" ]]; then
    target_args+=("$option" "$value")
  fi
}

append_flag_arg() {
  local option="$1"
  local value="$2"
  if truthy "$value"; then
    target_args+=("$option")
  fi
}

append_extra_args() {
  local declaration=""
  if declaration="$(declare -p SEEKCOORD_EXTRA_ARGS 2>/dev/null)"; then
    if [[ "$declaration" == declare\ -a* || "$declaration" == declare\ -x\ -a* ]]; then
      local -n extra_array=SEEKCOORD_EXTRA_ARGS
      target_args+=("${extra_array[@]}")
      return 0
    fi
  fi

  local extra="${SEEKCOORD_EXTRA_ARGS:-${EXTRA_ARGS:-}}"
  if [[ -n "$extra" ]]; then
    local extra_words=()
    read -r -a extra_words <<< "$extra"
    target_args+=("${extra_words[@]}")
  fi
}

export_if_set() {
  local env_name="$1"
  local value="$2"
  if [[ -n "$value" ]]; then
    export "${env_name}=${value}"
  fi
}

quote_command() {
  printf '%q ' "$@"
  printf '\n'
}

config_file=""
dry_run=0

while (($# > 0)); do
  case "$1" in
    --help|-h)
      show_help
      exit 0
      ;;
    --config|-c)
      [[ $# -ge 2 ]] || die "Option '$1' requires a config file"
      config_file="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --)
      shift
      if (($# > 0)); then
        [[ -z "$config_file" ]] || die "Multiple config files were provided"
        config_file="$1"
        shift
      fi
      [[ $# -eq 0 ]] || die "Unexpected arguments after config file: $*"
      ;;
    -*)
      die "Unknown CONFIG option: $1"
      ;;
    *)
      [[ -z "$config_file" ]] || die "Multiple config files were provided: '$config_file' and '$1'"
      config_file="$1"
      shift
      ;;
  esac
done

[[ -n "$config_file" ]] || die "Missing job config file"
[[ -f "$config_file" ]] || die "Job config file not found: $config_file"

config_dir="$(cd "$(dirname "$config_file")" && pwd)"
config_file="${config_dir}/$(basename "$config_file")"
export SEEKCOORD_JOB_CONFIG="$config_file"
export SEEKCOORD_JOB_CONFIG_DIR="$config_dir"

set -a
# shellcheck source=/dev/null
source "$config_file"
set +a

if truthy "${SEEKCOORD_DRY_RUN:-${DRY_RUN:-0}}"; then
  dry_run=1
fi

workflow="$(get_first SEEKCOORD_RUN_WORKFLOW RUN_WORKFLOW WORKFLOW PIPELINE || true)"
sample_name="$(get_first SEEKCOORD_SAMPLE_NAME SAMPLE_NAME SAMPLE_LABEL || true)"
chip_number="$(get_first SEEKCOORD_CHIP_NUMBER CHIP_NUMBER CHIP SAMPLE || true)"
casno="$(get_first SEEKCOORD_CASNO CASNO CASE_NO CASE PROJECT || true)"
chemistry="$(get_first SEEKCOORD_CHEMISTRY CHEMISTRY || true)"
species="$(get_first SEEKCOORD_SPECIES SPECIES || true)"
method="$(get_first SEEKCOORD_METHOD METHOD || true)"
mode="$(get_first SEEKCOORD_MODE MODE || true)"

require_value "SEEKCOORD_RUN_WORKFLOW" "$workflow"
require_value "SEEKCOORD_CHIP_NUMBER" "$chip_number"
require_value "SEEKCOORD_CASNO" "$casno"
require_value "SEEKCOORD_CHEMISTRY" "$chemistry"
require_value "SEEKCOORD_SPECIES" "$species"
require_value "SEEKCOORD_METHOD" "$method"
require_value "SEEKCOORD_MODE" "$mode"

target_args=()
if [[ -n "$sample_name" ]]; then
  target_args+=("$sample_name" "$chip_number" "$casno" "$chemistry" "$species" "$method" "$mode")
else
  target_args+=("$chip_number" "$casno" "$chemistry" "$species" "$method" "$mode")
fi

append_value_arg "--reference_dir" "$(get_first SEEKCOORD_REFERENCE_DIR REFERENCE_DIR || true)"
append_value_arg "--mask_dir" "$(get_first SEEKCOORD_MASK_DIR MASK_DIR || true)"
append_value_arg "--image_dir" "$(get_first SEEKCOORD_IMAGE_DIR IMAGE_DIR || true)"
append_value_arg "--thread" "$(get_first SEEKCOORD_THREAD THREAD || true)"
append_value_arg "--bin" "$(get_first SEEKCOORD_BIN BIN || true)"
append_value_arg "--cell_num" "$(get_first SEEKCOORD_CELL_NUM CELL_NUM || true)"
append_value_arg "--pixelSize" "$(get_first SEEKCOORD_PIXEL_SIZE PIXEL_SIZE PIXELSIZE || true)"

  case "$(lowercase "$workflow")" in
    ff|fresh|fresh-frozen|fresh_frozen|standard|std|normal|ffpe|probe|panel|targeted|targeted-panel|targeted_panel|wtpanel|sn|single-nucleus|single_nucleus|snrna|sn-rna|sn_rna)
    append_value_arg "--fastq_dir" "$(get_first SEEKCOORD_FASTQ_DIR FASTQ_DIR || true)"
    append_value_arg "--fastq_name" "$(get_first SEEKCOORD_FASTQ_NAME FASTQ_NAME || true)"
    append_value_arg "--insertR2" "$(get_first SEEKCOORD_INSERT_R2 INSERT_R2 INSERTR2 || true)"
    append_value_arg "--bbv4-strna-barcode-mismatch" "$(get_first SEEKCOORD_BBV4_STRNA_BARCODE_MISMATCH BBV4_STRNA_BARCODE_MISMATCH BBV4_STRNA_MISMATCH || true)"
    append_value_arg "--star-match-min" "$(get_first SEEKCOORD_STAR_MATCH_MIN STAR_MATCH_MIN || true)"
    append_value_arg "--star-match-ratio" "$(get_first SEEKCOORD_STAR_MATCH_RATIO STAR_MATCH_RATIO || true)"
    append_value_arg "--star-score-ratio" "$(get_first SEEKCOORD_STAR_SCORE_RATIO STAR_SCORE_RATIO || true)"
    append_value_arg "--star-multimap" "$(get_first SEEKCOORD_STAR_MULTIMAP STAR_MULTIMAP || true)"
    append_flag_arg "--resume-existing" "$(get_first SEEKCOORD_RESUME_EXISTING RESUME_EXISTING || true)"
    append_flag_arg "--resolve-multigene-umi" "$(get_first SEEKCOORD_RESOLVE_MULTIGENE_UMI RESOLVE_MULTIGENE_UMI || true)"
    ;;
esac

case "$(lowercase "$workflow")" in
  ffpe|probe|panel|targeted|targeted-panel|targeted_panel|wtpanel)
    append_value_arg "--cell-cluster-resolution" "$(get_first SEEKCOORD_CELL_CLUSTER_RESOLUTION CELL_CLUSTER_RESOLUTION || true)"
    append_value_arg "--cell-n-neighbors" "$(get_first SEEKCOORD_CELL_N_NEIGHBORS CELL_N_NEIGHBORS || true)"
    append_value_arg "--cell-n-pcs" "$(get_first SEEKCOORD_CELL_N_PCS CELL_N_PCS || true)"
    ;;
esac

case "$(lowercase "$workflow")" in
  sn|single-nucleus|single_nucleus|snrna|sn-rna|sn_rna)
    export_if_set SEEKCOORD_SN_BARCODE_LOWNUM "$(get_first SEEKCOORD_SN_BARCODE_LOWNUM SN_BARCODE_LOWNUM || true)"
    export_if_set SEEKCOORD_SN_CUTADAPT_MIN_LENGTH "$(get_first SEEKCOORD_SN_CUTADAPT_MIN_LENGTH SN_CUTADAPT_MIN_LENGTH || true)"
    export_if_set SEEKCOORD_SN_CUTADAPT_NEXTSEQ_TRIM "$(get_first SEEKCOORD_SN_CUTADAPT_NEXTSEQ_TRIM SN_CUTADAPT_NEXTSEQ_TRIM || true)"
    export_if_set SEEKCOORD_SN_CUTADAPT_OVERLAP "$(get_first SEEKCOORD_SN_CUTADAPT_OVERLAP SN_CUTADAPT_OVERLAP || true)"
    export_if_set SEEKCOORD_SN_CUTADAPT_PARAM "$(get_first SEEKCOORD_SN_CUTADAPT_PARAM SN_CUTADAPT_PARAM || true)"
    export_if_set SEEKCOORD_SN_STAR_MULTIMAP "$(get_first SEEKCOORD_SN_STAR_MULTIMAP SN_STAR_MULTIMAP || true)"
    export_if_set SEEKCOORD_SN_STRNA_STAR_MATCH_MIN "$(get_first SEEKCOORD_SN_STRNA_STAR_MATCH_MIN SN_STRNA_STAR_MATCH_MIN || true)"
    export_if_set SEEKCOORD_SN_STRNA_STAR_MATCH_RATIO "$(get_first SEEKCOORD_SN_STRNA_STAR_MATCH_RATIO SN_STRNA_STAR_MATCH_RATIO || true)"
    export_if_set SEEKCOORD_SN_STRNA_STAR_SCORE_RATIO "$(get_first SEEKCOORD_SN_STRNA_STAR_SCORE_RATIO SN_STRNA_STAR_SCORE_RATIO || true)"
    export_if_set SEEKCOORD_SN_SCRNA_STAR_MATCH_MIN "$(get_first SEEKCOORD_SN_SCRNA_STAR_MATCH_MIN SN_SCRNA_STAR_MATCH_MIN || true)"
    export_if_set SEEKCOORD_SN_SCRNA_STAR_MATCH_RATIO "$(get_first SEEKCOORD_SN_SCRNA_STAR_MATCH_RATIO SN_SCRNA_STAR_MATCH_RATIO || true)"
    export_if_set SEEKCOORD_SN_SCRNA_STAR_SCORE_RATIO "$(get_first SEEKCOORD_SN_SCRNA_STAR_SCORE_RATIO SN_SCRNA_STAR_SCORE_RATIO || true)"
    export_if_set SEEKCOORD_SN_FEATURE_TYPE "$(get_first SEEKCOORD_SN_FEATURE_TYPE SN_FEATURE_TYPE || true)"
    export_if_set SEEKCOORD_SN_FEATURECOUNTS_PARAM "$(get_first SEEKCOORD_SN_FEATURECOUNTS_PARAM SN_FEATURECOUNTS_PARAM || true)"
    export_if_set SEEKCOORD_SN_RESOLVE_MULTIGENE_UMI "$(get_first SEEKCOORD_SN_RESOLVE_MULTIGENE_UMI SN_RESOLVE_MULTIGENE_UMI || true)"
    ;;
esac

case "$(lowercase "$workflow")" in
  reanalysis|reanalyze|reanalyse|re|manual|manual-registration|manual_registration)
    append_value_arg "--workspace" "$(get_first SEEKCOORD_WORKSPACE WORKSPACE || true)"
    append_value_arg "--genomeDir" "$(get_first SEEKCOORD_GENOME_DIR GENOME_DIR GENOMEDIR || true)"
    append_value_arg "--sampledir" "$(get_first SEEKCOORD_SAMPLEDIR SAMPLEDIR SAMPLE_DIR || true)"
    append_value_arg "--src_dir" "$(get_first SEEKCOORD_REANALYSIS_SRC_DIR REANALYSIS_SRC_DIR || true)"
    append_flag_arg "--no-clean" "$(get_first SEEKCOORD_NO_CLEAN NO_CLEAN || true)"
    append_flag_arg "--skip-binsegment" "$(get_first SEEKCOORD_SKIP_BINSEGMENT SKIP_BINSEGMENT || true)"
    append_flag_arg "--skip-analysis" "$(get_first SEEKCOORD_SKIP_ANALYSIS SKIP_ANALYSIS || true)"
    append_flag_arg "--skip-report" "$(get_first SEEKCOORD_SKIP_REPORT SKIP_REPORT || true)"
    ;;
esac

append_flag_arg "--gene-mask-filter" "$(get_first SEEKCOORD_GENE_MASK_FILTER GENE_MASK_FILTER || true)"

append_flag_arg "--enable-cavity-filter" "$(get_first SEEKCOORD_ENABLE_CAVITY_FILTER ENABLE_CAVITY_FILTER || true)"
append_flag_arg "--disable-cavity-filter" "$(get_first SEEKCOORD_DISABLE_CAVITY_FILTER DISABLE_CAVITY_FILTER || true)"
append_flag_arg "--skip-cavity-filter" "$(get_first SEEKCOORD_SKIP_CAVITY_FILTER SKIP_CAVITY_FILTER || true)"
append_value_arg "--cavity-bins" "$(get_first SEEKCOORD_CAVITY_BINS CAVITY_BINS || true)"
append_value_arg "--cavity-mask-preset" "$(get_first SEEKCOORD_CAVITY_MASK_PRESET CAVITY_MASK_PRESET || true)"
append_flag_arg "--cavity-apply" "$(get_first SEEKCOORD_CAVITY_APPLY CAVITY_APPLY || true)"
append_flag_arg "--cavity-dry-run" "$(get_first SEEKCOORD_CAVITY_DRY_RUN CAVITY_DRY_RUN || true)"
append_flag_arg "--cavity-skip-qc-images" "$(get_first SEEKCOORD_CAVITY_SKIP_QC_IMAGES CAVITY_SKIP_QC_IMAGES || true)"

append_flag_arg "--enable-stardist-cell-segment" "$(get_first SEEKCOORD_ENABLE_STARDIST_CELL_SEGMENT ENABLE_STARDIST_CELL_SEGMENT ENABLE_STARDIST || true)"
append_flag_arg "--disable-stardist-cell-segment" "$(get_first SEEKCOORD_DISABLE_STARDIST_CELL_SEGMENT DISABLE_STARDIST_CELL_SEGMENT DISABLE_STARDIST || true)"
append_value_arg "--stardist-python" "$(get_first SEEKCOORD_STARDIST_PYTHON STARDIST_PYTHON || true)"
append_value_arg "--stardist-labels" "$(get_first SEEKCOORD_STARDIST_LABELS STARDIST_LABELS || true)"
append_value_arg "--stardist-model" "$(get_first SEEKCOORD_STARDIST_MODEL STARDIST_MODEL || true)"
append_value_arg "--stardist-model-dir" "$(get_first SEEKCOORD_STARDIST_MODEL_DIR STARDIST_MODEL_DIR || true)"
append_value_arg "--stardist-prob-thresh" "$(get_first SEEKCOORD_STARDIST_PROB_THRESH STARDIST_PROB_THRESH || true)"
append_value_arg "--stardist-nms-thresh" "$(get_first SEEKCOORD_STARDIST_NMS_THRESH STARDIST_NMS_THRESH || true)"
append_value_arg "--stardist-max-dim" "$(get_first SEEKCOORD_STARDIST_MAX_DIM STARDIST_MAX_DIM || true)"
append_value_arg "--stardist-scale" "$(get_first SEEKCOORD_STARDIST_SCALE STARDIST_SCALE || true)"
append_value_arg "--stardist-n-tiles" "$(get_first SEEKCOORD_STARDIST_N_TILES STARDIST_N_TILES || true)"
append_value_arg "--stardist-expand-pixels" "$(get_first SEEKCOORD_STARDIST_EXPAND_PIXELS STARDIST_EXPAND_PIXELS || true)"
append_value_arg "--stardist-min-umi" "$(get_first SEEKCOORD_STARDIST_MIN_UMI STARDIST_MIN_UMI || true)"
append_value_arg "--stardist-min-genes" "$(get_first SEEKCOORD_STARDIST_MIN_GENES STARDIST_MIN_GENES || true)"
append_flag_arg "--stardist-skip-counts" "$(get_first SEEKCOORD_STARDIST_SKIP_COUNTS STARDIST_SKIP_COUNTS || true)"

append_extra_args

cmd=(bash "$RUNNER" "$workflow" "${target_args[@]}")
if [[ "$dry_run" == "1" ]]; then
  cmd+=(--dry-run)
fi

echo "==============================================="
echo "SeekcoordTools CONFIG Runner"
echo "==============================================="
echo "Config:     $config_file"
echo "Workflow:   $workflow"
echo "Chip:       $chip_number"
echo "Case:       $casno"
echo "Chemistry:  $chemistry"
echo "Species:    $species"
echo "Method:     $method"
echo "Mode:       $mode"
echo "Dry Run:    $dry_run"
echo "Command:"
quote_command "${cmd[@]}"
echo "==============================================="

exec "${cmd[@]}"
