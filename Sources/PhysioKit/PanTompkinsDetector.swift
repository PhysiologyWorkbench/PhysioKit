import Foundation

/// Causal Pan–Tompkins QRS detector (see `PROVENANCE.md`): band-pass →
/// derivative → squaring → moving-window integration → adaptive thresholds, with
/// T-wave discrimination and search-back for missed beats. Sample-recursive by
/// nature, so batching changes nothing — feeding one array and feeding it in
/// chunks give identical peaks.
///
/// Two deliberate departures from the paper. The filters are Butterworth biquads
/// derived from `sampleRate` rather than the paper's integer-coefficient forms,
/// which assume 200 Hz — the H10 streams 130 Hz. And the fiducial is the largest
/// band-passed excursion inside the window that produced the detection, so
/// `RPeak.sampleIndex` names the R wave rather than the integrator's delayed
/// peak; the magnitude is taken unsigned so an inverted lead detects equally,
/// while the reported amplitude keeps its sign.
///
/// Not carried: the paper's halved thresholds for irregular rhythms. There is no
/// arrhythmia data here to validate that path against, and the house rule is not
/// to carry code no owned device exercises.
public struct PanTompkinsDetector: RPeakDetector {
    public let sampleRate: Double

    private let integrationWindow: Int
    private let fiducialWindow: Int
    private let refractory: Int
    private let tWaveWindow: Int
    private let learningSamples: Int
    private let candidateMemory: Int

    private var lowPass: Biquad
    private var highPass: Biquad
    private var raw: Ring
    private var bandPassed: Ring
    private var derivatives: Ring
    private var squares: Ring
    private var integratorSum = 0.0

    /// The two most recent integrator outputs, so a local maximum can be spotted
    /// one sample after it happens.
    private var previous1 = 0.0
    private var previous2 = 0.0
    private var index = 0

    private var learningPeak = 0.0
    private var learningSum = 0.0

    private var signalLevel = 0.0
    private var noiseLevel = 0.0
    private var threshold = 0.0

    private var lastQrsIndex: Int?
    private var lastQrsSlope = 0.0
    private var recentIntervals: [Int] = []
    private var regularIntervals: [Int] = []
    private var acceptableInterval: ClosedRange<Double>?
    private var missedInterval: Double?

    /// Peaks rejected as noise, kept so search-back can promote the best of them
    /// when a beat turns out to have been missed.
    private var candidates: [Candidate] = []

    public init(sampleRate: Double) {
        precondition(sampleRate > 0)
        self.sampleRate = sampleRate
        integrationWindow = max(Int((0.150 * sampleRate).rounded()), 1)
        // Wide enough to hold the R wave the integrator peak was built from,
        // once the band-pass and derivative group delays are allowed for.
        fiducialWindow = integrationWindow + 12
        refractory = Int((0.200 * sampleRate).rounded())
        tWaveWindow = Int((0.360 * sampleRate).rounded())
        learningSamples = max(Int((2.0 * sampleRate).rounded()), 1)
        candidateMemory = Int((5.0 * sampleRate).rounded())
        lowPass = .lowPass(cutoff: 15, sampleRate: sampleRate)
        highPass = .highPass(cutoff: 5, sampleRate: sampleRate)
        raw = Ring(capacity: fiducialWindow + 8)
        bandPassed = Ring(capacity: fiducialWindow + 8)
        derivatives = Ring(capacity: fiducialWindow + 8)
        squares = Ring(capacity: integrationWindow + 1)
    }

    public mutating func accept(_ samples: [Double]) -> [RPeak] {
        var peaks: [RPeak] = []
        for sample in samples { step(sample, into: &peaks) }
        return peaks
    }

    public mutating func reset() {
        self = PanTompkinsDetector(sampleRate: sampleRate)
    }

    private mutating func step(_ sample: Double, into peaks: inout [RPeak]) {
        raw.append(sample)
        bandPassed.append(highPass.filter(lowPass.filter(sample)))
        // Five-point derivative, then squaring and a moving-window integration:
        // the QRS becomes one broad bump whose width is the complex's duration.
        let slope = (2 * (bandPassed[index] ?? 0) + (bandPassed[index - 1] ?? 0)
                     - (bandPassed[index - 3] ?? 0) - 2 * (bandPassed[index - 4] ?? 0)) / 8
        derivatives.append(slope)
        integratorSum -= squares[index - integrationWindow] ?? 0
        integratorSum += slope * slope
        squares.append(slope * slope)
        let integrated = integratorSum / Double(integrationWindow)

        if index < learningSamples {
            learningPeak = max(learningPeak, integrated)
            learningSum += integrated
            if index == learningSamples - 1 {
                // The paper's learning phase: seed the running estimates from the
                // first couple of seconds rather than from zero, which would take
                // the first peak of any size for a beat.
                signalLevel = 0.25 * learningPeak
                noiseLevel = 0.5 * learningSum / Double(learningSamples)
                updateThreshold()
            }
        } else {
            searchBack(into: &peaks)
            if previous1 > previous2, previous1 >= integrated {
                classify(peakIndex: index - 1, level: previous1, into: &peaks)
            }
        }

        previous2 = previous1
        previous1 = integrated
        index += 1
    }

    private mutating func classify(peakIndex: Int, level: Double, into peaks: inout [RPeak]) {
        if let last = lastQrsIndex, peakIndex - last < refractory { return }
        let candidate = candidate(at: peakIndex, level: level)
        guard level > threshold else {
            noiseLevel = 0.125 * level + 0.875 * noiseLevel
            remember(candidate)
            updateThreshold()
            return
        }
        // A T wave arriving inside 360 ms is tall but slow; the QRS that precedes
        // it is at least twice as steep.
        if let last = lastQrsIndex, peakIndex - last < tWaveWindow,
           candidate.slope < 0.5 * lastQrsSlope {
            noiseLevel = 0.125 * level + 0.875 * noiseLevel
            remember(candidate)
            updateThreshold()
            return
        }
        signalLevel = 0.125 * level + 0.875 * signalLevel
        take(candidate, into: &peaks)
        updateThreshold()
    }

    /// Promotes the strongest rejected peak once a beat is overdue, using the
    /// half threshold — the paper's answer to a beat lost to a passing threshold
    /// excursion.
    private mutating func searchBack(into peaks: inout [RPeak]) {
        guard let last = lastQrsIndex, let missed = missedInterval,
              Double(index - last) > missed else { return }
        let reachable = candidates.filter {
            $0.peakIndex - last >= refractory && $0.level > threshold / 2
        }
        guard let best = reachable.max(by: { $0.level < $1.level }) else { return }
        signalLevel = 0.25 * best.level + 0.75 * signalLevel
        take(best, into: &peaks)
        updateThreshold()
    }

    private mutating func take(_ candidate: Candidate, into peaks: inout [RPeak]) {
        if let last = lastQrsIndex { record(interval: candidate.peakIndex - last) }
        lastQrsIndex = candidate.peakIndex
        lastQrsSlope = candidate.slope
        candidates.removeAll(keepingCapacity: true)
        peaks.append(RPeak(sampleIndex: candidate.fiducialIndex, amplitude: candidate.amplitude))
    }

    /// Keeps the two RR averages the paper distinguishes: one over the last eight
    /// beats however irregular, one over the last eight that fell inside the
    /// acceptable band. The second drives the limits, so a run of ectopic beats
    /// cannot widen its own tolerance.
    private mutating func record(interval: Int) {
        recentIntervals.append(interval)
        if recentIntervals.count > 8 { recentIntervals.removeFirst() }
        if acceptableInterval?.contains(Double(interval)) ?? true {
            regularIntervals.append(interval)
            if regularIntervals.count > 8 { regularIntervals.removeFirst() }
        }
        let source = regularIntervals.isEmpty ? recentIntervals : regularIntervals
        let average = Double(source.reduce(0, +)) / Double(source.count)
        acceptableInterval = (0.92 * average)...(1.16 * average)
        missedInterval = 1.66 * average
    }

    private mutating func remember(_ candidate: Candidate) {
        candidates.append(candidate)
        while let first = candidates.first, candidate.peakIndex - first.peakIndex > candidateMemory {
            candidates.removeFirst()
        }
    }

    private mutating func updateThreshold() {
        threshold = noiseLevel + 0.25 * (signalLevel - noiseLevel)
    }

    /// Locates the R wave behind an integrator peak: the largest excursion from
    /// the local baseline in the window that fed it, read off the *raw* signal so
    /// the filters' group delay does not shift the reported time and the
    /// amplitude stays in the input's own units. The steepest band-passed slope
    /// over the same span serves the T-wave test. Both are resolved now rather
    /// than on acceptance, so search-back can reach further back than the ring
    /// buffers hold.
    private func candidate(at peakIndex: Int, level: Double) -> Candidate {
        let window = max(peakIndex - fiducialWindow, 0)...peakIndex
        let values = window.compactMap { raw[$0] }
        let baseline = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)

        var fiducialIndex = peakIndex
        var amplitude = 0.0
        var slope = 0.0
        for i in window {
            if let value = raw[i], abs(value - baseline) > abs(amplitude) {
                amplitude = value - baseline
                fiducialIndex = i
            }
            if let derivative = derivatives[i] { slope = max(slope, abs(derivative)) }
        }
        return Candidate(peakIndex: peakIndex, level: level,
                         fiducialIndex: fiducialIndex, amplitude: amplitude, slope: slope)
    }
}

private struct Candidate {
    let peakIndex: Int
    let level: Double
    let fiducialIndex: Int
    let amplitude: Double
    let slope: Double
}

/// Second-order section in transposed direct form II, coefficients from the
/// bilinear-transformed Butterworth prototype (Q = 1/√2).
private struct Biquad {
    let b0, b1, b2, a1, a2: Double
    var z1 = 0.0
    var z2 = 0.0

    static func lowPass(cutoff: Double, sampleRate: Double) -> Biquad {
        let (cosine, alpha, a0) = terms(cutoff: cutoff, sampleRate: sampleRate)
        return Biquad(b0: (1 - cosine) / 2 / a0, b1: (1 - cosine) / a0, b2: (1 - cosine) / 2 / a0,
                      a1: -2 * cosine / a0, a2: (1 - alpha) / a0)
    }

    static func highPass(cutoff: Double, sampleRate: Double) -> Biquad {
        let (cosine, alpha, a0) = terms(cutoff: cutoff, sampleRate: sampleRate)
        return Biquad(b0: (1 + cosine) / 2 / a0, b1: -(1 + cosine) / a0, b2: (1 + cosine) / 2 / a0,
                      a1: -2 * cosine / a0, a2: (1 - alpha) / a0)
    }

    private static func terms(cutoff: Double, sampleRate: Double)
        -> (cosine: Double, alpha: Double, a0: Double) {
        // Above Nyquist the section would fold; clamp so a low sample rate
        // degrades the band edge instead of producing nonsense coefficients.
        let omega = 2 * Double.pi * min(cutoff, sampleRate / 2 * 0.99) / sampleRate
        let alpha = sin(omega) * 0.5 * 2.0.squareRoot()
        return (cos(omega), alpha, 1 + alpha)
    }

    mutating func filter(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

/// Fixed-capacity circular buffer addressed by absolute sample index — the shape
/// every look-back in the detector needs. Out-of-range reads return nil rather
/// than trapping, so the first samples after a reset need no special casing.
private struct Ring {
    private var values: [Double]
    private var written = 0

    init(capacity: Int) {
        values = Array(repeating: 0, count: capacity)
    }

    mutating func append(_ value: Double) {
        values[written % values.count] = value
        written += 1
    }

    subscript(index: Int) -> Double? {
        guard index >= 0, index < written, written - index <= values.count else { return nil }
        return values[index % values.count]
    }
}
