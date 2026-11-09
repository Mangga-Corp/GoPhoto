//
//  PhasedSubjectPicker.swift
//  gophoto
//
//  Phased guide: who is the subject. One clear person → locked automatically after a stable
//  moment; several → the photographer taps one (non-persons dimmed). After the lock the tracker in
//  `PersonDetector` follows that person (strict: never the largest one instead). A short loss is
//  silent; a long one asks "Point back at the person"; on return only a candidate near the last
//  place is taken back, otherwise the photographer chooses again. Pure logic.
//
import CoreGraphics
import Foundation

nonisolated struct PhasedSubjectPicker: Sendable, Equatable {

    enum State: Equatable, Sendable {
        /// Nobody locked yet (or the guide started over).
        case searching
        case locked
        /// The locked person disappeared at `since`.
        case lost(since: TimeInterval)
        /// The photographer must tap a person.
        case choosing
    }

    enum Action: Equatable, Sendable {
        case none
        case lock(CGRect)
    }

    struct Output: Equatable, Sendable {
        var action: Action = .none
        var instruction: PhasedInstruction?
        /// Dim everything that is not a person (selection UI).
        var dims = false
        /// The subject is a different person than before (the guide starts over).
        var newSubject = false
    }

    /// People smaller than this (frame height) are background and never make the scene ambiguous.
    static let minCandidateHeight: CGFloat = 0.12
    static let autoLockDwell: TimeInterval = 0.6
    static let reacquireDwell: TimeInterval = 0.3
    /// After the "point back" message, this much longer without the old place → choose again.
    static let chooseAfterLoss: TimeInterval = 2.0

    var lossGrace: TimeInterval = PhasedParameters.standard.lossGrace
    var reacquireDistance: Double = PhasedParameters.standard.reacquireDistance

    private(set) var state: State = .searching
    private(set) var lastBox: CGRect?
    private var pendingBox: CGRect?
    private var pendingSince: TimeInterval?
    /// A lock was requested; the detector confirms it on the next detections.
    private var requested: CGRect?

    mutating func reset() {
        state = .searching
        lastBox = nil
        pendingBox = nil
        pendingSince = nil
        requested = nil
    }

    private func isNear(_ a: CGRect, _ b: CGRect?) -> Bool {
        guard let b, b.height > 0 else { return false }
        let d = hypot(Double(a.midX - b.midX), Double(a.midY - b.midY))
        let ratio = Double(a.height / b.height)
        return d < reacquireDistance && ratio > 0.65 && ratio < 1.5
    }

    /// Same candidate as the pending one (small movement allowed) for `dwell` seconds.
    private mutating func stable(_ box: CGRect, now: TimeInterval, dwell: TimeInterval) -> Bool {
        if let p = pendingBox, hypot(Double(box.midX - p.midX), Double(box.midY - p.midY)) < 0.08 {
            pendingBox = box
            return now - (pendingSince ?? now) >= dwell
        }
        pendingBox = box
        pendingSince = now
        return false
    }

    mutating func update(candidates: [CGRect], locked: Bool, lockedBox: CGRect?, now: TimeInterval) -> Output {
        var out = Output()
        if locked {
            if case .locked = state {} else { pendingBox = nil; pendingSince = nil }
            requested = nil
            state = .locked
            lastBox = lockedBox ?? lastBox
            return out
        }
        let people = candidates.filter { $0.height >= Self.minCandidateHeight }
        switch state {
        case .locked:
            state = .lost(since: now)
            pendingBox = nil; pendingSince = nil
        case .lost(let since):
            let near = people.filter { isNear($0, lastBox) }
            if near.count == 1, stable(near[0], now: now, dwell: Self.reacquireDwell) {
                requested = near[0]
                out.action = .lock(near[0])
            } else if near.isEmpty {
                pendingBox = nil; pendingSince = nil
            }
            let elapsed = now - since
            if elapsed >= lossGrace { out.instruction = .pointBack }
            if elapsed >= lossGrace + Self.chooseAfterLoss, !people.isEmpty, near.isEmpty {
                state = .choosing
            }
        case .searching:
            if people.count == 1 {
                if stable(people[0], now: now, dwell: Self.autoLockDwell) {
                    requested = people[0]
                    out.action = .lock(people[0])
                }
            } else if people.count >= 2 {
                state = .choosing
                pendingBox = nil; pendingSince = nil
            } else {
                pendingBox = nil; pendingSince = nil
            }
        case .choosing:
            break
        }
        if case .choosing = state {
            out.instruction = .tapPerson
            out.dims = true
        }
        return out
    }

    /// A tap on the preview (frame units): the smallest candidate that contains it.
    mutating func tap(_ point: CGPoint, candidates: [CGRect]) -> Output {
        var out = Output()
        let hits = candidates.filter { $0.insetBy(dx: -0.02, dy: -0.02).contains(point) }
        guard let box = hits.min(by: { $0.width * $0.height < $1.width * $1.height }) else { return out }
        out.newSubject = !isNear(box, lastBox)
        requested = box
        lastBox = box
        state = .searching
        pendingBox = nil; pendingSince = nil
        out.action = .lock(box)
        return out
    }
}
