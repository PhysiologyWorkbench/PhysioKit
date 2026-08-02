# CLAUDE.md — PhysioKit

## What this is

The physiological signal algorithms for the Physiology Workbench family: HRV
metrics, RR artifact correction, R-peak detection and ECG-derived respiration.
Swift ports of published methods, with the references pinned in `PROVENANCE.md`.

It knows nothing about Bluetooth, devices, files or user interfaces. Everything
crossing its boundary is plain data — `[Double]` in, `Double?` or `[RPeak]` out.
That is deliberate: the owner wanted native Swift now with an easy path back to a
Rust or C implementation later, and nothing Swift-specific leaks across the
boundary, so the package could be re-backed by a C ABI without its callers
noticing.

## Constraints

- **macOS and iOS are both hard requirements.** iPadOS later.
- **Causal where it matters.** The correctors and the detector run on a live
  stream, so they may not look forward. Batch variants are welcome behind the
  same seams, but must be named as batch.
- Swift 6 language mode. No actors here — these are values and pure functions.
- **Accelerate only.** Adding any other dependency is a decision to be taken
  deliberately, not a convenience; see below.

## Layout

```
Sources/PhysioKit/
  Metrics.swift               — meanRR, rmssd, sdnn, standardDeviation (vDSP)
  RRArtifactCorrector.swift   — the corrector seam: RRCorrection, the protocol
  PercentageJumpCorrector.swift — causal percentage-jump rejection
  RPeakDetector.swift         — the detector seam: RPeak, the protocol
  PanTompkinsDetector.swift   — causal Pan–Tompkins, batch-fed
  Respiration.swift           — respiratoryRate from R-wave amplitude modulation
Tests/PhysioKitTests/         — 23 tests
```

`swift build` / `swift test` from the repo root. Green baseline: **23 tests**,
and they are the whole validation available without a chest — see "Hardware
truth".

## Dependencies

**None.** Accelerate is a system framework, not a package dependency, and the
manifest has no `dependencies:` at all.

This is not an omission and it is worth keeping. The sibling packages in the
family (`DeviceCore`, `LovenseKit`, `PolarKit`, `Hdf5Store`) reference each other
by path pre-publication and switch to git URL + version at publication — step
**C2** of the repo split. This package needs neither: it depends on nothing, and
nothing about its build changes when the others are published.

Sibling repos, all directly under the same parent: `DeviceCore`, `LovenseKit`,
`PolarKit`, `PhysioKit`, `Hdf5Store`, `PWB`. **The directory names are
load-bearing** — SwiftPM derives a path dependency's package identity from the
directory basename, not from the manifest's `name:`. `PWB` is the one repo that
depends on this one.

## The seams

Two protocols, both plain-data, both with one causal conformer today:

- **`RRArtifactCorrector`** — `Double` in (one RR interval, ms), `RRCorrection`
  out (a value plus whether it was judged an artifact). `PercentageJumpCorrector`
  is the causal conformer. The planned batch **Lipponen–Tarvainen** corrector goes
  behind this same protocol; `PROVENANCE.md` already pins its reference and
  constants so the port is a diff, not an archaeology dig.
- **`RPeakDetector`** — a batch of samples in, `[RPeak]` out, with
  **absolute sample indices** counted from the last `reset()`.
  `PanTompkinsDetector` is the causal conformer.

`respiratoryRate` and the HRV metrics are free functions, not seams. They have
one implementation each and no plausible second, so a protocol would be a naming
convention rather than a seam. (The family has made that mistake once already, in
`DeviceCore`; do not repeat it here.)

## What the algorithms know that their references don't

- **A causal filter shifts the answer, and the fiducial is where it shows.**
  `PanTompkinsDetector` decides *that* there is a beat from the filtered chain,
  and then locates the peak in the **raw** ring buffer against a local baseline.
  Reporting the filtered index would have biased every beat time by the group
  delay — a constant 6 samples, 46 ms at 130 Hz. Bonus: the amplitude comes back
  in real µV, which is exactly what the respiration stage wants.
  **Detect on the processed signal, measure on the original.**
- **A latency-carrying detector must report absolute positions, not offsets.** A
  peak is confirmed after its own samples, so the batch that returns it is usually
  not the batch that contained it. `RPeak.sampleIndex` counts from the last reset
  and the caller anchors sample zero; anchoring forward from the current batch
  shifts every beat by about a frame.
- **The respiration noise guard is ours, and its threshold is measured.** The
  strongest component in the respiratory band must exceed **four times** the band
  mean or no rate is reported. White noise reaches 2–3× naturally (the largest of
  ~50 periodogram bins), a real modulation 8–24 even when shallow. "Twice the band
  mean" felt sober and let pure noise through every time. **Guess the shape of the
  statistic, measure the value.**
- **Two deliberate departures from Pan–Tompkins**, both noted in the source: the
  filters are Butterworth biquads derived from the sample rate rather than the
  paper's integer-coefficient forms fixed at 200 Hz (the strap streams 130 Hz);
  and the paper's halved thresholds for irregular rhythms are not carried, there
  being no arrhythmia data here to validate that path against.
- **`respiratoryRate` returns `nil` rather than a bad number** when the span is
  too short, the beats too few, or nothing stands above the band. A caller must
  treat `nil` as *unknown*, never as *unchanged*: a stale respiration value once
  vetoed a safety stop in the app, because the estimator goes silent exactly when
  breathing turns irregular. Expiry is the caller's job, but the `nil` is this
  package's contract.

## Provenance

`PROVENANCE.md` pins every reference — Pan & Tompkins (1985), Moody et al.
(1985), Lipponen & Tarvainen (2019), the ESC/NASPE HRV task force (1996) — and
the NeuroKit2 implementation each Swift port tracks, **at a specific commit**
(`56075c05…`, 2026-02-22), with the key constants listed.

Update it with any change to an algorithm. The point is that re-syncing against
an upstream that has moved is a diff against a known point.

## Hardware truth

The tests here run against synthetic signals, and a synthetic signal is not a
body. Every constant in this package was provisional until a chest said
otherwise — and one of them was wrong when it did.

The validation exists, but it lives with the sensor: a 26-minute annotated
protocol against a metronome, recorded through a Polar H10, with the results in
the **PolarKit** repo's `POLAR.md`. What it established, in this package's terms:
detected R peaks agree with the strap's own fused RR within ±1 beat per block,
RMSSD from those beats agrees to a few ms, and `respiratoryRate` lands within
0.5 br/min of a metronome at 6, 12 and 20 br/min — with availability, not
accuracy, as its weak point.

**Anything changing a constant here should be re-checked against that protocol
rather than against the synthetic tests alone.**

## Rules this repo enforces

- **Nothing Swift-specific in the public surface.** No actors, no `AsyncStream`,
  no Foundation-only types where a plain one exists. The boundary is what makes
  the implementation replaceable.
- **A fallback path is not covered until you have watched its test fail.** The
  search-back test passed the moment it was written, which proved nothing — the
  ordinary threshold path satisfies it too. Commenting the search-back out and
  watching the test fail took thirty seconds and turned a decorative test into a
  real one.
- **Cite before you port.** A new algorithm gets its `PROVENANCE.md` entry in the
  same commit as its source file.
- **Batch and causal are different algorithms**, even behind one protocol. Name
  them so at the call site.

## Design record

`PROVENANCE.md` — the references and the pinned upstream.
`LESSONS.md` — dated lessons; skim before work that resembles past work.
The hardware evidence is in the **PolarKit** repo's `POLAR.md`; the app that
composes these algorithms into a live pipeline is the **PWB** repo.
