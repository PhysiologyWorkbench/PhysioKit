# PhysioKit

Physiological signal algorithms in Swift 6: heart-rate-variability metrics, RR
artifact correction, R-peak detection, and ECG-derived respiration. Ports of
published methods, with every reference pinned in
[PROVENANCE.md](PROVENANCE.md).

Dependency-free — Accelerate only, no packages. It knows nothing about
Bluetooth, files or user interfaces: plain data in, plain data out.

## What is in it

| | |
| --- | --- |
| `meanRR`, `rmssd`, `sdnn`, `standardDeviation` | time-domain HRV metrics over an RR series, via vDSP |
| `RRArtifactCorrector` | the corrector seam — one RR interval in, a value plus an artifact flag out |
| `PercentageJumpCorrector` | causal percentage-jump rejection with a local expectation |
| `RPeakDetector` / `RPeak` | the detector seam — samples in, absolute sample indices out |
| `PanTompkinsDetector` | causal Pan–Tompkins QRS detection, batch-fed, fiducial measured off the raw signal |
| `respiratoryRate` | breathing rate from R-wave amplitude modulation, with a measured noise guard |

## Requirements

Swift 6.0, macOS 13+ / iOS 16+. No dependencies.

## Use

```swift
.package(url: "https://github.com/PhysiologyWorkbench/PhysioKit", from: "0.1.0")
```

```swift
var detector = PanTompkinsDetector(sampleRate: 130)
var corrector = PercentageJumpCorrector()

for batch in ecgBatches {                       // [Double], microvolts
    for peak in detector.accept(batch) {
        // peak.sampleIndex is absolute since the last reset()
        let rr = msBetween(peak, previous)
        let corrected = corrector.accept(rr)
        if !corrected.isArtifact { rrSeries.append(corrected.valueMs) }
    }
}

let hrv = rmssd(rrSeries)
let breathsPerMinute = respiratoryRate(amplitudes: amplitudes, times: beatTimes)
```

`respiratoryRate` returns `nil` when it cannot see a rate it believes — too short
a span, too few beats, or nothing standing clear of the noise. Treat `nil` as
*unknown*, never as *unchanged*.

## Build and test

```sh
swift build
swift test        # 23 tests
```

The tests run against synthetic signals. A synthetic signal is not a body: these
algorithms have also been validated against a Polar H10 over a 26-minute
annotated protocol with a breathing metronome, and the evidence for that lives
with the sensor rather than here.

## Design notes

- **Causal by default.** The corrector and the detector run on a live stream and
  may not look forward. Batch variants belong behind the same seams, named as
  batch — the Lipponen–Tarvainen corrector is the planned one, already pinned in
  `PROVENANCE.md`.
- **Detect on the processed signal, measure on the original.** The QRS detector
  decides *that* there is a beat from a band-passed chain, then locates the peak
  in the raw buffer — otherwise every beat time carries the filter's group delay
  (6 samples, 46 ms at 130 Hz) and the amplitude is not in microvolts.
- **Absolute indices.** A peak is confirmed after its own samples arrive, so the
  batch that returns it is usually not the batch that contained it.

## Licence

Not yet stated — the repository is pre-publication. The referenced upstream
implementations carry their own licences; see `PROVENANCE.md`.
