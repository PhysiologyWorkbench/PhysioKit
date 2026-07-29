# PhysioKit — algorithm provenance

The ECG / RR-interval / HRV algorithms here are ports of published references.
This file pins the upstream sources so the Swift implementations can be re-synced
when the references change.

## R-peak detection

`PanTompkinsDetector` — the classic real-time QRS detector:

> Pan J, Tompkins WJ. "A real-time QRS detection algorithm." *IEEE Trans Biomed
> Eng.* 1985;BME-32(3):230–236.

Reference implementation to re-sync against:

- NeuroKit2 — `neurokit2/ecg/ecg_findpeaks.py`, `_ecg_findpeaks_pantompkins`.
- Repository: https://github.com/neuropsychology/NeuroKit
- Pinned commit: `56075c05aae819a4962fcd9eeeac3ddf86b0de51` (2026-02-22)
- Key constants: band-pass 5–15 Hz, 150 ms integration window, 200 ms
  refractory, 360 ms T-wave window with a 0.5 slope ratio, threshold
  `NPK + 0.25 (SPK − NPK)`, peak/noise adaptation 0.125, search-back at 1.66 ×
  the RR average with the half threshold, RR acceptance band 92 %–116 %.

Two deliberate departures, both noted in the source: the filters are Butterworth
biquads derived from the sample rate rather than the paper's integer-coefficient
forms, which are fixed at 200 Hz (the H10 streams 130 Hz); and the paper's halved
thresholds for irregular rhythms are not carried, there being no arrhythmia data
here to validate that path against.

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

## ECG-derived respiration

`respiratoryRate` — the R-wave amplitude (RPA) variant of ECG-derived
respiration: breathing swings the heart's electrical axis and the chest's
impedance, so the R-wave amplitudes carry the respiratory modulation and its
frequency is the breathing rate.

> Moody GB, Mark RG, Zoccola A, Mantero S. "Derivation of respiratory signals
> from multi-lead ECGs." *Computers in Cardiology.* 1985;12:113–116.

Reference implementations to re-sync against:

- NeuroKit2 — `neurokit2/ecg/ecg_rsp.py` and `neurokit2/signal/signal_rate.py`.
- Repository: https://github.com/neuropsychology/NeuroKit
- Pinned commit: `56075c05aae819a4962fcd9eeeac3ddf86b0de51` (2026-02-22)
- Key constants: respiratory band 0.1–0.5 Hz (6–30 breaths/min), resampled to
  4 Hz, at least three cycles of the slowest breath in the band.

One guard is ours rather than the reference's: the strongest band component must
exceed four times the band mean, or no rate is reported. White noise reaches
2–3 times, a real modulation 8 and up, so this refuses to read a rate off noise.

## HRV metrics

`meanRR`, `rmssd`, `sdnn` — standard time-domain HRV definitions (Task Force of the
European Society of Cardiology and the North American Society of Pacing and
Electrophysiology, 1996). SDNN and RMSSD use the population (divide-by-N) form.
Computed via Accelerate / vDSP.
