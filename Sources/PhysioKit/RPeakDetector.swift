/// One detected R wave: where it sits in the sample stream and how tall it is.
/// `sampleIndex` counts from the last `reset`, so a caller that knows the wall
/// time of any one sample can place every peak; `amplitude` is the band-passed
/// signal at the fiducial, whose beat-to-beat modulation is the input to
/// ECG-derived respiration.
public struct RPeak: Equatable {
    public let sampleIndex: Int
    public let amplitude: Double

    public init(sampleIndex: Int, amplitude: Double) {
        self.sampleIndex = sampleIndex
        self.amplitude = amplitude
    }
}

/// The R-peak detection seam: a causal detector fed the ECG in the batches the
/// sensor delivers, returning the peaks it became sure of during that batch.
/// Peaks lag their batch — a detector must see past a peak to confirm it — which
/// is why they carry an absolute index rather than a position within the batch.
/// Plain data in/out (`Double`s and `Int`s) like `RRArtifactCorrector`, so the
/// boundary survives a non-Swift re-backing. See `PROVENANCE.md`.
public protocol RPeakDetector {
    mutating func accept(_ samples: [Double]) -> [RPeak]
    mutating func reset()
}
