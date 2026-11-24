# Findings

## System

| Item | Value |
|---|---|
| Laptop | HP (subsystem 103c:8d3f), with a display MUX (the NVIDIA GPU also has an eDP connector, `card0-eDP-2`, disconnected) |
| Panel | CMN (Chimei Innolux) 0x1652, 2560x1600, made week 21 of 2024 (from the EDID). **Replaced by the official service shortly before the problem started.** |
| Panel modes | Only **60.001 Hz** and **240 Hz**. The sway config uses 240 Hz, scale 1.25 |
| Panel driven by | Intel Raptor Lake-S UHD (i915), `card1-eDP-1`, 4-lane eDP |
| dGPU | NVIDIA RTX 5070 Max-Q, open kernel module 620.70.06 (render offload only) |
| Software | Fedora 45, kernel 7.3.4, sway 1.12, wlroots 0.20.2, mesa 26.2.7. Kernel cmdline has `i915.enable_psr=0` |

## Symptom (user's description)

Thin lines across the screen, and occasionally the screen goes black and comes back. It appears under
sustained combined CPU+RAM and GPU load at 240 Hz (on AC power). It does not appear at idle, with GPU-only load, or at
60 Hz under the same load.

## Main finding: the eDP link loses lock under load

Reproduced on 2026-11-23 at about 20:33 with the OCCT GPU test (details in [evidence/FINDINGS.md](evidence/FINDINGS.md)).

- With DRM DisplayPort debug logging on, the kernel logs every read of the panel's DPCD link-status
  registers. Register `0x202`/`0x203` holds the per-lane status, one hex digit per lane: `7` = locked, `0` = lost.
- **Idle at 240 Hz (20:26–20:29): no spontaneous link-status reads.**
- **Under OCCT load (from 20:33:17), every 15–60 s:**
  - `00 00`: all 4 lanes lost clock recovery and symbol lock (link down, so the screen goes black)
  - `77 77` about 100–150 ms later: link re-locked
  - At 20:34:24: `17 77`, meaning **only lane 1** lost equalization and symbol lock
- The user's FLICKER markers (20:33:27–20:33:32) fall in the same seconds as link-loss events (20:33:27, 20:33:29).
- Nothing changed the display configuration during the load (no modeset, no refresh change, no output
  power change), so these are spontaneous link failures, not deliberate retraining.
- Conditions at the time: **on AC power**, battery steady at 12.3 V. NVIDIA GPU ~65–78 W at ~70 °C, CPU package ~78 °C.

### Confirmed in the clean session (20:43–21:35, [runs/2026-11-23_20-43-06/ANALYSIS.md](runs/2026-11-23_20-43-06/ANALYSIS.md))

| Phase | Refresh | Load | Spontaneous link-loss reads | User saw |
|---|---|---|---|---|
| A idle (6.6 min) | 240 | none | 0 | no flicker |
| B GPU only (11.9 min) | 240 | OCCT 3D Adaptive + VRAM, ~88 W | 0 | no flicker |
| B2 GPU + CPU/RAM (13.9 min) | 240 | + OCCT CPU+RAM | **26 in 6 episodes** (all 4 lanes lost) | **continuous flicker 21:08:41–21:21:13** |
| D GPU + CPU/RAM (10.2 min) | **60** | same as B2, similar temperatures | 0 | no flicker |

- **The trigger is combined CPU+RAM + GPU load. GPU load alone doesn't trigger it.**
- **It depends on refresh rate:** the same load at 60 Hz is clean.
- The flicker began 1 min 50 s after CPU+RAM was added and stopped 28 s after the load was stopped.

### Why 240 Hz and not 60 Hz: link speed
The driver's link setup shows that **240 Hz runs each of the 4 lanes at 8.1 Gbit/s (HBR3, the panel's maximum),
while 60 Hz uses 4.32 Gbit/s**. A marginal connection fails first at the higher rate. In the clean session, two
of the episodes (21:09:26 and 21:09:33) ended with i915 **fully retraining the link: the panel's link was powered
down and up for about 1 s**, which is a visible blackout. The other episodes recovered without a retrain.

### Why CPU+RAM load triggers it (hypotheses, not yet distinguished)
- **No FIFO underruns** were logged (i915 always reports those), so it is **not** the display engine being starved of
  memory bandwidth. The failure is at the physical link level (the lanes lose lock).
- **The temperature difference is small:** the CPU package maxed at 77 °C with GPU-only load (no failure) and 79–80 °C
  with CPU+RAM (failure). Measured heat alone is a weak explanation, but the temperature near the connector is unknown.
- **The eDP transmitter is part of the CPU chip.** On Intel laptop CPUs the display engine and its output circuitry
  (DDI A, which drives the eDP link) sit on the CPU die. CPU core and memory-controller load causes large, fast current
  swings and switching noise in the CPU package and its voltage regulators, right where the eDP signal starts.
  This reduces the margin of the 8.1 Gbit/s signal. With a healthy connection there is enough margin left. With a
  marginal connector or cable there isn't. **Leading hypothesis.**
- Once the link starts failing, it keeps failing while the load continues: the link flaps (lines), the driver
  retrains it (about 1 s blackout), and the cycle repeats. That's the "violent" continuous flicker.
- Tests that would distinguish heat from electrical noise: CPU-only vs RAM-only stress, the same stress with a
  capped CPU power limit, and the same stress started from a cold machine (immediate failure points to electrical noise).

**Interpretation.** The physical link between the GPU and the panel is marginal. A single lane failing on
its own points to signal integrity in the cable or connector rather than software. Heat and/or electrical
noise under load pushes it over the edge, and 240 Hz runs the link at its highest data rate, which leaves the
least margin. Combined with the timing (it started after the panel replacement), the most likely causes are a
poorly seated, damaged or wrong eDP cable or connector, or a marginal replacement panel.

## Secondary findings

### Page-flip errors are a side effect, not the cause
- sway logs `Atomic commit failed: Device or resource busy` / `Page-flip failed on output eDP-1`
  in almost every session (up to ~2000 per session, in bursts of up to ~190 per 10 min).
- During the refresh-toggle test, errors were logged while the user saw **no** artifacts.
- They happen when the driver can't accept a new frame. During a link recovery this is expected.

### The "screen went off" events were critical-battery suspends
- 2026-11-23 18:59:44 and 19:01:14 (and 2026-11-22 12:10): `suspend requested from client ... ('upowerd')`.
  The battery was at 0%, discharging at about 50 W.
- Hibernate is blocked by kernel lockdown (Secure Boot), so upower can only suspend.
- Battery health: 76.9% of design capacity.

### Shutdowns
- 20 of 22 boots ended with a clean reboot or poweroff.
- The 2 unclean endings (Nov 22 12:13, Nov 23 19:03) were the battery running out after a critical-battery
  suspend and resume. The journal just stops.

### Resume works
- After every resume, the panel and bar came back within the same second, using the correct config.
- `Failed to disable CRTC` before every suspend is noise (sway has already lost DRM master).
- `nvidia-suspend.service` being skipped is expected with the open driver plus s2idle.

### Unrelated noise
- `nouveau` crashes on boots -21/-20 (2026-11-21), before nouveau was blacklisted
- `spd5118 ... failed to resume async: error -6` on every resume (RAM temperature sensor)
- `ACPI Error: No handler for Region [CMS0]`, `NVRM: rm_power_source_change_event ... status=0x11`

## Confidence and limitations

| Claim | Confidence | Why / caveat |
|---|---|---|
| The eDP link loses lock during the flicker | **High** | Direct register readings from the panel, timed with the user's markers |
| It is triggered by combined CPU+RAM + GPU load | **High** | Two sessions. In the clean session: 0 events idle (6.6 min), 0 with GPU only (11.9 min), 26 after CPU+RAM was added |
| It depends on 240 Hz | **High** | The same combined load at 60 Hz with similar temperatures: 0 events, no visible flicker |
| Battery / voltage drop | **Ruled out** | It happens on AC with stable voltage |
| Heat vs electrical noise from the CPU/memory side | **Unknown** | Not separated. GPU heat alone (76 °C) was not enough |
| Every visible glitch is logged | **No** | Flicker was visible 21:08:41–21:21:13, but link-loss reads cover only 21:09:26–21:18:57. Matching is per episode |
| Cable/connector vs panel | **Inference** | A single-lane failure points to the connection, but software can't distinguish the cable from the panel |
| Caused by the panel replacement | **Circumstantial** | Based on timing. We have no logs from before the repair |

Decoding the DPCD bytes is our own interpretation, based on the DisplayPort register layout. The kernel
only prints the raw bytes. See [METHODS.md](METHODS.md#reading-dpcd-link-status).

## Recommendation
1. Take it back to the service under the repair warranty with [SERVICE-SUMMARY.md](SERVICE-SUMMARY.md) and `evidence/`.
   Ask them to reseat or replace the eDP cable, check both connectors, and confirm the panel part number.
2. Until then, use 60 Hz: `output "Chimei Innolux Corporation 0x1652 0x0000FFA1" mode 2560x1600@60.001Hz scale 1.25`.
3. Avoid draining the battery to 0% under load (critical-battery suspends, and two sudden power losses).
