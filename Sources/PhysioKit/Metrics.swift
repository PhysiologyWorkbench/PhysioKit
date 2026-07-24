import Accelerate

/// Time-domain HRV metrics over a sequence of RR intervals (milliseconds).
/// Pure and side-effect-free; `nil` means not-yet-computable (an empty sequence,
/// or fewer than two intervals for the difference/spread metrics). See
/// `PROVENANCE.md` for the definitions. Computed via vDSP.

/// Mean RR interval. `nil` for an empty sequence.
public func meanRR(_ xs: [Double]) -> Double? {
    guard !xs.isEmpty else { return nil }
    return vDSP.mean(xs)
}

/// RMSSD — root mean square of successive RR-interval differences. Needs ≥2.
public func rmssd(_ xs: [Double]) -> Double? {
    guard xs.count >= 2 else { return nil }
    let diffs = vDSP.subtract(Array(xs.dropFirst()), Array(xs.dropLast()))
    return vDSP.rootMeanSquare(diffs)
}

/// SDNN — population standard deviation of the RR intervals. Needs ≥2.
public func sdnn(_ xs: [Double]) -> Double? {
    guard xs.count >= 2 else { return nil }
    let mean = vDSP.mean(xs)
    let meanSquare = vDSP.meanSquare(xs)
    let variance = meanSquare - mean * mean
    return variance > 0 ? variance.squareRoot() : 0
}
