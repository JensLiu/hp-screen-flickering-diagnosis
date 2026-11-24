#!/usr/bin/env bash
# Switch the internal panel between 60 and 240 Hz repeatedly (each switch retrains the eDP link).
# Supported: sway, Hyprland. On GNOME change the refresh rate in Settings > Displays instead.
# Usage: ./toggle-refresh.sh [cycles] [seconds-at-240]
set -u
CYCLES=${1:-10}; HOLD=${2:-20}
LOG="$(dirname "$0")/toggle-$(date +%F_%H-%M-%S).log"
setmode() {  # setmode <Hz>
  local r=$([ "$1" = 60 ] && echo 60.001 || echo 240)
  if [ -n "${SWAYSOCK:-}" ]; then swaymsg output eDP-1 mode "2560x1600@${r}Hz" >/dev/null
  elif [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then hyprctl keyword monitor "eDP-1,2560x1600@${r},auto,1.25" >/dev/null
  else echo "Unsupported desktop (${XDG_CURRENT_DESKTOP:-?}). On GNOME use Settings > Displays > Refresh Rate."; exit 1; fi
}
echo "Logging to $LOG. Ctrl+C to stop (ends at 60 Hz)."
trap 'setmode 60; echo "$(date +%T.%3N) stopped, left at 60Hz" | tee -a "$LOG"; exit' INT
for i in $(seq 1 "$CYCLES"); do
  echo "$(date +%T.%3N) cycle $i -> 240Hz" | tee -a "$LOG"; setmode 240; sleep "$HOLD"
  echo "$(date +%T.%3N) cycle $i -> 60Hz"  | tee -a "$LOG"; setmode 60;  sleep 3
done
echo "$(date +%T.%3N) done, left at 60Hz" | tee -a "$LOG"
