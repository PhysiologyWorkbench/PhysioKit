# PhysioKit — algorithm provenance

The RR-interval / HRV algorithms here are ports of published references. This file
pins the upstream sources so the Swift implementations can be re-synced when the
references change.

## RR artifact correction

`PercentageJumpCorrector` — a causal percentage-jump rejection filter: the
streaming simplification of the Kubios "threshold" correction (compare each RR
interval to a local expectation; reject/interpolate beyond a percentage
threshold).

The batch corrector planned behind the same `RRArtifactCorrector` seam is the
Lipponen & Tarvainen (2019) method — the Kubios *automatic* correction:

> Lipponen JA, Tarvainen MP. "A robust algorithm for heart rate variability time
> series artefact correction using novel beat classification." *J Med Eng Technol.*
> 2019;43(3):173–181.

Reference implementation to port and re-sync against:

- NeuroKit2 — `neurokit2/signal/signal_fixpeaks.py`, `_find_artifacts`
  (`method="kubios"`).
- Repository: https://github.com/neuropsychology/NeuroKit
- Pinned commit: `56075c05aae819a4962fcd9eeeac3ddf86b0de51` (2026-02-22)
- Key constants: `alpha=5.2`, `window_width=91`, `c1=0.13`, `c2=0.17`,
  `medfilt_order=11`.

## HRV metrics

`meanRR`, `rmssd`, `sdnn` — standard time-domain HRV definitions (Task Force of the
European Society of Cardiology and the North American Society of Pacing and
Electrophysiology, 1996). SDNN and RMSSD use the population (divide-by-N) form.
Computed via Accelerate / vDSP.
