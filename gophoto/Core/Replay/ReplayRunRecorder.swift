//
//  ReplayRunRecorder.swift
//  gophoto
//
//  appMode 2 testing: what happened in one replay run, by media time: subject lock / loss /
//  reacquisition, phase changes, reopens, instructions with durations, reversals, zoom intents,
//  pipeline counters, and which capabilities were (not) evaluated and why. Written as JSON (detail)
//  and one CSV row (summary). Counts are observations, not errors: a reopen is not a bug without
//  human annotation.
//
import Foundation

nonisolated enum ReplayScenario: String, CaseIterable, Identifiable, Sendable, Codable {
    /// Production pipeline on RGB only; missing sensors stay missing.
    case rgbObservation
    /// SIMULATED STATE: distance seeded as done once after the baseline; the controller decides after.
    case distanceLocked

    var id: String { rawValue }
    var title: String {
        switch self {
        case .rgbObservation: "RGB observation"
        case .distanceLocked: "Distance locked (simulation)"
        }
    }
    static let fixtureID = "distance-locked-v1"
}

nonisolated struct ReplayRunRecorder: Sendable {
    struct Mark: Codable, Sendable { var t: Double; var kind: String; var detail: String }
    struct Span: Codable, Sendable { var instruction: String; var from: Double; var to: Double; var seconds: Double }
    struct Capability: Codable, Sendable { var name: String; var evaluated: Bool; var why: String }

    let runID: String
    let startedAt: Date
    var config: [String: String]
    private(set) var marks: [Mark] = []
    private(set) var spans: [Span] = []
    private(set) var reversals = 0
    private(set) var reopens = 0
    private(set) var zoomIntents = 0
    private(set) var fixtureSeedTime: Double?
    private(set) var maskSeen = false
    private(set) var cropSeen = false
    private(set) var readySeen = false
    private(set) var lastTime = 0.0
    private var current: (instruction: String, from: Double)?
    private var lastMove: String?

    init(runID: String, config: [String: String]) {
        self.runID = runID
        self.startedAt = Date()
        self.config = config
    }

    mutating func time(_ t: Double) { lastTime = max(lastTime, t) }

    mutating func mark(_ kind: String, _ detail: String, at t: Double) {
        time(t)
        marks.append(Mark(t: t, kind: kind, detail: detail))
        if kind == "reopen" { reopens += 1 }
        if kind == "fixture", fixtureSeedTime == nil { fixtureSeedTime = t }
    }

    /// The shown instruction changed at media time `t` ("none" = no instruction).
    mutating func instruction(_ name: String, at t: Double) {
        time(t)
        if let current, current.instruction != name {
            spans.append(Span(instruction: current.instruction, from: current.from, to: t, seconds: t - current.from))
        }
        if current?.instruction != name { current = (name, t) }
        // Reversal: a distance instruction followed by the opposite one.
        let distance = ["moveCloser", "moveBack", "moveFarther"]
        if distance.contains(name) {
            if let lastMove, lastMove != name { reversals += 1 }
            lastMove = name
        }
        if name == "takePhoto" || name == "holdStill" { readySeen = true }
    }

    mutating func zoomIntent(_ zoom: Double, at t: Double) {
        zoomIntents += 1
        if zoomIntents <= 20 { mark("zoom intent", String(format: "%.2f× (not applied: replay)", zoom), at: t) }
    }

    mutating func sawMask() { maskSeen = true }
    mutating func sawCrop() { cropSeen = true }

    /// Closes the open instruction at the end of the run.
    mutating func finish(at t: Double) {
        time(t)
        if let current { spans.append(Span(instruction: current.instruction, from: current.from, to: lastTime,
                                           seconds: lastTime - current.from)) }
        current = nil
    }

    func capabilities(scenario: ReplayScenario, phased: Bool) -> [Capability] {
        [
            Capability(name: "person detection + tracking", evaluated: true, why: "RGB frames through the production detector"),
            Capability(name: "subject mask / coverage", evaluated: maskSeen,
                       why: maskSeen ? "instance mask seen on the subject" : (phased ? "no mask on a locked subject" : "Main guides do not use the mask")),
            Capability(name: "distance", evaluated: true,
                       why: scenario == .distanceLocked
                       ? "SIMULATED lock (fixture \(ReplayScenario.fixtureID)); only the reopen logic on RGB is observed"
                       : "RGB size vs the preset reference only; the video's zoom and real distance are unknown"),
            Capability(name: "phone height (vantage)", evaluated: false, why: "no field of view and no motion sensor in the video"),
            Capability(name: "tilt", evaluated: false, why: "no motion sensor in the video"),
            Capability(name: "depth", evaluated: false, why: "the video has no depth data"),
            Capability(name: "zoom", evaluated: false, why: "never applied to a video (\(zoomIntents) intents logged)"),
            Capability(name: "auto crop geometry", evaluated: cropSeen,
                       why: cropSeen ? "geometry only, on a simulated 48 MP source; no image-quality claim" : "final framing phase not reached"),
            Capability(name: "final readiness", evaluated: false,
                       why: readySeen ? "a ready state appeared, but it rests on missing sensors / simulation" : "needs phone height and tilt"),
        ]
    }

    // MARK: Output

    static let csvHeader = "run,started,video,sha256,duration_s,size,guide,framing,preset,shot,scenario,fixture,seed_t,end_t,instructions,reversals,reopens,locks,losses,reacquired,phase_changes,zoom_intents,shown,analysed,dropped_busy,late,lag_mean_ms,lag_max_ms,analysis_mean_ms,sensors"

    func csvRow(stats: ReplayPipelineStats, scenario: ReplayScenario) -> String {
        func c(_ s: String?) -> String { "\"\((s ?? "").replacingOccurrences(of: "\"", with: "'"))\"" }
        let count: (String) -> Int = { kind in marks.filter { $0.kind == kind }.count }
        let fields: [String] = [
            c(runID), c(ISO8601DateFormatter().string(from: startedAt)), c(config["video"]), c(config["sha256"]),
            c(config["duration"]), c(config["size"]), c(config["guide"]), c(config["framing"]), c(config["preset"]),
            c(config["shot"]), c(scenario.rawValue), c(scenario == .distanceLocked ? ReplayScenario.fixtureID : ""),
            fixtureSeedTime.map { String(format: "%.3f", $0) } ?? "", String(format: "%.3f", lastTime),
            "\(spans.count)", "\(reversals)", "\(reopens)", "\(count("lock"))", "\(count("loss"))", "\(count("reacquire"))",
            "\(count("phase"))", "\(zoomIntents)", "\(stats.shown)", "\(stats.analysed)", "\(stats.droppedBusy)",
            "\(stats.lateFrames)", String(format: "%.1f", stats.lagMean * 1000), String(format: "%.1f", stats.lagMax * 1000),
            String(format: "%.1f", stats.analysisMean * 1000), c(config["sensors"]),
        ]
        return fields.joined(separator: ",")
    }

    func json(stats: ReplayPipelineStats, scenario: ReplayScenario, phased: Bool) -> Data? {
        struct Doc: Codable {
            var run: String; var started: String; var config: [String: String]; var scenario: String
            var fixture: String?; var fixtureSeedTime: Double?; var endTime: Double
            var marks: [Mark]; var instructions: [Span]; var reversals: Int; var reopens: Int; var zoomIntents: Int
            var pipeline: [String: Double]; var capabilities: [Capability]; var note: String
        }
        let doc = Doc(run: runID, started: ISO8601DateFormatter().string(from: startedAt), config: config,
                      scenario: scenario.rawValue, fixture: scenario == .distanceLocked ? ReplayScenario.fixtureID : nil,
                      fixtureSeedTime: fixtureSeedTime, endTime: lastTime, marks: marks, instructions: spans,
                      reversals: reversals, reopens: reopens, zoomIntents: zoomIntents,
                      pipeline: ["shown": Double(stats.shown), "analysed": Double(stats.analysed),
                                 "droppedBusy": Double(stats.droppedBusy), "lateFrames": Double(stats.lateFrames),
                                 "analysisStride": Double(ReplayCameraService.analysisStride),
                                 "lagMeanSeconds": stats.lagMean, "lagMaxSeconds": stats.lagMax,
                                 "analysisMeanSeconds": stats.analysisMean],
                      capabilities: capabilities(scenario: scenario, phased: phased),
                      note: "Open-loop replay: the person in the video does not follow the guide. Counts are observations, not errors; no accuracy without ground truth. Times are media time (s); lag is wall time from frame shown to analysis done.")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(doc)
    }

    /// Writes `replay-<run>.json` and appends the CSV row. Returns the files to share.
    func write(stats: ReplayPipelineStats, scenario: ReplayScenario, phased: Bool, alsoAppendTo extra: URL? = nil) -> [URL] {
        let fm = FileManager.default
        try? fm.createDirectory(at: ReplayLibrary.results, withIntermediateDirectories: true)
        var urls: [URL] = []
        let jsonURL = ReplayLibrary.results.appending(path: "replay-\(runID).json")
        if let data = json(stats: stats, scenario: scenario, phased: phased), (try? data.write(to: jsonURL)) != nil {
            urls.append(jsonURL)
        }
        let csv = ReplayLibrary.summaryCSV
        if !fm.fileExists(atPath: csv.path()) {
            try? (Self.csvHeader + "\n").data(using: .utf8)?.write(to: csv)
        }
        for file in [csv] + (extra.map { [$0] } ?? []) {
            if !fm.fileExists(atPath: file.path()) {
                try? (Self.csvHeader + "\n").data(using: .utf8)?.write(to: file)
            }
            if let handle = try? FileHandle(forWritingTo: file) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data((csvRow(stats: stats, scenario: scenario) + "\n").utf8))
                try? handle.close()
            }
        }
        urls.append(csv)
        return urls
    }
}
