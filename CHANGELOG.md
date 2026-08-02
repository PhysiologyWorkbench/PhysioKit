# Changelog

This project adheres to [Semantic Versioning](https://semver.org/). While the major
version is 0 the public API may change in a minor release; every such change is listed
here.

## [0.1.0] — unreleased

First release. The physiological signal algorithms of the Physiology Workbench family,
as a dependency-free package.

### Added

- **HRV metrics.** `meanRR`, `rmssd`, `sdnn` and `standardDeviation` over an RR series,
  computed with vDSP. Population (divide-by-N) form.
- **RR artifact correction.** The `RRArtifactCorrector` seam — one interval in, an
  `RRCorrection` out — with `PercentageJumpCorrector` as the causal conformer.
- **R-peak detection.** The `RPeakDetector` seam — a batch of samples in, `[RPeak]` at
  absolute sample indices out — with `PanTompkinsDetector` as the causal conformer.
  Detection runs on the filtered chain, the fiducial and its amplitude are measured on
  the raw signal.
- **ECG-derived respiration.** `respiratoryRate` from R-wave amplitude modulation,
  returning `nil` rather than a rate it cannot believe.
