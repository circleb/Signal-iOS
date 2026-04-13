#!/usr/bin/env zsh
# Sync upstream Signal project metadata into HCP: PBXGroup layout, then PBXFileReference bodies.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/Scripts/sync_ssk_groups_from_signal_pbx.py"
python3 "$ROOT/Scripts/sync_pbx_file_refs_from_signal.py" "$@"
