import Testing
@testable import PhysioKit

struct MetricsTests {
    @Test func meanIsNilForEmpty() {
        #expect(meanRR([]) == nil)
    }

    @Test func meanOfIntervals() {
        #expect(meanRR([800, 820, 810]) == 810)
    }

    @Test func rmssdNeedsTwoIntervals() {
        #expect(rmssd([]) == nil)
        #expect(rmssd([800]) == nil)
    }

    @Test func rmssdOfKnownSequence() {
        // diffs [20, -10] → squares [400, 100] → mean 250 → √250
        let r = try! #require(rmssd([800, 820, 810]))
        #expect(abs(r - 250.0.squareRoot()) < 1e-9)
    }

    @Test func sdnnNeedsTwoIntervals() {
        #expect(sdnn([]) == nil)
        #expect(sdnn([800]) == nil)
    }

    @Test func sdnnIsPopulationStdDev() {
        // mean 810, deviations [-10, 10, 0] → var 200/3 → √66.6…
        let s = try! #require(sdnn([800, 820, 810]))
        #expect(abs(s - (200.0 / 3.0).squareRoot()) < 1e-9)
    }

    @Test func sdnnOfConstantIsZero() {
        #expect(sdnn([800, 800, 800]) == 0)
    }
}
