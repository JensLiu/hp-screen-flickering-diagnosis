# Flicker reproduced: the internal display link drops under load (2026-11-23)

## Setup
- Panel at 2560x1600 @ 240 Hz, driven by the Intel iGPU over eDP (4 lanes). Laptop on AC power (battery 80%, steady 12.3 V).
- DRM DisplayPort debug logging on: `echo 0x100 > /sys/module/drm/parameters/debug`.
- `repro/monitor-load.sh` logged power and temperatures every second. The user pressed ENTER at the moment of visible flicker.
- Load: OCCT GPU 3D + GPU memory test on the RTX 5070 (~65–78 W, 86–98% utilization).

## Result
- 20:26–20:29, idle at 240 Hz: **no** spontaneous link events.
- 20:29:45: OCCT starts. GPU 42 °C → 70 °C, CPU package 56 °C → 79 °C.
- **20:33:17 onward: the panel repeatedly reports loss of the link** (DPCD reads after short-pulse HPD IRQs),
  roughly every 15–60 s. The user saw thin lines and blackouts at the same moment (FLICKER markers at 20:33:27–20:33:32).
- No modeset, refresh change or output power change happened during this period, so these drops are spontaneous.

### How to read the DPCD lane-status reads (`0x00202` = LANE0_1, LANE2_3, ALIGN, SINK_STATUS)
Each nibble is one lane. `7` = CR_DONE | CHANNEL_EQ_DONE | SYMBOL_LOCKED (healthy). `0` = lane lost completely.

| Read | Meaning |
|---|---|
| `77 77 81` / `77 77 01` | all 4 lanes locked, interlane aligned (healthy) |
| `00 00 80` / `00 00 00` | **all 4 lanes lost clock recovery and symbol lock**: link down, so the screen blanks |
| `11 11 80` | only clock recovery on all lanes: link mid-recovery |
| `17 77 81` (20:34:24) | **lane 1 alone** lost equalization and symbol lock while lanes 0, 2 and 3 stayed fine |

Example spontaneous event (20:35:33.996 → 20:35:34.150): link down (`00 00 80`, `00 00 00`), then back up
(`77 77 81`) about 150 ms later. This matches a brief blackout with a line glitch.

## Conclusion
The physical eDP link between the mainboard and the panel loses signal lock under sustained load at 240 Hz.
It happens while plugged in with stable battery voltage, so it is not a battery or power-sag issue. A
single-lane failure is characteristic of a marginal cable or connector (signal integrity), made worse by heat
and/or electrical noise from the dGPU under load. The problem started after the screen panel was replaced by
the service, so the most likely cause is a poorly seated, damaged or out-of-spec eDP cable or connector, or a
marginal replacement panel.

The sway `Page-flip failed` errors are a side effect (the driver is busy recovering the link), not the cause.

## Files
- `kernel-drm-dp-debug_2026-11-23_20-15_onward.log`: kernel log with DP debug
- `link-status-reads.log`: only the DPCD 0x200/0x202 reads
- `monitor-2026-11-23_20-27-01.csv`: per-second power, temperatures, GPU load and FLICKER markers
- `pageflip-2026-11-23_20-27-01.log`: sway page-flip errors during the run
- `full-journal_2026-11-23_20-15_onward.log`: everything logged in that window

Note: 20:16–20:20 (refresh toggle test) and 20:23–20:25 (display power off/on test) also contain link-training
reads. Those are **expected** because each modeset or power-on retrains the link. Only the events after 20:33 are spontaneous.
