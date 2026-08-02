# Lessons learned — PhysioKit

Running log of high-level lessons from building this library. Newest first. Each
entry is dated and kept terse — "what I wish I'd known starting", not a step log.

Entries here are this repo's slice of a log that was kept for the whole
Physiology Workbench family before it was split into separate repositories, so a
dated heading may appear in a sibling repo too, carrying that repo's bullets.

## 2026-07-29 — Derived signals: the synthetic signal is not the body

Own R-peak detection and ECG-derived respiration, written against synthetic ECG
and **not yet validated on hardware** at the time of writing — which is itself the
first lesson: the two transport phases before this one both found that the
reference lied and the hardware didn't, so treat every constant as provisional
until a chest says otherwise. (It has since said so; the evidence lives with the
sensor, in the PolarKit repo's `POLAR.md`, including which of these constants was
wrong.)

- **A causal filter shifts your answer, and the fiducial is where it shows.**
  The detector runs on a band-passed signal, so the peak it finds sits at the
  filter's group delay — a constant 6 samples (46 ms at 130 Hz) in the first test
  run. Reporting that index would have biased every beat time. The fix was to
  locate the peak in the *raw* ring buffer against a local baseline, using the
  filtered chain only to decide *that* there is a beat. Bonus: the amplitude comes
  back in real µV, which is what the respiration stage wants. Generally — **detect
  on the processed signal, measure on the original.**
- **A latency-carrying detector must report absolute positions, not offsets.**
  A peak is confirmed after its own samples, so the batch that returns it is
  usually not the batch that contained it. `RPeak.sampleIndex` counts from the
  last reset and the caller anchors sample zero; anchoring forward from the
  current batch would have shifted every beat by about a frame (0.56 s). The
  property is testable without hardware: every beat must land on the synthetic's
  RR grid, and a frame is not a multiple of it.
- **Prove a fallback path is actually being taken.** The search-back test passed
  the moment it was written — which proves nothing, since the ordinary threshold
  path would satisfy it too. Commenting out the search-back call and watching the
  test fail was thirty seconds and turned a decorative test into a real one. Do
  this for any test that claims to cover a recovery path.
- **A noise guard needs a measured threshold, not a plausible one.** "Peak must
  exceed twice the band mean" felt sober and let pure noise through every time:
  the largest of ~50 periodogram bins naturally sits 2–3× the mean. Measuring both
  populations (noise 2.2–3.0, real modulation 8–24 even when shallow and noisy)
  made the choice obvious and gave the constant a justification in the source.
  **Guess the shape of the statistic, measure the value.**

## 2026-07-24 — RR artifact handling: a package with a swap-ready seam

This package's first stage: the RR corrector, carved out as a standalone package
rather than written into the app.

- **A dependency-free package is cheap insurance for a decision you might
  revert.** The owner wanted native Swift now but an easy path back to Rust later.
  Realised as a package that imports only Accelerate and exposes the corrector as
  a plain-data protocol (`RRArtifactCorrector`: `Double` in, `Double` out).
  Nothing Swift-specific leaks across the boundary, so the whole package could be
  re-backed by a C ABI later, and it lifts into its own repo by moving a directory
  — which is exactly what eventually happened, with no changes to the code.
  Keeping the algorithms out of the app also gave them real unit tests without a
  host app.
- **Vendor the reference, pinned, next to the port.** The algorithms are ports of
  published methods, so `PROVENANCE.md` cites the NeuroKit implementation at a
  specific commit — the same discipline the family applies to vendored device
  configuration. Re-syncing later is a diff against a known point, not an
  archaeology dig.
