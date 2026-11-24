# Methods

## Principles
- **Evidence comes from the system's own records:** the systemd journal (`journalctl`), kernel debug output and
  `/sys`. No conclusions from symptoms alone.
- **Eliminate hypotheses with tests.** Every hypothesis was tested, and three were rejected (see
  [INVESTIGATION-LOG.md](INVESTIGATION-LOG.md)).
- **Line events up by time.** User observations (markers), kernel events and sensor readings are matched on
  timestamps.
- **Exclude expected events.** Link retraining caused by deliberate actions (refresh switches, output power-on,
  resume) looks like a failure in the log, so those periods are identified and excluded.

## 1. Log survey (all boots)
- Listed the boots with `journalctl --list-boots`, and covered all 22 boots since 2026-11-21.
- Per boot (run under bash, because zsh does not split words in unquoted variables), counted:
  - a clean ending: `Journal stopped`, `systemd-shutdown`, `reboot.target`/`poweroff.target` in the last lines
  - suspends: `PM: suspend entry`, and who requested them (`suspend requested from client`)
  - display errors: `Page-flip failed`, `Atomic commit failed`, `Failed to disable CRTC`
- sway runs under GDM, so **its log lines appear as `gdm-wayland-session[<pid>]`, not `sway`.**
- Checked whether the screen came back after each resume: the time of `PM: suspend exit` versus the output
  being reconfigured (`Found config * for output eDP-1`, `Bar configured`).
- Histogram of page-flip errors per 10 minutes, to see whether they cluster after resume (they don't).
- Searched for i915 errors visible at normal log level: FIFO underrun, link training, AUX timeouts. There were none.

## 2. Hardware and configuration
- `lspci -nnk` for the GPUs. Mapped `/sys/class/drm/cardN` to drivers, finding that the panel is on `card1` = i915.
- `swaymsg -t get_outputs` lists the panel's modes. There are only 60.001 and 240 Hz, no 120 Hz.
- EDID decoded by hand from `/sys/class/drm/card1-eDP-1/edid` (manufacturer, product, manufacture week/year).
- upower state and config (`upower -i`, `/etc/UPower/UPower.conf`), and the swayidle command line.

## 3. Making the link visible: DRM debug
At the default log level, i915 does not log eDP link problems. DisplayPort debug output was turned on:

```
sudo sh -c 'echo 0x100 > /sys/module/drm/parameters/debug'   # 0x100 = DRM_UT_DP; lasts until reboot
```

The kernel then logs every DPCD read over the AUX channel, for example:
```
i915 ...: [drm:drm_dp_dpcd_read [drm_display_helper]] AUX A/DDI A/PHY A: 0x00202 AUX -> (ret=  6) 00 00 80 00 00 00
```

### Reading DPCD link status
`0x00202` reads 6 bytes starting at DPCD address 0x202 (the DisplayPort standard's register layout):

| Byte | Address | Meaning |
|---|---|---|
| 1 | 0x202 LANE0_1_STATUS | low digit = lane 0, high digit = lane 1 |
| 2 | 0x203 LANE2_3_STATUS | low digit = lane 2, high digit = lane 3 |
| 3 | 0x204 LANE_ALIGN_STATUS_UPDATED | bit 0 = interlane align done, bit 7 = link status updated |
| 4 | 0x205 SINK_STATUS | |

Each lane digit is made of bits: `1` = clock recovery done, `2` = channel equalization done, `4` = symbol locked.
So `7` = healthy, `1` = only clock recovery, `0` = lane completely lost.

| Example | Meaning |
|---|---|
| `77 77 81` | all lanes locked, aligned (healthy) |
| `00 00 80` | all 4 lanes lost (link down) |
| `11 11 80` | clock recovery only (link training in progress) |
| `17 77 81` | lane 1 = `1`: **lane 1 alone** lost equalization and symbol lock |

Reads of `0x00200` (SINK_COUNT, DEVICE_SERVICE_IRQ) together with `0x2005` and `0x200b` are the sequence the
driver uses when it services an interrupt from the panel. This is inferred from the read pattern; this debug
category doesn't log a reason.

### Where the link-status lines come from (the chain)
1. **The panel's eDP receiver (its timing controller)** continuously monitors each of the 4 lanes (clock
   recovery, equalization, symbol lock) and keeps the result in its own DPCD registers 0x202–0x207.
2. When the panel detects a problem, it signals the GPU with a short pulse on the HPD (hot-plug detect) wire.
   This is a "short pulse" or IRQ_HPD, as opposed to a long pulse that means plug/unplug.
3. **The i915 driver** handles the interrupt by reading the panel's registers over the AUX channel (a slow
   side-channel next to the 4 data lanes): 0x200 (sink count / IRQ vector), 0x2005 and 0x200b (IRQ/ESI
   registers), and 0x202 (6 bytes of link status).
4. If the link isn't healthy, i915 **retrains** it: panel power D3 (`0x600 = 02`), then D0 (`0x600 = 01`) about
   1 s later, reading the capabilities (0x000, 0x2200, 0x010), setting lanes and rate (`0x101 = 84` → 4 lanes +
   enhanced framing, `0x115` = link-rate index), clock recovery (`0x102 = 21`, TPS1 → status `11 11`), then
   equalization (`0x102 = 07`, TPS4 → status `77 77`), and done (`0x102 = 00`).
5. With `drm.debug=0x100` (DRM_UT_DP), `drm_display_helper` prints **every** AUX read and write to the kernel
   log as `[drm:drm_dp_dpcd_read …] AUX A/DDI A/PHY A: <address> AUX -> (ret=<len>) <bytes>` (`AUX <-` for writes).
6. journald stores the kernel log. `record-session.sh` captured it with `journalctl -kf -o short-precise` into
   `kernel.log`. The analysis greps `0x00202` and drops the lines whose lanes are `77 77`.

Step 2 is inferred from the read pattern (0x200 → 0x2005 → 0x202 → 0x200b). The DP debug category doesn't
print "HPD short pulse" itself. The KMS category (`drm.debug=0x106`) would print it explicitly.

**Link rate.** The eDP rate table read from 0x010 (16-bit values in units of 200 kHz) is: 1.62, 2.16, 2.43, 2.7, 3.24,
4.32, 5.4 and 8.1 Gbit/s per lane. Observed `0x115` writes: **240 Hz → index 7 = 8.1 Gbit/s (HBR3, the maximum)**,
**60 Hz → index 5 = 4.32 Gbit/s**. So 240 Hz runs the link at almost twice the bit rate, which leaves far less
margin for a marginal cable or connector.

**Spontaneous versus expected:** every modeset (refresh change), output power-on and resume also retrains
the link and produces the same reads. Spontaneous events are reads where lanes are not `77 77`, in periods
with none of those actions. That was checked in the journal (no output reconfiguration, no `swaymsg`
mode changes) and in the process list (the toggle script was not running).

## 4. Reproduction tests

| Test | Tool | Result |
|---|---|---|
| Stress patterns at 240 Hz (1 px checkerboard, lines, flashes) | `repro/stress-pattern.html` | No visible artifacts |
| Refresh toggle 60↔240 Hz, 7 cycles | `repro/toggle-refresh.sh` | No visible artifacts. Page-flip errors still logged, so page flips can't be the visible symptom |
| Output power off/on at 240 Hz, 5 cycles | inline `swaymsg 'output eDP-1 power off/on'` loop | No visible artifacts |
| Suspend/resume at 240 Hz | `systemctl suspend` | No visible artifacts |
| **Sustained GPU load at 240 Hz, on AC** | OCCT GPU 3D + memory test, `repro/monitor-load.sh` | **Reproduced**: link-loss events plus visible lines and blackouts |

## 5. Measuring during reproduction
`repro/monitor-load.sh` (first run) and `repro/record-session.sh` (clean sessions) sample once per second:
- AC online, battery %, status, **voltage** (`voltage_now`) and power (to detect a voltage drop)
- CPU package temperature (`x86_pkg_temp`)
- NVIDIA power, temperature, clock, utilization and P-state (`nvidia-smi`)
- refresh rate (sway), the count of page-flip errors, and (in `record-session.sh`) the count of non-`77 77` link-status reads

User observations are recorded with `logger` into the journal (`flicker-mark` = flicker seen,
`flicker-phase` = phase label), so they share a clock with the kernel log and can be matched to it.

## 6. Analysis
- Count link-status reads that aren't `77 77`, per second or minute: `grep '0x00202' kernel.log | grep -v ') 77 77'`
- Find the closest link event to each FLICKER marker.
- Compare event rates between phases (idle versus load, 240 versus 60 Hz) and against temperature and power in the CSV.

## Known weaknesses
See [FINDINGS.md → Confidence and limitations](FINDINGS.md#confidence-and-limitations). Mainly: the first
idle baseline was short, the markers came from one session, the 60 Hz-under-load control hasn't been done,
and heat, noise and power are not separated.
