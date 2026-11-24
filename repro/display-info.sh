#!/usr/bin/env bash
# Desktop-independent helpers, sourced by record-session.sh and monitor-load.sh.
# Supports GNOME (Mutter D-Bus), sway (swaymsg) and Hyprland (hyprctl). Prints "unknown" otherwise.

# Name and version of the running desktop/compositor.
desktop_info() {
  local d="${XDG_CURRENT_DESKTOP:-unknown}" v=""
  if [ -n "${SWAYSOCK:-}" ] && command -v swaymsg >/dev/null; then
    v="sway $(swaymsg -t get_version 2>/dev/null | grep -oP '"human_readable": "\K[^"]+')"
  elif [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null; then
    v="$(hyprctl version 2>/dev/null | head -1)"
  elif command -v gnome-shell >/dev/null && [[ "$d" == *GNOME* ]]; then
    v="$(gnome-shell --version 2>/dev/null)"
  fi
  echo "$d ${v} (session: ${XDG_SESSION_TYPE:-unknown})"
}

# Internal panel (eDP) mode as "WIDTHxHEIGHT@REFRESH", refresh rounded to whole Hz.
panel_mode() {
  if [ -n "${SWAYSOCK:-}" ] && command -v swaymsg >/dev/null; then
    swaymsg -t get_outputs 2>/dev/null | python3 -c '
import json,sys
for o in json.load(sys.stdin):
    if o["name"].startswith("eDP"):
        m=o["current_mode"]; print("%dx%d@%d" % (m["width"], m["height"], round(m["refresh"]/1000))); break
else: print("unknown")'
  elif [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null; then
    hyprctl monitors -j 2>/dev/null | python3 -c '
import json,sys
for o in json.load(sys.stdin):
    if o["name"].startswith("eDP"):
        print("%dx%d@%d" % (o["width"], o["height"], round(o["refreshRate"]))); break
else: print("unknown")'
  elif command -v gdbus >/dev/null && gdbus introspect --session --dest org.gnome.Mutter.DisplayConfig \
         --object-path /org/gnome/Mutter/DisplayConfig >/dev/null 2>&1; then
    # GNOME/Mutter: GetCurrentState lists every mode; the current one carries 'is-current': <true>.
    gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
      --method org.gnome.Mutter.DisplayConfig.GetCurrentState 2>/dev/null | python3 -c '
import re,sys
s=sys.stdin.read()
# split per monitor: (( "eDP-1", vendor, product, serial ), [modes...], {props})
for mon in re.split(r"\(\(\x27", s)[1:]:
    if not mon.startswith("eDP"): continue
    for m in re.finditer(r"\(\x27[^\x27]+\x27, (\d+), (\d+), ([\d.]+), [^{]*?\{([^}]*)\}", mon):
        if "\x27is-current\x27: <true>" in m.group(4):
            print("%sx%s@%d" % (m.group(1), m.group(2), round(float(m.group(3))))); sys.exit()
print("unknown")'
  else
    echo unknown
  fi
}

# Just the refresh rate in Hz (or empty).
panel_refresh() { panel_mode | grep -oP '@\K[0-9]+'; }
