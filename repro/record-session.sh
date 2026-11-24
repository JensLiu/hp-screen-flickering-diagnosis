#!/usr/bin/env bash
# Clean recording session for the eDP flicker investigation. Works under GNOME, sway and Hyprland.
# Creates runs/<timestamp>/ with:
#   meta.txt     - system state at start and end (boot id, kernel cmdline, desktop, panel mode, versions)
#   kernel.log   - kernel log (incl. drm DP debug) for this session only
#   journal.log  - full journal for this session only (includes flicker-mark / flicker-phase entries)
#   monitor.csv  - ~1 Hz: power, battery, temps, NVIDIA GPU load, refresh, compositor errors, link-loss count
# Stops on Ctrl+C / SIGTERM, when runs/<timestamp>/STOP exists, or after MAX_MIN minutes.
# Usage: record-session.sh [max_minutes] [output_base_dir]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/display-info.sh"
MAX_MIN=${1:-90}
BASE="${2:-$(cd "$HERE/.." && pwd)/runs}"
RUN="$BASE/$(date +%F_%H-%M-%S)"; mkdir -p "$RUN"
BAT=/sys/class/power_supply/BAT0
AC=$(for p in /sys/class/power_supply/*; do [ "$(cat $p/type 2>/dev/null)" = Mains ] && echo $p; done | head -1)
PKG=$(for z in /sys/class/thermal/thermal_zone*; do [ "$(cat $z/type)" = x86_pkg_temp ] && echo $z/temp; done | head -1)

# --- preflight -----------------------------------------------------------------
ok=1
if ! journalctl -k -b -n1 --no-pager >/dev/null 2>&1 || [ -z "$(journalctl -k -b -n1 --no-pager -q 2>/dev/null)" ]; then
  echo "ERROR: this account cannot read the kernel log. Add it to the 'systemd-journal' group (then log in again)."; ok=0
fi
dp=$(journalctl -k -b --no-pager 2>/dev/null | grep -c drm_dp_dpcd_read)
if [ "$dp" -eq 0 ]; then
  echo "WARNING: no DisplayPort debug lines found in this boot's kernel log."
  echo "         Enable with:  sudo sh -c 'echo 0x100 > /sys/module/drm/parameters/debug'"
  echo "         (or boot with kernel argument drm.debug=0x100), then change the refresh rate once to confirm."
fi
echo "Desktop: $(desktop_info)"
echo "Panel:   $(panel_mode)"
[ $ok -eq 1 ] || { rmdir "$RUN" 2>/dev/null; exit 1; }

meta() {
  echo "== $1 $(date '+%F %T.%3N')"
  echo "boot_id: $(cat /proc/sys/kernel/random/boot_id)"
  echo "kernel: $(uname -r)"
  echo "cmdline: $(cat /proc/cmdline)"
  echo "os: $(. /etc/os-release; echo "$PRETTY_NAME")"
  echo "desktop: $(desktop_info)"
  echo "panel mode: $(panel_mode)"
  echo "drm.debug: $(cat /sys/module/drm/parameters/debug 2>/dev/null || echo 'not readable (needs root)'); DP debug lines this boot: $(journalctl -k -b --no-pager 2>/dev/null | grep -c drm_dp_dpcd_read)"
  echo "AC online: $(cat $AC/online 2>/dev/null)  battery: $(cat $BAT/capacity 2>/dev/null)% $(cat $BAT/status 2>/dev/null)"
  echo "nvidia: $(nvidia-smi --query-gpu=name,driver_version,power.draw,temperature.gpu,pstate --format=csv,noheader 2>/dev/null)"
  echo
}
meta START > "$RUN/meta.txt"

journalctl -kf -n0 -o short-precise > "$RUN/kernel.log" 2>&1 & KPID=$!
journalctl -f -n0 -o short-precise > "$RUN/journal.log" 2>&1 & JPID=$!
sleep 1
logger -t flicker-phase "RECORDING START $RUN"

finish() {
  logger -t flicker-phase "RECORDING STOP"
  sleep 1
  kill $KPID $JPID 2>/dev/null
  meta END >> "$RUN/meta.txt"
  echo "Saved to $RUN"
  exit 0
}
trap finish INT TERM

echo "time,ac_online,bat_pct,bat_status,bat_V,bat_W,cpu_pkg_C,gpu_W,gpu_C,gpu_MHz,gpu_util,gpu_pstate,refresh_Hz,compositor_flip_errors,linkloss_total" > "$RUN/monitor.csv"
echo "Recording to $RUN (max $MAX_MIN min). Stop: Ctrl+C or: touch $RUN/STOP"
end=$(( $(date +%s) + MAX_MIN*60 )); n=0; refresh=""
while [ ! -e "$RUN/STOP" ] && [ "$(date +%s)" -lt "$end" ]; do
  ((n++ % 5 == 0)) && refresh=$(panel_refresh)
  ac=$(cat "$AC/online" 2>/dev/null); pct=$(cat $BAT/capacity 2>/dev/null); st=$(cat $BAT/status 2>/dev/null | tr ' ' _)
  v=$(awk '{printf "%.3f",$1/1e6}' $BAT/voltage_now 2>/dev/null); w=$(awk '{printf "%.1f",$1/1e6}' $BAT/power_now 2>/dev/null)
  cpu=$(awk '{printf "%.0f",$1/1000}' "$PKG" 2>/dev/null)
  IFS=, read -r gw gc gmhz gu gp < <(nvidia-smi --query-gpu=power.draw,temperature.gpu,clocks.gr,utilization.gpu,pstate --format=csv,noheader,nounits 2>/dev/null | tr -d ' ')
  # page-flip / atomic-commit failures reported by any compositor (sway/wlroots, Mutter, Hyprland)
  flips=$(grep -ciE 'page.?flip.*fail|atomic commit failed|flip.*(EBUSY|resource busy)' "$RUN/journal.log")
  # DPCD 0x202 read where lanes 0-3 are not all "7" = link not fully locked at that moment
  loss=$(grep '0x00202 AUX' "$RUN/kernel.log" | grep -vc ') 77 77')
  echo "$(date +%T),$ac,$pct,$st,$v,$w,$cpu,$gw,$gc,$gmhz,$gu,$gp,$refresh,$flips,$loss" >> "$RUN/monitor.csv"
  sleep 1
done
finish
