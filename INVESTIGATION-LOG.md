# Investigation log

All times are CET (2026-11-23 unless stated otherwise).

## 1. Initial report: flicker after the screen went off and woke up
- User: "My screen starts flickering after briefly going off (automatically) and then woke up."
- Found two **critical-battery suspends** requested by `upowerd`, at 18:59:44 and 19:01:14. The battery was at
  0%, discharging at ~50 W. Hibernate is blocked by Secure Boot lockdown, so upower suspends instead.
- After the 18:59:48 resume, sway logged `Atomic commit failed: Device or resource busy` / `Page-flip failed`.
- User: the screen went back to normal after the second suspend.
- **Hypothesis 1: a bad resume at a near-empty battery left the panel in a bad state.** (Later rejected.)

## 2. Survey of all boots since the first conversation (2026-11-21)
- 22 boots: 20 clean, 2 unclean (battery ran out after a critical-battery suspend: Nov 22 12:13, Nov 23 19:03).
- Resume always brought the panel back within a second.
- **Correction:** page-flip errors were not tied to resume. Boot -2 had 0 suspends and 2022 errors.
- **Hypothesis 2: the Intel GPU can't keep up at 240 Hz, and the page-flip failures cause the flicker.**
- User: 60 Hz doesn't flicker, 240 Hz does (first written as "120", then corrected).
- Found the panel only has 60.001 and 240 Hz modes, so an earlier suggestion to try 120 Hz was wrong.

## 3. Folder created
- Full per-boot journals, filtered extracts, system info and configs were dumped into this folder.
- A bug in the filename generation (an embedded "-- No entries --" and newline) was fixed by renaming.

## 4. Questioning the page-flip theory
- User asked: how are we sure it's page flips? Answer: **we weren't.** There was no timestamp match, and a
  dropped frame looks like a stutter, not like lines or a blackout.
- User described the artifact: **thin lines, occasionally blacking out and coming back.**
  This points to signal corruption or a panel resync, not dropped frames.
- Searched all full logs for underrun, link-training and AUX errors at normal log level: there were none.
  Found nouveau crashes on Nov 21 (unrelated, before the blacklist).
- **Hypothesis 3: an eDP link or signal problem at 240 Hz**, with i915 power features (FBC/DC) as an alternative.

## 5. Panel replacement
- User: the problem appeared **after the official service replaced the screen panel**.
- EDID: CMN 0x1652, made week 21 of 2024, supports 240 Hz.
- This strengthens the hardware hypothesis (cable, connector or panel).

## 6. Reproduction attempts (~20:09–20:26)
- Stress pattern page and refresh-toggle script created.
- Toggle test (20:17–20:20, 7 cycles): **no visible artifacts.** Page-flip errors were logged anyway, so
  page flips are confirmed not to be the visible symptom.
- The user enabled DRM DP debug (`drm.debug=0x100`) at 20:10.
- Output power off/on and suspend/resume at 240 Hz: **no visible artifacts.**
- **Hypothesis 4: a voltage drop at a near-empty battery under load** (the first episode was at 0% battery).

## 7. Reproduction with GPU load (20:27–20:37)
- User: heavy GPU load is another way to trigger it. Ran the OCCT GPU test with `repro/monitor-load.sh`.
- 20:29:45 load starts. **From 20:33:17, the panel repeatedly reports link loss** (`00 00`, then `77 77`
  about 150 ms later; at 20:34:24 lane 1 alone, `17 77`). The user's FLICKER markers at 20:33:27–32 match.
- On AC power with steady 12.3 V, so **Hypothesis 4 rejected.**
- No modeset or output change during the load, so the events are spontaneous.
- **Conclusion: the eDP link loses lock under load.** Evidence was saved to `evidence/`, with a write-up in `evidence/FINDINGS.md`.

## 8. Review of the evidence and method
- User asked for the evidence and method. The limitations were documented: a short idle baseline, markers
  from one session, no 60 Hz-under-load control, heat/noise/power not separated, cable versus panel unknown.

## 9. Clean recording session (started 20:43:06)
- `repro/record-session.sh` records only this session into `runs/2026-11-23_20-43-06/`, with metadata at the
  start and end, the kernel log, the journal and a 1 Hz CSV that includes a live link-loss count.
- `repro/mark.sh` records FLICKER markers and phase labels, with desktop-notification reminders for each phase:
  A idle 240 Hz (5 min) → B OCCT at 240 Hz (10 min) → C cooldown (3 min) → D optional OCCT at 60 Hz (10 min).
- Changed during the session: Enter in `mark.sh` now toggles FLICKER START/END, because once the flicker starts it
  continues. The reminders I scheduled with a background `nohup` were killed when my command finished, so the
  Phase B2 reminder never arrived (and probably the Phase A one too).
- The user noted that the earlier reproduction also ran **OCCT CPU+RAM**, not only 3D Adaptive + VRAM. So phase B
  was split: B = GPU only, then B2 = CPU+RAM added. Phase D used the full combined load at 60 Hz.

## 10. Results of the clean session (analysed after 21:35)
- A idle 240 Hz: 0 link-loss. B GPU only 240 Hz (~88 W, 12 min): 0. **B2 + CPU/RAM at 240 Hz: flicker after
  1 min 50 s, 26 link-loss reads in 6 episodes.** C cooldown: the flicker stopped 28 s after the load.
  **D, the same combined load at 60 Hz: 0 events, no flicker** (user confirmed).
- **Conclusions:** the trigger is combined CPU/RAM + GPU load, it requires 240 Hz, and it is not power related.
  See `runs/2026-11-23_20-43-06/ANALYSIS.md`.
