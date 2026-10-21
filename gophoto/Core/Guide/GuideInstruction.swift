//
//  GuideInstructions.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 13/10/26.
//
import CoreGraphics

nonisolated enum GuideInstruction: Equatable, Sendable, CaseIterable {
    case findPerson
    case moveCloser, moveFarther      // distance
    case moveLeft, moveRight          // horizontal
    case moveHigher, moveLower        // vertical
    case tiltUp, tiltDown             // camera angle: phone pitch vs the preset (after framing)
    case straighten                   // framing OK, phone crooked
    case holdStill                    // everything OK → take the photo

    // Phone tilt allowed for "Hold still": +- 2degree to become OK, +-3degree before it breaks
    static let straightEnter: Double = 2
    static let straightExit: Double = 3

    // Phone pitch vs the preset's angle: +-3 degree to become OK (PRD DBM-59), +-4 before it breaks
    static let angleEnter: Double = 3
    static let angleExit: Double = 4

    /// - Parameter pitchError: phone pitch minus the preset's target pitch, degrees
    ///   (positive = phone tilted further DOWN than the target). Nil = no angle guidance.
    static func next(offset: FramingOffset?, roll: Double, pitchError: Double? = nil,
                     current: GuideInstruction) -> GuideInstruction {
        guard let offset else { return .findPerson }

        // Once framed, use the looser "exit" tolerances so small wobbles don't break it
        let isFramed = current.isTilt || current == .straighten || current == .holdStill
        let position = isFramed ? FramingTarget.positionExit : FramingTarget.positionEnter
        let size = isFramed ? FramingTarget.sizeExit : FramingTarget.sizeEnter

        let needsDistance = abs(offset.sizeRatio - 1) > size
        let needsHorizontal = abs(offset.dx) > position
        let needsVertical = abs(offset.dy) > position
        let angleLimit = isFramed ? angleExit : angleEnter
        let needsAngle = pitchError.map { abs($0) > angleLimit } ?? false

        // 1. Keep the current direction while it still needs fixing (no jumping around)
        if current.isDistance, needsDistance { return distance(offset) }
        if current.isHorizontal, needsHorizontal { return horizontal(offset) }
        if current.isVertical, needsVertical { return vertical(offset) }
        if current.isTilt, needsAngle, let pitchError { return tilt(pitchError) }

        // 2. Otherwise fix in priority order: distance -> left/right -> up/down -> camera angle
        if needsDistance { return distance(offset) }
        if needsHorizontal { return horizontal(offset) }
        if needsVertical { return vertical(offset) }
        if needsAngle, let pitchError { return tilt(pitchError) }

        // 3. Framing is OK -> is the phone straight?
        let straightLimit = current == .holdStill ? straightExit : straightEnter
        if abs(roll) > straightLimit { return .straighten }

        return .holdStill
    }

    // Directions are for the PHOTOGRAPHER holding the phone:
    // moving the phone right slides the person LEFT in the picture, and vice versa.
    private static func distance(_ o: FramingOffset) -> GuideInstruction {
        o.sizeRatio < 1 ? .moveCloser : .moveFarther
    }
    private static func horizontal(_ o: FramingOffset) -> GuideInstruction {
        o.dx > 0 ? .moveRight : .moveLeft
    }
    private static func vertical(_ o: FramingOffset) -> GuideInstruction {
        o.dy > 0 ? .moveLower : .moveHigher
    }

    private static func tilt(_ pitchError: Double) -> GuideInstruction {
        pitchError > 0 ? .tiltUp : .tiltDown
    }

    private var isTilt: Bool { self == .tiltUp || self == .tiltDown }
    private var isDistance: Bool { self == .moveCloser || self == .moveFarther }
    private var isHorizontal: Bool { self == .moveLeft || self == .moveRight }
    private var isVertical: Bool { self == .moveHigher || self == .moveLower }
}
