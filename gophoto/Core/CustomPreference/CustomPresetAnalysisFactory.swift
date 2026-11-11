//
//  CustomPresetAnalysisFactory.swift
//  gophoto
//
//  Builds the camera targets (`PresetAnalysis`) of a custom preference from its subject placement
//  and camera angle, in the same shape a photo analysis has, so the guided camera, the shot size
//  picker and session validation work unchanged:
//  - standing: full body, three-quarter and half body variants (`shotVariants`);
//  - sitting: a full-body variant (`postureVariants`).
//
//  The analysis is derived, never stored: it is rebuilt from the style whenever the preference is
//  loaded, so it always matches the current `PresetAnalysis.currentVersion`.
//

import CoreGraphics
import Foundation

nonisolated enum CustomPresetAnalysisFactory {

    static func makeAnalysis(for style: CustomPreferenceStyle, analyzedAt: Date = Date()) -> PresetAnalysis {
        let standing = Dictionary(uniqueKeysWithValues: Framing.standing.map { framing in
            (framing.shot.rawValue, variant(framing, style: style, analyzedAt: analyzedAt))
        })
        let sitting = variant(.sittingFull, style: style, analyzedAt: analyzedAt)

        // The whole preset carries the standing full body's targets (what the analysis of a
        // photo set would report for its widest shot), plus every variant.
        var analysis = variant(.standingFull, style: style, analyzedAt: analyzedAt)
        analysis.photoCount = 0
        analysis.subjectPhotoCount = 0
        analysis.shotSize = nil
        analysis.shotVariants = standing
        analysis.postureVariants = [BodyPosture.sitting.rawValue: sitting]
        return analysis
    }

    /// Where the subject's box sits for `placement` in a full-body standing frame (normalized,
    /// origin top-left). Also used to draw the placement cards, so the picture matches the guide.
    static func subjectBox(for placement: SubjectPlacement) -> CGRect {
        Framing.standingFull.box(for: placement)
    }

    // MARK: Variants

    private static func variant(_ framing: Framing, style: CustomPreferenceStyle, analyzedAt: Date) -> PresetAnalysis {
        let target = AngleTarget(style.angle)
        // One synthetic reference per variant: `defaultShot` then ranks them all equal and picks
        // the widest (full body), as it does for a photo set with one photo per shot size.
        var analysis = PresetAnalysis(analyzedAt: analyzedAt,
                                      photoCount: 1,
                                      subjectBox: framing.box(for: style.placement),
                                      subjectPhotoCount: 1,
                                      angle: .match(category: target.category.rawValue, pitchDown: target.pitchDown))
        analysis.angleCounts = [target.category.rawValue: 1]
        analysis.angleDeterminedCount = 1
        analysis.angleLeadingShare = 1

        analysis.eyeElevation = target.eyeElevation
        analysis.eyeOffsetFaces = target.eyeOffsetFaces
        analysis.heightLevel = target.heightLevel.rawValue
        let side = target.eyeSide(framing: framing.shot.framing)
        analysis.eyeSide = side.rawValue
        analysis.eyeSideSource = PresetAnalysis.EyeSideSource.taste.rawValue
        analysis.eyeAboveShare = side == .above ? 1 : 0
        analysis.eyeSidePhotoCount = 1

        analysis.shotSize = framing.shot.rawValue
        analysis.framing = framing.shot.framing.rawValue
        analysis.clippedTop = false
        analysis.clippedBottom = framing.isCutAtBottom
        analysis.faceHeight = framing.faceHeight
        analysis.cutLevel = framing.cutLevel
        return analysis
    }

    // MARK: Framing per shot size

    /// Body size and position in the frame for one shot size, chosen to match typical reference
    /// photos of that shot size (same basis as `PersonDetector`: full body box, origin top-left).
    private struct Framing {
        let shot: PresetAnalysis.ShotSize
        let top: Double
        let height: Double
        let width: Double
        /// Face height as a share of the frame height.
        let faceHeight: Double
        /// Half body only: where the frame cuts the body (see `PresetAnalysis.cutLevel`).
        var cutLevel: String?

        /// Three-quarter and half body photos are cut by the frame bottom.
        var isCutAtBottom: Bool { top + height >= 1 }

        static let standingFull = Framing(shot: .full, top: 0.14, height: 0.72, width: 0.24, faceHeight: 0.075)
        static let threeQuarter = Framing(shot: .threeQuarter, top: 0.08, height: 0.92, width: 0.36, faceHeight: 0.11)
        static let half = Framing(shot: .half, top: 0.08, height: 0.92, width: 0.52, faceHeight: 0.16, cutLevel: "chest")
        /// A seated person is about `PresetAnalysis.seatedHeightRatio` of their standing height.
        static let sittingFull = Framing(shot: .full, top: 0.26, height: 0.72 * PresetAnalysis.seatedHeightRatio,
                                         width: 0.34, faceHeight: 0.085)

        /// The standing shot sizes the camera offers, widest first.
        static let standing: [Framing] = [.standingFull, .threeQuarter, .half]

        func box(for placement: SubjectPlacement) -> CGRect {
            let midX = placement.centerX(boxWidth: width)
            return CGRect(x: midX - width / 2, y: top, width: width, height: height)
        }
    }

    // MARK: Camera angle targets

    private enum HeightLevel: String {
        case aboveHead, eye, hip
    }

    /// Camera height and phone tilt for one angle, in the units `PresetAnalysis` uses:
    /// - `eyeOffsetFaces` / `eyeElevation`: camera vs the subject's eyes (+ = above);
    /// - `pitchDown`: phone pitch (`DeviceTilt`, + = tilted down).
    private struct AngleTarget {
        let category: CameraAngleCategory
        let eyeElevation: Double
        let eyeOffsetFaces: Double
        let pitchDown: Double
        let heightLevel: HeightLevel

        init(_ angle: CameraAngleStyle) {
            switch angle {
            case .eyeLevel:
                self.init(category: .eyeLevel, eyeElevation: 0, eyeOffsetFaces: 0, pitchDown: 0, heightLevel: .eye)
            case .lowAngle:
                self.init(category: .lowAngle, eyeElevation: -20, eyeOffsetFaces: -3.5, pitchDown: -12, heightLevel: .hip)
            case .highAngle:
                self.init(category: .highAngle, eyeElevation: 20, eyeOffsetFaces: 1.5, pitchDown: 15, heightLevel: .aboveHead)
            }
        }

        private init(category: CameraAngleCategory, eyeElevation: Double, eyeOffsetFaces: Double, pitchDown: Double,
                     heightLevel: HeightLevel) {
            self.category = category
            self.eyeElevation = eyeElevation
            self.eyeOffsetFaces = eyeOffsetFaces
            self.pitchDown = pitchDown
            self.heightLevel = heightLevel
        }

        /// Above or below the eyes; exactly at eye level the PRD framing rule decides
        /// (full body → below, cut framings → above).
        func eyeSide(framing: FramingCategory) -> PresetAnalysis.EyeSide {
            if eyeOffsetFaces > 0 { return .above }
            if eyeOffsetFaces < 0 { return .below }
            return framing == .fullBody ? .below : .above
        }
    }
}

// MARK: - Placement geometry

private extension SubjectPlacement {
    /// Gap between the subject and the frame edge for "near the edge" (not touching it).
    static let edgeGap = 0.03

    /// Horizontal centre of a subject box `boxWidth` wide, kept inside the frame.
    func centerX(boxWidth: Double) -> Double {
        let halfWidth = boxWidth / 2
        let wanted: Double = switch self {
        case .ruleOfThirds: 1.0 / 3.0                       // left vertical third line
        case .central: 0.5
        case .offCentered: 0.42                              // a little left of the dead centre
        case .edgeProximity: halfWidth + Self.edgeGap        // close to the left edge
        case .rightSide: 0.72                                // negative space on the left
        case .leftSide: 0.28
        case .edgeTouching: 1 - halfWidth                    // touching the right edge
        }
        return min(max(wanted, halfWidth), 1 - halfWidth)
    }
}
