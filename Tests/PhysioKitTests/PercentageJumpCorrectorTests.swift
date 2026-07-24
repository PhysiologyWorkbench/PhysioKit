import Testing
@testable import PhysioKit

struct PercentageJumpCorrectorTests {
    @Test func normalSequencePassesThroughUnchanged() {
        var c = PercentageJumpCorrector(threshold: 0.2, bufferSize: 3)
        let rr = [800.0, 810, 790, 805, 795, 800]
        let out = rr.map { c.accept($0) }
        #expect(out.allSatisfy { !$0.isArtifact })
        #expect(out.map(\.valueMs) == rr)
    }

    @Test func missedBeatIsCorrectedToLocalExpectation() {
        var c = PercentageJumpCorrector(threshold: 0.2, bufferSize: 3)
        for v in [800.0, 810, 790] { _ = c.accept(v) }   // warm-up, median 800
        let missed = c.accept(1600)                       // deviation 1.0
        #expect(missed.isArtifact)
        #expect(missed.valueMs == 800)
        // The artifact did not poison the expectation: a normal beat follows clean.
        let next = c.accept(805)
        #expect(!next.isArtifact)
        #expect(next.valueMs == 805)
    }

    @Test func ectopicShortThenLongBothCorrected() {
        var c = PercentageJumpCorrector(threshold: 0.2, bufferSize: 3)
        for v in [800.0, 810, 790] { _ = c.accept(v) }
        let short = c.accept(500)   // deviation 0.375
        let long = c.accept(1100)   // deviation 0.375
        #expect(short.isArtifact)
        #expect(long.isArtifact)
        #expect(short.valueMs == 800)
        #expect(long.valueMs == 800)
    }

    @Test func warmupAcceptsWildValues() {
        var c = PercentageJumpCorrector(threshold: 0.2, bufferSize: 3)
        let a = c.accept(800)
        let b = c.accept(2000)   // still within warm-up (buffer not full)
        #expect(!a.isArtifact)
        #expect(!b.isArtifact)
        #expect(b.valueMs == 2000)
    }

    @Test func resetClearsContext() {
        var c = PercentageJumpCorrector(threshold: 0.2, bufferSize: 3)
        for v in [800.0, 810, 790] { _ = c.accept(v) }
        c.reset()
        let after = c.accept(1600)   // buffer empty again → warm-up accept
        #expect(!after.isArtifact)
        #expect(after.valueMs == 1600)
    }
}
