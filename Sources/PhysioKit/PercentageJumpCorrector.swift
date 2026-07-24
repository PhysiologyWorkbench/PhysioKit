/// Causal percentage-jump artifact corrector — the streaming simplification of the
/// Kubios "threshold" correction (see `PROVENANCE.md`). Each RR interval is compared
/// to the median of a small buffer of recently accepted intervals; if it deviates
/// by more than `threshold` (fractional) it is flagged and replaced by that local
/// expectation. The corrected value is fed back into the buffer, so a run of
/// artifacts cannot drag the expectation with it.
///
/// A per-beat percentage tolerance lets genuine heart-rate ramps through (each beat
/// stays within `threshold` of its neighbours). Sustained-change handling is where
/// the batch Lipponen–Tarvainen corrector will later improve on this.
public struct PercentageJumpCorrector: RRArtifactCorrector {
    public let threshold: Double
    public let bufferSize: Int

    private var accepted: [Double] = []

    public init(threshold: Double = 0.2, bufferSize: Int = 5) {
        precondition(bufferSize >= 1)
        self.threshold = threshold
        self.bufferSize = bufferSize
    }

    public mutating func accept(_ rrMs: Double) -> RRCorrection {
        // Warm-up: accept unconditionally until there is enough context to judge.
        guard accepted.count >= bufferSize, let expected = median(accepted) else {
            push(rrMs)
            return RRCorrection(valueMs: rrMs, isArtifact: false)
        }
        if abs(rrMs - expected) / expected > threshold {
            push(expected)
            return RRCorrection(valueMs: expected, isArtifact: true)
        }
        push(rrMs)
        return RRCorrection(valueMs: rrMs, isArtifact: false)
    }

    public mutating func reset() {
        accepted.removeAll(keepingCapacity: true)
    }

    private mutating func push(_ value: Double) {
        accepted.append(value)
        if accepted.count > bufferSize { accepted.removeFirst() }
    }
}

private func median(_ xs: [Double]) -> Double? {
    guard !xs.isEmpty else { return nil }
    let sorted = xs.sorted()
    let mid = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
}
