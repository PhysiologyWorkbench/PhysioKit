import Accelerate

/// Respiratory rate, in breaths per minute, from an ECG-derived amplitude series
/// — the R-wave amplitudes at their beat times (see `PROVENANCE.md`). Breathing
/// swings the heart's electrical axis and the chest's impedance, so the R waves
/// rise and fall with it; recovering the rate is finding that modulation's
/// frequency.
///
/// The series is unevenly sampled, at beats, so it is interpolated onto a uniform
/// grid, detrended, windowed and transformed, and the strongest component inside
/// `band` is taken with a parabolic fit for sub-bin resolution. `nil` when the
/// span is too short to hold three cycles of the slowest breath in `band`, when
/// there are too few beats, or when no component stands clearly above the rest of
/// the band — a rate read off noise would be worse than none.
///
/// `times` are seconds on any common origin and must be non-decreasing.
public func respiratoryRate(amplitudes: [Double], times: [Double],
                            band: ClosedRange<Double> = 0.1...0.5,
                            resampleRate: Double = 4) -> Double? {
    guard amplitudes.count == times.count, amplitudes.count >= 10,
          let first = times.first, let last = times.last else { return nil }
    let span = last - first
    guard span >= 3 / band.lowerBound else { return nil }

    let count = Int(span * resampleRate)
    let padded = nextPowerOfTwo(count)
    guard count >= 8 else { return nil }

    var grid = resampled(amplitudes: amplitudes, times: times,
                         count: count, resampleRate: resampleRate, origin: first)
    detrend(&grid)
    vDSP.multiply(grid, vDSP.window(ofType: Double.self, usingSequence: .hanningDenormalized,
                                    count: count, isHalfWindow: false),
                  result: &grid)
    grid += [Double](repeating: 0, count: padded - count)

    guard let dft = try? vDSP.DiscreteFourierTransform(
        previous: nil, count: padded, direction: .forward,
        transformType: .complexComplex, ofType: Double.self) else { return nil }
    let (real, imaginary) = dft.transform(real: grid,
                                          imaginary: [Double](repeating: 0, count: padded))
    let magnitudes = vDSP.hypot(real, imaginary)

    // Only the positive frequencies, and only inside the respiratory band.
    let binWidth = resampleRate / Double(padded)
    let bins = max(Int(band.lowerBound / binWidth), 1)...min(Int(band.upperBound / binWidth),
                                                             padded / 2 - 1)
    guard bins.lowerBound < bins.upperBound,
          let peak = bins.max(by: { magnitudes[$0] < magnitudes[$1] }) else { return nil }

    // White noise puts its largest band bin around 2–3 times the band mean; a
    // real breathing modulation reaches 8 and up even when shallow and noisy over
    // a one-minute window. Four separates them with margin either way.
    let mean = bins.reduce(0.0) { $0 + magnitudes[$1] } / Double(bins.count)
    guard magnitudes[peak] > 4 * mean else { return nil }

    return (Double(peak) + parabolicOffset(magnitudes, at: peak)) * binWidth * 60
}

/// Linear interpolation onto an evenly-spaced grid. The series is monotonic in
/// time, so one forward-moving cursor covers it.
private func resampled(amplitudes: [Double], times: [Double], count: Int,
                       resampleRate: Double, origin: Double) -> [Double] {
    var grid = [Double](repeating: 0, count: count)
    var cursor = 0
    for i in 0..<count {
        let t = origin + Double(i) / resampleRate
        while cursor + 2 < times.count, times[cursor + 1] < t { cursor += 1 }
        let (t0, t1) = (times[cursor], times[cursor + 1])
        let fraction = t1 > t0 ? (t - t0) / (t1 - t0) : 0
        grid[i] = amplitudes[cursor] + fraction * (amplitudes[cursor + 1] - amplitudes[cursor])
    }
    return grid
}

/// Removes the least-squares line, so a drifting electrode contact cannot put a
/// large low-frequency component under the band's lower edge and leak into it.
private func detrend(_ values: inout [Double]) {
    let n = Double(values.count)
    let meanIndex = (n - 1) / 2
    let meanValue = vDSP.mean(values)
    var covariance = 0.0
    var variance = 0.0
    for (i, value) in values.enumerated() {
        let dx = Double(i) - meanIndex
        covariance += dx * (value - meanValue)
        variance += dx * dx
    }
    let slope = variance > 0 ? covariance / variance : 0
    for i in values.indices {
        values[i] -= meanValue + slope * (Double(i) - meanIndex)
    }
}

/// Sub-bin peak position from a parabola through the peak and its neighbours.
private func parabolicOffset(_ magnitudes: [Double], at peak: Int) -> Double {
    guard peak > 0, peak + 1 < magnitudes.count else { return 0 }
    let (left, centre, right) = (magnitudes[peak - 1], magnitudes[peak], magnitudes[peak + 1])
    let curvature = left - 2 * centre + right
    return curvature < 0 ? 0.5 * (left - right) / curvature : 0
}

private func nextPowerOfTwo(_ n: Int) -> Int {
    var power = 1
    while power < n { power <<= 1 }
    return power
}
