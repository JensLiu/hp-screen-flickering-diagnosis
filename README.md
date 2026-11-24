# Screen flickering investigation

HP laptop (Intel Raptor Lake iGPU + NVIDIA RTX 5070 Max-Q), Fedora 45, sway.
Investigation started 2026-11-23. It covers every boot in the journal (2026-11-21 10:56 onward).

## Status

**Reproduced twice and localized.** Under sustained **combined CPU+RAM and GPU load at 240 Hz**, the internal eDP
link between the mainboard and the panel **loses signal lock**. GPU load alone, idle, and the same load at 60 Hz
were all clean (see `runs/2026-11-23_20-43-06/ANALYSIS.md`). Sometimes it is all 4 lanes, once it was only lane 1. The link
re-locks about 100–150 ms later. This matches the symptom: **thin lines and brief blackouts that recover by
themselves**. The problem started after the official service replaced the screen panel. The most likely cause
is the eDP cable or connector (badly seated, damaged or wrong part), or a marginal replacement panel.

Confidence and caveats are in [FINDINGS.md](FINDINGS.md#confidence-and-limitations).
The second, clean recording session (20:43–21:35, `runs/2026-11-23_20-43-06/`) confirmed it with control phases.

**Workaround until repair:** run the panel at 60 Hz.

## Documents

| File | Contents |
|---|---|
| [report/report.pdf](report/report.pdf) | **Formal report for the service/technicians** (LaTeX source `report/report.tex`): method, tests, data, results, reproduction procedure, scripts |
| [FINDINGS.md](FINDINGS.md) | What we know, the evidence for it, and how confident we are |
| [METHODS.md](METHODS.md) | How the investigation was done and how to read the raw data (DPCD decoding etc.) |
| [INVESTIGATION-LOG.md](INVESTIGATION-LOG.md) | Chronological log, including the hypotheses that were rejected and why |
| [TOOLS.md](TOOLS.md) | The scripts in `repro/` and how to run a recording session |
| [SERVICE-SUMMARY.md](SERVICE-SUMMARY.md) | A short, non-technical summary to give the repair service |
| [evidence/FINDINGS.md](evidence/FINDINGS.md) | Write-up of the first successful reproduction (20:33, OCCT run) |

## Folder layout

| Path | Contents |
|---|---|
| `evidence/` | First reproduction: DP debug kernel log, monitor CSV with FLICKER markers, journal |
| `runs/<timestamp>/` | Clean recording sessions (`meta.txt`, `kernel.log`, `journal.log`, `monitor.csv`) |
| `repro/` | Test and recording tools, plus raw output of the early tests |
| `full-logs/` | The complete journal of every boot since 2026-11-21 (`bootNN_<start>_<id>.log.gz`, use `zless`) |
| `filtered/` | Extracts of the full logs: page-flip errors, suspend/resume timeline, boot endings |
| `system-info/` | Hardware, versions, sway outputs, driver parameters, panel EDID, upower dump |
| `config/` | Copies of the sway config, UPower.conf and /etc/modprobe.d at the time of the investigation |

> The full logs contain everything the system logged (network names, devices, app activity).
> Review them before sharing them with anyone.
