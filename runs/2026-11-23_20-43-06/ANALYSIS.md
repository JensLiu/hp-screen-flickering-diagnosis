# Clean session 2026-11-23 20:43:06 – 21:35:22: analysis

Same boot (0279ba15), DRM DP debug on (set at 20:10), AC power throughout (battery 80%, not charging).
Phase labels and flicker markers were entered by the user with `repro/mark.sh` (logged in `journal.log`).

## Phases and results

| Phase | Time | Refresh | Load | CPU pkg | GPU avg / max temp | **Spontaneous link-loss reads** | User saw |
|---|---|---|---|---|---|---|---|
| A idle | 20:48:19–20:54:57 (6.6 min) | 240 | none | 53–71 °C | 12 W / 54 °C | **0** | no flicker |
| B GPU only | 20:54:57–21:06:51 (11.9 min) | 240 | OCCT 3D Adaptive + VRAM | 58–77 °C | 88 W / 76 °C | **0** | no flicker |
| B2 GPU + CPU/RAM | 21:06:51–21:20:45 (13.9 min) | 240 | + OCCT CPU+RAM | 67–80 °C | 72 W / 75 °C | **26** (6 episodes) | **flicker 21:08:41 → 21:21:13, continuous** |
| C cooldown | 21:20:45–21:24:16 | 240 | none | 55–77 °C | 13 W / 63 °C | 0 | flicker ended 21:21:13 |
| D GPU + CPU/RAM | 21:24:52–21:35:02 (10.2 min) | **60** | OCCT 3D + VRAM + CPU+RAM | 58–79 °C | 65 W / 76 °C | **0** | **no flicker** |

Battery voltage stayed between 12.25 and 12.70 V (on AC), with no sag.

## Link-loss episodes (DPCD 0x202, lanes not `77 77`)
All in phase B2, and all spontaneous (no mode change, output power change or resume at those times):

| Time | Reads | Pattern |
|---|---|---|
| 21:09:26.60 – 21:09:27.90 | 9 | `00 00 80` / `00 00 00` (all 4 lanes lost) → `11 11 80` (clock recovery, retraining) |
| 21:09:33.21 – 21:09:34.43 | 6 | the same |
| 21:14:13.69 – 21:14:17.02 | 5 | all lanes lost |
| 21:17:20.50 – 21:17:20.58 | 4 | all lanes lost |
| 21:18:23.84 | 1 | all lanes lost |
| 21:18:57.57 | 1 | all lanes lost |

**Excluded (expected):** 21:24:14 `11 11 80` = link training for the user's switch to 60 Hz (sway shows 60 Hz from
21:24:16). 21:35:02 `11 11 80` = training for the switch back to 240 Hz.

## Interpretation
1. **Trigger = combined CPU+RAM + GPU load, not GPU load alone.** About 12 min of ~88 W GPU load gave 0 events.
   Adding CPU+RAM gave visible flicker within 1 min 50 s and link loss within 2 min 35 s.
2. **Refresh-rate dependent.** The same combined load at 60 Hz, with comparable temperatures (CPU up to
   79 °C vs 80 °C, GPU max 76 vs 75 °C), gave 0 events and no visible flicker.
3. It is not battery or voltage related (on AC, stable voltage).
4. It is consistent with a marginal eDP link that fails at 240 Hz (highest data rate, least margin) when the
   CPU/memory side is heavily loaded. That could be from heat near the mainboard connector or the cable path,
   or from electrical noise from the CPU/memory power delivery. This run can't separate heat from noise.

## Caveats
- **The visible flicker lasted longer than the logged events.** The user marked a continuous flicker from
  21:08:41 to 21:21:13, but link-loss reads cover 21:09:26–21:18:57. The driver only reads link status when
  the panel raises an interrupt, so not every glitch is logged. Matching is at the level of episodes, not
  individual glitches.
- Under CPU load the 1 Hz monitor slowed to one sample every 3–5 s (276 gaps over 3 s, max 5 s). The kernel log
  is unaffected.
- Phase D's label was typed at 21:24:52, but the switch to 60 Hz happened at 21:24:16, so 60 Hz covers the
  whole of phase D.
- One session only. Phase A (idle) and phase B (GPU only) are now proper control periods.
