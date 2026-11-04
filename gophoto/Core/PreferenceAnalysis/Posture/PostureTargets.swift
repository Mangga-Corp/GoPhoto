import Foundation
import CoreGraphics

/// Posture-specific numbers the guide uses where it used to assume a standing person.
nonisolated enum PostureTargets {

    /// Share of the person's box that must be in the frame before a full-body shot counts as
    /// "close enough" (framing step, rule E1).
    static let standingFullBodyMinRatio = 0.7
    static let sittingFullBodyMinRatio = 0.65

    /// Height of a seated person with their legs in the frame, as a share of their standing
    /// height, by what they sit on (floor: shortest; bench: legs hang down).
    static func seatedHeightRatio(support: SupportSurface?) -> Double {
        switch support {
        case .chair: 0.72
        case .floor: 0.55
        case .elevated: 0.78
        case .unknown, nil: 0.70
        }
    }

    static func fullBodyMinRatio(posture: String?) -> Double {
        posture == Posture.sitting.rawValue ? sittingFullBodyMinRatio : standingFullBodyMinRatio
    }

    /// Body height (metres) for the distance estimate: the standing height, shortened if seated.
    static func bodyHeightMeters(standing: Double, posture: String?, support: String?) -> Double {
        guard posture == Posture.sitting.rawValue else { return standing }
        return standing * seatedHeightRatio(support: support.flatMap(SupportSurface.init(rawValue:)))
    }

    /// `box` shrunk to a seated person's height around its centre (width unchanged).
    static func seatedBox(from box: CGRect, support: SupportSurface?) -> CGRect {
        let height = box.height * seatedHeightRatio(support: support)
        return CGRect(x: box.minX, y: box.midY - height / 2, width: box.width, height: height)
    }
}
