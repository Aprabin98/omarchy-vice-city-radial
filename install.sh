#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
BINDINGS="$CONFIG_HOME/hypr/bindings.lua"
COMMAND="$BIN_DIR/omarchy-launcher"
QS="${QUICKSHELL_BIN:-qs}"

command -v "$QS" >/dev/null || { echo "Quickshell is required (install it with your Omarchy system packages)." >&2; exit 1; }
mkdir -p "$BIN_DIR" "$CONFIG_HOME/omarchy-launcher" "$(dirname "$BINDINGS")"

if [[ -e "$COMMAND" && ! -L "$COMMAND" ]]; then
  echo "Refusing to replace existing file: $COMMAND" >&2
  exit 1
fi
if [[ -L "$COMMAND" && "$(readlink -f "$COMMAND")" != "$ROOT/omarchy-launcher" ]]; then
  echo "Refusing to replace a launcher owned by another installation." >&2
  exit 1
fi

TEMP_BINDINGS="$(mktemp "${BINDINGS}.XXXXXX")"
trap 'rm -f "$TEMP_BINDINGS"' EXIT
if [[ -f "$BINDINGS" ]]; then
  awk '
    /^-- BEGIN omarchy-launcher / || /^-- BEGIN vice-city-radial / { skip=1; next }
    skip && (/^-- END omarchy-launcher$/ || /^-- END vice-city-radial$/) { skip=0; next }
    !skip {
      if ($0 ~ /^[[:space:]]*o\.bind\(["\047]ALT \+ SPACE["\047]/) conflict=1
      print
    }
    END { if (conflict) exit 42 }
  ' "$BINDINGS" > "$TEMP_BINDINGS" || {
    status=$?
    if [[ "$status" -eq 42 ]]; then
      echo "ALT + SPACE is already assigned outside the old launcher binding; resolve the conflict first." >&2
    else
      echo "Could not read existing Hyprland bindings." >&2
    fi
    exit "$status"
  }
  if ! awk '/^-- BEGIN (omarchy-launcher|vice-city-radial) / { found=1 } END { exit !found }' "$BINDINGS"; then
    backup="$BINDINGS.omarchy-launcher.bak"
    [[ -e "$backup" ]] && backup="$BINDINGS.omarchy-launcher.$(date +%Y%m%d-%H%M%S).bak"
    cp -a "$BINDINGS" "$backup"
  fi
else
  printf '%s\n' '-- Personal Hyprland bindings' > "$TEMP_BINDINGS"
fi
{
  cat "$TEMP_BINDINGS"
  printf '\n%s\n' \
    '-- BEGIN omarchy-launcher (managed by omarchy-launcher/install.sh)' \
    "o.bind(\"ALT + SPACE\", \"Omarchy Launcher\", \"$COMMAND\")" \
    '-- END omarchy-launcher'
} > "$TEMP_BINDINGS.new"
mv "$TEMP_BINDINGS.new" "$BINDINGS"
rm -f "$TEMP_BINDINGS"
trap - EXIT

if [[ -L "$BIN_DIR/vice-city-radial" && "$(readlink -f "$BIN_DIR/vice-city-radial")" == "$ROOT/vice-city-radial" ]]; then
  rm "$BIN_DIR/vice-city-radial"
fi
ln -sfn "$ROOT/omarchy-launcher" "$COMMAND"
if [[ ! -e "$CONFIG_HOME/omarchy-launcher/config.json" ]]; then
  install -m 600 "$ROOT/config.json" "$CONFIG_HOME/omarchy-launcher/config.json"
fi
chmod +x "$ROOT/omarchy-launcher" "$ROOT/install.sh" "$ROOT/uninstall.sh"
echo "Installed Omarchy Launcher on Alt + Space. Reload Hyprland with: hyprctl reload"
echo "Settings: $CONFIG_HOME/omarchy-launcher/config.json"
