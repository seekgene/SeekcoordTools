#!/usr/bin/env bash
set -euo pipefail

env_name="${1:-seekcoord18}"
if ! command -v conda >/dev/null 2>&1; then
  echo "ERROR: conda was not found." >&2
  exit 1
fi

conda run -n "$env_name" python --version
conda run -n "$env_name" python -c 'import tensorflow, stardist, csbdeep; print("tensorflow=" + tensorflow.__version__); print("stardist=" + stardist.__version__); print("csbdeep=" + csbdeep.__version__)'
conda run -n "$env_name" bash -lc 'command -v STAR; command -v featureCounts; command -v samtools; command -v cutadapt; seekcoord --help >/dev/null; seekcoord rna binSegment --help >/dev/null'
echo "SeekcoordTools command and dependency verification passed."
