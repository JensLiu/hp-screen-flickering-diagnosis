# Tools (`repro/`)

| Script | Purpose |
|---|---|
| `record-session.sh [max_minutes]` | **Clean recording session.** Creates `runs/<timestamp>/` with `meta.txt` (system state at start and end), `kernel.log` (incl. DP debug), `journal.log`, and `monitor.csv` (1 Hz). Stops with Ctrl+C, `touch runs/<ts>/STOP`, or after max_minutes (default 90) |
| `mark.sh` | Marker tool. **Press Enter without typing anything** = toggles `FLICKER START` / `FLICKER END` (one episode; a continuous flicker needs only two presses). **Type text + Enter** = phase label. Known labels start a reminder notification for when the phase is over. (The session from 20:43 began with an older version where Enter = a single `FLICKER` marker.) |
| `display-info.sh` | Shared helper sourced by the other scripts: detects the desktop (GNOME via Mutter D-Bus, sway, Hyprland) and reads the panel's current mode/refresh rate |
| `monitor-load.sh` | Older interactive monitor (first reproduction): a 1 Hz CSV plus a live table. Press Enter in it to mark a flicker |
| `toggle-refresh.sh [cycles] [seconds]` | Switches eDP-1 between 240 and 60 Hz repeatedly (forces the link to retrain). Always ends at 60 Hz |
| `stress-pattern.html` | Full-screen worst-case patterns (1 px checkerboard and lines inverting every frame, flashes, gradient). Keys 1–5, Space, A, H. **Mode 4 strobes**, so skip it if you're sensitive to flashing |

## Before recording
DisplayPort debug logging must be on. It lasts until reboot:
```
sudo sh -c 'echo 0x100 > /sys/module/drm/parameters/debug'
```
Check that it's on: `journalctl -k -b | grep -c drm_dp_dpcd_read` should be greater than 0 after any display change.

## Running a session
1. `repro/record-session.sh` (in the background, or in its own terminal)
2. `repro/mark.sh` in a terminal you can switch to quickly
3. Phases (type the label into mark.sh, then press Enter):

| Phase | Label | Duration | Action |
|---|---|---|---|
| A | `idle 240` | 5 min | Nothing heavy running |
| B | `occt start 240` | 10 min | OCCT GPU test running |
| C | `occt stop` | 3 min | OCCT stopped, cooldown |
| D (optional) | `occt start 60` | 10 min | First set 60 Hz (GNOME: Settings > Displays > Refresh Rate; sway: `swaymsg output eDP-1 mode 2560x1600@60.001Hz`), then OCCT |

4. Press Enter alone in mark.sh **when flickering starts**, and Enter again **when it stops**.

## Monitor CSV columns
`time, ac_online, bat_pct, bat_status, bat_V, bat_W, cpu_pkg_C, gpu_W, gpu_C, gpu_MHz, gpu_util, gpu_pstate, refresh_Hz, pageflip_total, linkloss_total`
(`linkloss_total` is only in `record-session.sh`: a running count of DPCD 0x202 reads where the lanes are not all locked.)

## Analysis one-liners
```
R=runs/<timestamp>
grep -E 'flicker-(mark|phase)' $R/journal.log                       # markers and phases
grep '0x00202' $R/kernel.log | grep -v ') 77 77'                    # link-loss reads
grep '0x00202' $R/kernel.log | grep -v ') 77 77' | cut -c8-15 | uniq -c   # per second
```
Remember to exclude the link retraining you caused yourself (refresh switches, output power-on, resume).
