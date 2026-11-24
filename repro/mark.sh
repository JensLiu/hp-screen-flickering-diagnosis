#!/usr/bin/env bash
# Marker tool. Run in a terminal you can reach quickly.
#   ENTER alone   -> toggles: 1st press = "FLICKER START", next press = "FLICKER END" (an episode)
#   text + ENTER  -> phase label, e.g. "idle 240", "occt start 240", "occt stop", "occt start 60"
# Everything goes into the system journal with a precise timestamp, so the recorder picks it up.
# Known phase labels start a timer and pop up a desktop notification when the phase is over.
TIMER=""; FLICKERING=0
remind() {  # remind <seconds> <title> <body>
  [ -n "$TIMER" ] && kill "$TIMER" 2>/dev/null
  ( sleep "$1"; notify-send -u critical -t 0 "$2" "$3"; printf '\a\n>>> %s: %s\n' "$2" "$3" ) &
  TIMER=$!
  echo "             (reminder in $(( $1 / 60 )) min)"
}
trap '[ -n "$TIMER" ] && kill "$TIMER" 2>/dev/null; exit' INT TERM EXIT

echo "ENTER = flicker START, ENTER again = flicker END.  Type a phase label + ENTER.  Ctrl+C to quit."
echo "Phases: 'idle 240' (5 min) -> 'occt start 240' (10 min) -> 'occt stop' (3 min) -> optional 'occt start 60' (10 min)"
while IFS= read -r line; do
  if [ -z "$line" ]; then
    if [ $FLICKERING -eq 0 ]; then
      FLICKERING=1; logger -t flicker-mark "FLICKER START"
      echo "$(date +%T.%3N)  *** FLICKER START ***  (press ENTER again when it stops)"
    else
      FLICKERING=0; logger -t flicker-mark "FLICKER END"
      echo "$(date +%T.%3N)  --- flicker end ---"
    fi
    continue
  fi
  logger -t flicker-phase "$line"; echo "$(date +%T.%3N)  phase: $line"
  case "$line" in
    idle*)            remind 300 "Phase A done" "Start the OCCT GPU test, then type: occt start 240" ;;
    "occt start 60"*) remind 600 "Phase D done" "Stop OCCT, type: occt stop — then stop the recorder (Ctrl+C)" ;;
    "occt start"*)    remind 600 "Phase B done" "Stop OCCT, then type: occt stop" ;;
    "occt stop"*)     remind 180 "Phase C done" "Optional: set the panel to 60 Hz (GNOME: Settings > Displays > Refresh Rate), start OCCT, type: occt start 60 — or stop the recorder" ;;
  esac
done
