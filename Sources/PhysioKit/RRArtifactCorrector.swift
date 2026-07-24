/// The result of correcting one RR interval: the value to use downstream (the
/// original when accepted, or a corrected value when an artifact was detected) and
/// whether it was flagged as an artifact.
public struct RRCorrection: Equatable {
    public let valueMs: Double
    public let isArtifact: Bool

    public init(valueMs: Double, isArtifact: Bool) {
        self.valueMs = valueMs
        self.isArtifact = isArtifact
    }
}

/// The artifact-correction seam: a causal, streaming corrector fed one RR interval
/// at a time. Deliberately plain data in/out (`Double`s), so the whole boundary
/// could be re-backed by a non-Swift implementation (e.g. Rust behind a C ABI)
/// without changing callers. See `PROVENANCE.md`.
public protocol RRArtifactCorrector {
    mutating func accept(_ rrMs: Double) -> RRCorrection
    mutating func reset()
}
