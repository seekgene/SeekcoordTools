#!/usr/bin/env bash

# Shared environment interface for SeekcoordTools v1.8 shell entrypoints.
# Source this file; do not execute it directly.

SEEKCOORD_REPO_DIR="${SEEKCOORD_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "${SEEKCOORD_REPO_DIR}/scripts/seekcoord_config.sh"
seekcoord_config_load

seekcoord_env_try_conda_root() {
  local candidate="${1:-}"
  if [[ -z "${SEEKCOORD_CONDA_ROOT:-}" && -n "$candidate" && -d "$candidate" ]]; then
    SEEKCOORD_CONDA_ROOT="$candidate"
  fi
}

seekcoord_env_init_defaults() {
  SEEKCOORD_ENV_NAME="${SEEKCOORD_ENV_NAME:-seekcoord18}"
  SEEKCOORD_CONDA_ROOT="${SEEKCOORD_CONDA_ROOT:-}"

  if [[ -z "$SEEKCOORD_CONDA_ROOT" ]]; then
    if [[ -n "${CONDA_EXE:-}" ]]; then
      seekcoord_env_try_conda_root "$(cd "$(dirname "${CONDA_EXE}")/.." && pwd)"
    fi
    seekcoord_env_try_conda_root "${MAMBA_ROOT_PREFIX:-}"
    if [[ -z "$SEEKCOORD_CONDA_ROOT" ]] && command -v conda >/dev/null 2>&1; then
      seekcoord_env_try_conda_root "$(conda info --base 2>/dev/null || true)"
    fi
    seekcoord_env_try_conda_root "$HOME/miniforge3"
    seekcoord_env_try_conda_root "$HOME/mambaforge"
    seekcoord_env_try_conda_root "$HOME/miniconda3"
    seekcoord_env_try_conda_root "$HOME/anaconda3"
  fi

  if [[ -z "${SEEKCOORD_ENV_PREFIX:-}" && -n "$SEEKCOORD_CONDA_ROOT" ]]; then
    SEEKCOORD_ENV_PREFIX="${SEEKCOORD_CONDA_ROOT}/envs/${SEEKCOORD_ENV_NAME}"
  fi

  SEEKCOORD_AUTO_ACTIVATE="${SEEKCOORD_AUTO_ACTIVATE:-0}"
  SEEKCOORD_USE_ENV_PATH="${SEEKCOORD_USE_ENV_PATH:-0}"
}

seekcoord_env_is_help_request() {
  for arg in "$@"; do
    case "$arg" in
      --help|-h)
        return 0
        ;;
    esac
  done
  return 1
}

seekcoord_env_activate() {
  if [[ -z "${SEEKCOORD_CONDA_ROOT:-}" ]]; then
    echo "ERROR: SEEKCOORD_CONDA_ROOT is not set and conda root was not found"
    exit 1
  fi

  local conda_sh="${SEEKCOORD_CONDA_ROOT}/etc/profile.d/conda.sh"
  if [[ ! -f "$conda_sh" ]]; then
    echo "ERROR: conda.sh not found: ${conda_sh}"
    exit 1
  fi

  source "$conda_sh"
  conda activate "$SEEKCOORD_ENV_NAME" || {
    echo "ERROR: Failed to activate conda env '${SEEKCOORD_ENV_NAME}'"
    exit 1
  }

  if [[ -z "${SEEKCOORD_ENV_PREFIX:-}" ]]; then
    SEEKCOORD_ENV_PREFIX="${CONDA_PREFIX:-}"
  fi
}

seekcoord_env_export_runtime() {
  if [[ -n "${SEEKCOORD_ENV_PREFIX:-}" && -x "${SEEKCOORD_ENV_PREFIX}/bin/python" ]]; then
    export STARDIST_PYTHON="${STARDIST_PYTHON:-${SEEKCOORD_ENV_PREFIX}/bin/python}"
  fi

  if [[ -n "${SEEKCOORD_ENV_PREFIX:-}" && -d "${SEEKCOORD_ENV_PREFIX}/lib" ]]; then
    case ":${LD_LIBRARY_PATH:-}:" in
      *":${SEEKCOORD_ENV_PREFIX}/lib:"*) ;;
      *) export LD_LIBRARY_PATH="${SEEKCOORD_ENV_PREFIX}/lib:${LD_LIBRARY_PATH:-}" ;;
    esac
  fi

  if [[ "$SEEKCOORD_USE_ENV_PATH" == "1" && -n "${SEEKCOORD_ENV_PREFIX:-}" && -d "${SEEKCOORD_ENV_PREFIX}/bin" ]]; then
    case ":${PATH:-}:" in
      *":${SEEKCOORD_ENV_PREFIX}/bin:"*) ;;
      *) export PATH="${SEEKCOORD_ENV_PREFIX}/bin:${PATH:-}" ;;
    esac
  fi

  export PYTHONNOUSERSITE="${PYTHONNOUSERSITE:-1}"
  export MPLCONFIGDIR="${MPLCONFIGDIR:-${TMPDIR:-/tmp}/seekcoord_mplconfig}"
  export NUMBA_CACHE_DIR="${NUMBA_CACHE_DIR:-${TMPDIR:-/tmp}/seekcoord_numba_cache}"

  if [[ "${SEEKCOORD_SKIP_ENV_MKDIR:-0}" != "1" ]]; then
    mkdir -p "$MPLCONFIGDIR" "$NUMBA_CACHE_DIR"
  fi
}

seekcoord_env_setup() {
  seekcoord_env_init_defaults

  if [[ "$SEEKCOORD_AUTO_ACTIVATE" == "1" ]] && ! seekcoord_env_is_help_request "$@"; then
    if [[ "${CONDA_DEFAULT_ENV:-}" != "$SEEKCOORD_ENV_NAME" ]]; then
      seekcoord_env_activate
    elif [[ -z "${SEEKCOORD_ENV_PREFIX:-}" ]]; then
      SEEKCOORD_ENV_PREFIX="${CONDA_PREFIX:-}"
    fi
  fi

  if [[ -z "${SEEKCOORD_ENV_PREFIX:-}" && -n "${CONDA_PREFIX:-}" && "${CONDA_DEFAULT_ENV:-}" == "$SEEKCOORD_ENV_NAME" ]]; then
    SEEKCOORD_ENV_PREFIX="$CONDA_PREFIX"
  fi

  seekcoord_env_export_runtime
}

seekcoord_env_summary() {
  cat <<EOF
SEEKCOORD_REPO_DIR=${SEEKCOORD_REPO_DIR:-}
SEEKCOORD_CONFIG_FILE=${SEEKCOORD_CONFIG_FILE:-}
SEEKCOORD_ENV_NAME=${SEEKCOORD_ENV_NAME:-}
SEEKCOORD_ENV_PREFIX=${SEEKCOORD_ENV_PREFIX:-}
SEEKCOORD_AUTO_ACTIVATE=${SEEKCOORD_AUTO_ACTIVATE:-0}
SEEKCOORD_USE_ENV_PATH=${SEEKCOORD_USE_ENV_PATH:-0}
STARDIST_PYTHON=${STARDIST_PYTHON:-}
PYTHONNOUSERSITE=${PYTHONNOUSERSITE:-}
MPLCONFIGDIR=${MPLCONFIGDIR:-}
NUMBA_CACHE_DIR=${NUMBA_CACHE_DIR:-}
EOF
}
