import Testing
import Foundation
@testable import PhysioKit

struct RespirationTests {
    /// R-wave amplitudes at beat times, modulated at `breathsPerMinute` — what the
    /// detector hands over when someone is breathing steadily. Beat times carry a
    /// little jitter so the series is genuinely uneven.
    private func series(seconds: Double, rrSeconds: Double, breathsPerMinute: Double,
                        depth: Double = 0.15, noise: Double = 0)
        -> (amplitudes: [Double], times: [Double]) {
        var generator = SystemRandomNumberGenerator()
        var amplitudes: [Double] = []
        var times: [Double] = []
        var t = 0.0
        while t < seconds {
            let modulation = sin(2 * .pi * breathsPerMinute / 60 * t)
            amplitudes.append(1000 * (1 + depth * modulation)
                + noise * Double.random(in: -1...1, using: &generator))
            times.append(t)
            t += rrSeconds * Double.random(in: 0.97...1.03, using: &generator)
        }
        return (amplitudes, times)
    }

    @Test func recoversAKnownBreathingRate() {
        for truth in [10.0, 15.0, 20.0] {
            let (amplitudes, times) = series(seconds: 120, rrSeconds: 0.8,
                                             breathsPerMinute: truth)
            let rate = respiratoryRate(amplitudes: amplitudes, times: times)
            #expect(rate != nil)
            #expect(abs((rate ?? 0) - truth) < 1)
        }
    }

    @Test func survivesModestNoiseOnTheAmplitudes() {
        let (amplitudes, times) = series(seconds: 120, rrSeconds: 0.8,
                                         breathsPerMinute: 15, noise: 60)
        let rate = respiratoryRate(amplitudes: amplitudes, times: times)

        #expect(abs((rate ?? 0) - 15) < 1.5)
    }

    @Test func needsThreeCyclesOfTheSlowestBreath() {
        // 20 s cannot hold three 0.1 Hz cycles, whatever is in it.
        let (amplitudes, times) = series(seconds: 20, rrSeconds: 0.8, breathsPerMinute: 15)

        #expect(respiratoryRate(amplitudes: amplitudes, times: times) == nil)
    }

    @Test func refusesToReadARateOffNoise() {
        var generator = SystemRandomNumberGenerator()
        let times = stride(from: 0.0, to: 120.0, by: 0.8).map { $0 }
        let amplitudes = times.map { _ in 1000 + Double.random(in: -100...100, using: &generator) }

        #expect(respiratoryRate(amplitudes: amplitudes, times: times) == nil)
    }

    @Test func rejectsMismatchedOrTinyInput() {
        #expect(respiratoryRate(amplitudes: [1, 2, 3], times: [0, 1]) == nil)
        #expect(respiratoryRate(amplitudes: [], times: []) == nil)
    }
}
