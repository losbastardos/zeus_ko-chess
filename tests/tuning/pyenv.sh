#!/usr/bin/env bash
set -euo pipefail

# Numpy na NixOS: symlinknute libstdc++/libz v .venv/liblibs + LD_LIBRARY_PATH.
# Wrapper akceptuje aj formy typu: tests/tuning/pyenv.sh python3 -c "...".
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PY="$ROOT_DIR/.venv/bin/python"

if [[ ! -x "$VENV_PY" ]]; then
  echo "error: missing venv python: $VENV_PY" >&2
  exit 2
fi

export LD_LIBRARY_PATH="$ROOT_DIR/.venv/liblibs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if [[ $# -gt 0 && ( "${1}" == "python" || "${1}" == "python3" ) ]]; then
  shift
fi

exec "$VENV_PY" "$@"
