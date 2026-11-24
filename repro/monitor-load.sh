#!/usr/bin/env bash
# Logs power/thermal/display state once per second while you run a GPU load (e.g. OCCT).
# Press ENTER in this terminal the moment you see lines/blackout -> a FLICKER marker is recorded.
# Ctrl+C to stop. Output: monitor-<timestamp>.csv and pageflip-<timestamp>.log next to this script.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"; TS=$(date +%F_%H-%M-%S)
. "$DIR/display-info.sh"
CSV="$DIR/monitor-$TS.csv"; FLIPS="$DIR/pageflip-$TS.log"
BAT=/sys/class/power_supply/BAT0
AC=$(for p in /sys/class/power_supply/*; do [ "$(cat $p/type 2>/dev/null)" = Mains ] && echo $p; done | head -1)
PKG=$(for z in /sys/class/thermal/thermal_zone*; do [ "$(cat $z/type)" = x86_pkg_temp ] && echo $z/temp; done | head -1)

journalctl -f -n0 -o short-precise 2>/dev/null | grep --line-buffered -iE 'page.?flip.*fail|atomic commit failed' > "$FLIPS" &
JPID=$!
trap 'kill $JPID 2>/dev/null; echo; echo "Saved: $CSV"; echo "       $FLIPS"; exit' INT TERM

echo "time,marker,ac_online,bat_pct,bat_status,bat_V,bat_W,cpu_pkg_C,gpu_W,gpu_C,gpu_MHz,gpu_util,gpu_pstate,refresh_Hz,pageflip_total" > "$CSV"
echo "Logging to $CSV"
echo ">>> Press ENTER the moment you see thin lines or a blackout. Ctrl+C to stop. <<<"
printf "%-8s %-3s %4s %-12s %6s %6s %5s %6s %5s %5s %4s %7s %5s\n" time AC bat% status batV batW cpuC gpuW gpuC MHz util refresh flips
n=0
while :; do
  marker=""
  if read -r -t 1 _; then marker="FLICKER"; logger -t flicker-mark "user saw flicker"; fi
  ((n++ % 5 == 0)) && refresh=$(panel_refresh)
  ac=$(cat "$AC/online" 2>/dev/null)
  pct=$(cat $BAT/capacity); st=$(cat $BAT/status)
  v=$(awk '{printf "%.2f",$1/1e6}' $BAT/voltage_now)
  w=$(awk '{printf "%.1f",$1/1e6}' $BAT/power_now 2>/dev/null)
  cpu=$(awk '{printf "%.0f",$1/1000}' "$PKG")
  IFS=, read -r gw gc gmhz gu gp < <(nvidia-smi --query-gpu=power.draw,temperature.gpu,clocks.gr,utilization.gpu,pstate --format=csv,noheader,nounits 2>/dev/null | tr -d ' ')
  flips=$(grep -ciE 'page.?flip.*fail|atomic commit failed' "$FLIPS")
  t=$(date +%T)
  echo "$t,$marker,$ac,$pct,$st,$v,$w,$cpu,$gw,$gc,$gmhz,$gu,$gp,${refresh:-},$flips" >> "$CSV"
  printf "%-8s %-3s %4s %-12s %6s %6s %5s %6s %5s %5s %4s %7s %5s %s\n" "$t" "$ac" "$pct" "$st" "$v" "$w" "$cpu" "$gw" "$gc" "$gmhz" "$gu" "${refresh:-}" "$flips" "$marker"
done
