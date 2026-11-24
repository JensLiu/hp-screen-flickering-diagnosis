# Display fault after screen panel replacement: summary for service

**Problem:** Since the screen panel was replaced, the internal display shows **thin lines and briefly goes black,
then recovers**. It happens under sustained **combined CPU and GPU load** (e.g. OCCT CPU+RAM together with 3D + VRAM)
at the panel's 240 Hz refresh rate. In a controlled test it did **not** happen at idle, with GPU-only load, or with
the same combined load at 60 Hz.

**What the logs show:** with the Linux kernel's DisplayPort debug logging enabled, the panel reports that the
internal **eDP link loses signal lock** at the moments the artifacts appear:
- all 4 lanes drop (lane status `00 00`) and re-lock about 150 ms later, repeating every 15–60 s under load
- in one event **only lane 1** lost symbol lock while the other three lanes stayed fine
- the laptop was on AC power with stable voltage, and no display settings changed during the test

A single lane failing on its own points to a **physical connection problem** (cable or connector signal
integrity), not software.

**Request:**
1. Reseat or replace the **eDP display cable** and check the connectors at both ends (mainboard and panel).
2. Confirm that the replacement panel matches the original part (installed: CMN/Innolux 0x1652,
   2560x1600 @ 240 Hz, made week 21 of 2024).
3. Test the result at **240 Hz under sustained combined CPU + GPU load** for 10+ minutes. In our test, the flicker
   began about 2 minutes after the CPU load was added. The problem doesn't show at idle, with GPU-only load, or at 60 Hz.

**Attached evidence:** the `evidence/` folder: kernel DisplayPort debug log, per-second temperature and power
log with timestamps of when the artifacts were seen, and an explanation of the log values (`evidence/FINDINGS.md`).
