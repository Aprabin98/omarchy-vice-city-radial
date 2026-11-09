#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
BINDINGS="$CONFIG_HOME/hypr/bindings.lua"

if [[ -L "$BIN_DIR/omarchy-launcher" && "$(readlink -f "$BIN_DIR/omarchy-launcher")" == "$ROOT/omarchy-launcher" ]]; then
  rm "$BIN_DIR/omarchy-launcher"
fi
if [[ -f "$BINDINGS" ]]; then
  tmp="$(mktemp "${BINDINGS}.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  awk '
    /^-- BEGIN omarchy-launcher / || /^-- BEGIN vice-city-radial / { skip=1; next }
    skip && (/^-- END omarchy-launcher$/ || /^-- END vice-city-radial$/) { skip=0; next }
    !skip { print }
  ' "$BINDINGS" > "$tmp"
  cat "$tmp" > "$BINDINGS"
  rm "$tmp"
  trap - EXIT
fi
if [[ -L "$BIN_DIR/vice-city-radial" && "$(readlink -f "$BIN_DIR/vice-city-radial")" == "$ROOT/vice-city-radial" ]]; then
  rm "$BIN_DIR/vice-city-radial"
fi
echo "Uninstalled Omarchy Launcher; project files and user settings were kept."
