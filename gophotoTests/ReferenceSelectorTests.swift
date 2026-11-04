import Testing
@testable import gophoto

/// The fallback choice for "framing F, posture P" (pure functions: no models, no UI).
struct ReferenceSelectorTests {

    private func reading(_ posture: Posture, confidence: Double = 0.9,
                         visibility: AttributeVisibility = .visible) -> PostureReading {
        PostureReading(posture: .init(value: posture, confidence: confidence, visibility: visibility),
                       torsoOrientation: .init(value: .unknown, confidence: 0, visibility: .notVisible),
                       sitting: nil)
    }

    private func photo(_ id: String, _ shot: PresetAnalysis.ShotSize?, _ reading: PostureReading?) -> ReferenceCandidate {
        ReferenceCandidate(photoID: id, shot: shot, reading: reading)
    }

    private func level(_ photos: [ReferenceCandidate], _ shot: PresetAnalysis.ShotSize,
                       _ posture: Posture) -> ReferenceMatchLevel {
        ReferenceSelector.level(of: ReferenceSelector.partition(photos, shot: shot, posture: posture))
    }

    // MARK: Tiers

    @Test func exactWhenFramingAndPostureMatch() {
        let photos = [photo("a", .full, reading(.sitting)), photo("b", .half, reading(.standing))]
        #expect(level(photos, .full, .sitting) == .exact)
    }

    @Test func samePostureWhenOnlyOtherFramingIsSeated() {
        // The case this feature is for: seated half body only, full body requested.
        let photos = [photo("a", .half, reading(.sitting))]
        #expect(level(photos, .full, .sitting) == .samePosture)
    }

    @Test func sameFramingWhenOnlyStandingFullBody() {
        let photos = [photo("a", .full, reading(.standing))]
        #expect(level(photos, .full, .sitting) == .sameFraming)
    }

    @Test func combinedWhenBothTiersExist() {
        let photos = [photo("a", .half, reading(.sitting)), photo("b", .full, reading(.standing))]
        let part = ReferenceSelector.partition(photos, shot: .full, posture: .sitting)
        #expect(part.samePosture == ["a"])
        #expect(part.sameFraming == ["b"])
        #expect(ReferenceSelector.level(of: part) == .combined)
    }

    @Test func defaultWithoutAnyUsablePhoto() {
        #expect(level([], .full, .sitting) == .default)
        // A photo without a framing is no reference at all.
        #expect(level([photo("a", nil, reading(.sitting))], .full, .sitting) == .default)
    }

    // MARK: Thresholds

    @Test func lowConfidencePostureIsNotAPostureReference() {
        let photos = [photo("a", .full, reading(.sitting, confidence: ReferenceThresholds.minConfidence - 0.01))]
        // Not believed as sitting, so only its composition is usable.
        #expect(level(photos, .full, .sitting) == .sameFraming)
    }

    @Test func confidenceAtTheThresholdIsUsed() {
        let photos = [photo("a", .full, reading(.sitting, confidence: ReferenceThresholds.minConfidence))]
        #expect(level(photos, .full, .sitting) == .exact)
    }

    @Test func notVisiblePostureIsNotUsed() {
        let photos = [photo("a", .full, reading(.sitting, visibility: .notVisible))]
        #expect(level(photos, .full, .sitting) == .sameFraming)
    }

    @Test func attributeUsabilityFollowsTheSameThreshold() {
        let weak = ClassifiedAttribute(value: SupportSurface.chair, confidence: 0.59, visibility: .visible)
        let hidden = ClassifiedAttribute(value: SupportSurface.chair, confidence: 0.9, visibility: .notVisible)
        let good = ClassifiedAttribute(value: SupportSurface.chair, confidence: 0.6, visibility: .partiallyVisible)
        #expect(!weak.isUsable)
        #expect(!hidden.isUsable)
        #expect(good.isUsable)
    }

    // MARK: Standing stays as it was

    @Test func unreadPostureCountsAsStandingWhenStandingIsRequested() {
        // Before postures existed every photo was a standing photo.
        let photos = [photo("a", .full, nil), photo("b", .full, reading(.unknown, confidence: 0.2))]
        let part = ReferenceSelector.partition(photos, shot: .full, posture: .standing)
        #expect(part.exact == ["a", "b"])
    }

    @Test func unreadPostureIsNotASeatedReference() {
        let photos = [photo("a", .full, nil)]
        let part = ReferenceSelector.partition(photos, shot: .full, posture: .sitting)
        #expect(part.exact.isEmpty && part.samePosture.isEmpty)
        #expect(part.sameFraming == ["a"])   // its composition still transfers
    }

    @Test func seatedPhotoIsNotAStandingReference() {
        let photos = [photo("a", .full, reading(.sitting))]
        #expect(level(photos, .full, .standing) == .sameFraming)
    }

    // MARK: Keys and the level table

    @Test func levelTable() {
        #expect(ReferenceSelector.level(hasExact: true, hasSamePosture: true, hasSameFraming: true) == .exact)
        #expect(ReferenceSelector.level(hasExact: false, hasSamePosture: true, hasSameFraming: true) == .combined)
        #expect(ReferenceSelector.level(hasExact: false, hasSamePosture: true, hasSameFraming: false) == .samePosture)
        #expect(ReferenceSelector.level(hasExact: false, hasSamePosture: false, hasSameFraming: true) == .sameFraming)
        #expect(ReferenceSelector.level(hasExact: false, hasSamePosture: false, hasSameFraming: false) == .default)
    }

    @Test func variantKeyIsStable() {
        #expect(ReferenceSelector.variantKey(.samePosture, shot: .full, posture: .sitting) == "samePosture:full:sitting")
    }
}
