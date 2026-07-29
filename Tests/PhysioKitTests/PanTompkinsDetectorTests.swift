import Testing
import Foundation
@testable import PhysioKit

/// A synthetic single-lead ECG: a narrow R spike per beat with a broader, slower
/// T wave 250 ms behind it — the pairing the detector's T-wave discrimination
/// has to survive — plus a slow baseline wander the band-pass must remove.
/// Amplitudes are in µV, matching what the H10 delivers.
func syntheticECG(sampleRate: Double, beats: Int, rrSeconds: Double,
                  rAmplitude: Double = 1000, tAmplitude: Double = 250) -> (signal: [Double], peaks: [Int]) {
    let total = Int(Double(beats + 1) * rrSeconds * sampleRate)
    var signal = [Double](repeating: 0, count: total)
    var peaks: [Int] = []
    for beat in 0..<beats {
        let peak = Int((Double(beat) + 0.5) * rrSeconds * sampleRate)
        guard peak < total else { break }
        peaks.append(peak)
        add(&signal, centre: peak, width: 0.010 * sampleRate, amplitude: rAmplitude)
        add(&signal, centre: peak + Int(0.250 * sampleRate), width: 0.060 * sampleRate,
            amplitude: tAmplitude)
    }
    for i in 0..<total {
        signal[i] += 200 * sin(2 * .pi * 0.15 * Double(i) / sampleRate)
    }
    return (signal, peaks)
}

private func add(_ signal: inout [Double], centre: Int, width: Double, amplitude: Double) {
    let span = Int(width * 4)
    for i in max(centre - span, 0)..<min(centre + span, signal.count) {
        let x = Double(i - centre) / width
        signal[i] += amplitude * exp(-0.5 * x * x)
    }
}

struct PanTompkinsDetectorTests {
    private let rate = 130.0

    @Test func findsEveryBeatPastTheLearningPhase() {
        let (signal, expected) = syntheticECG(sampleRate: rate, beats: 40, rrSeconds: 0.8)
        var detector = PanTompkinsDetector(sampleRate: rate)
        let detected = detector.accept(signal)

        // The first two seconds train the thresholds and emit nothing.
        let wanted = expected.filter { $0 >= Int(2 * rate) }
        #expect(detected.count == wanted.count)
        for (peak, truth) in zip(detected, wanted) {
            #expect(abs(peak.sampleIndex - truth) <= 3)
        }
    }

    @Test func reportsTheRWaveAmplitudeNotTheTWave() {
        let (signal, _) = syntheticECG(sampleRate: rate, beats: 20, rrSeconds: 0.8)
        var detector = PanTompkinsDetector(sampleRate: rate)
        let detected = detector.accept(signal)

        #expect(!detected.isEmpty)
        // Band-passing scales the spike down, but the R wave stays several times
        // the T wave it would be confused with.
        for peak in detected {
            #expect(peak.amplitude > 100)
        }
    }

    @Test func batchingChangesNothing() {
        let (signal, _) = syntheticECG(sampleRate: rate, beats: 30, rrSeconds: 0.8)
        var whole = PanTompkinsDetector(sampleRate: rate)
        var chunked = PanTompkinsDetector(sampleRate: rate)

        let atOnce = whole.accept(signal)
        // 73 samples is the H10's ECG frame.
        var piecemeal: [RPeak] = []
        var index = 0
        while index < signal.count {
            let end = min(index + 73, signal.count)
            piecemeal += chunked.accept(Array(signal[index..<end]))
            index = end
        }

        #expect(atOnce == piecemeal)
    }

    @Test func resetReturnsToAFreshDetector() {
        let (signal, _) = syntheticECG(sampleRate: rate, beats: 20, rrSeconds: 0.8)
        var detector = PanTompkinsDetector(sampleRate: rate)
        let first = detector.accept(signal)
        detector.reset()
        let second = detector.accept(signal)

        #expect(first == second)
    }

    @Test func recoversAMissedBeatBySearchBack() {
        var (signal, expected) = syntheticECG(sampleRate: rate, beats: 40, rrSeconds: 0.8)
        // Cut one R wave well past the learning phase down to 45 % — the
        // integrator sees amplitude squared, so its peak lands between the half
        // threshold and the main one, where only search-back can reach it.
        let weakened = expected[20]
        add(&signal, centre: weakened, width: 0.010 * rate, amplitude: -550)
        var detector = PanTompkinsDetector(sampleRate: rate)
        let detected = detector.accept(signal)

        #expect(detected.contains { abs($0.sampleIndex - weakened) <= 6 })
    }
}
