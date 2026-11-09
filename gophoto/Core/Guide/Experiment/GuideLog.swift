//
//  GuideLog.swift
//  gophoto
//
//  appMode 2 guide log: why the guide changed its instruction / phase, and one note per shutter,
//  always with the guide + framing it belongs to, so the combinations can be compared.
//  Files: Documents/GuideLogs/<session>.jsonl (one JSON object per line) and
//  Documents/GuideLogs/<session>/capture-<n>.json (one document per shutter). No images, no faces.
//
import Foundation

/// One value in a log entry (kept small and Codable).
nonisolated enum LogValue: Codable, Sendable, Equatable {
    case string(String), number(Double), int(Int), bool(Bool)

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v.isFinite ? (v * 10_000).rounded() / 10_000 : 0)
        case .int(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else { self = .string(try c.decode(String.self)) }
    }
}

nonisolated extension LogValue: ExpressibleByStringLiteral, ExpressibleByFloatLiteral,
                                ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(floatLiteral value: Double) { self = .number(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
}

/// Builds the fields of an entry, skipping nil values.
nonisolated struct LogFields: Sendable {
    private(set) var values: [String: LogValue] = [:]
    init() {}
    subscript(key: String) -> LogValue? {
        get { values[key] }
        set { values[key] = newValue }
    }
    mutating func set(_ key: String, _ value: Double?) { if let value { values[key] = .number(value) } }
    mutating func set(_ key: String, _ value: Int?) { if let value { values[key] = .int(value) } }
    mutating func set(_ key: String, _ value: Bool?) { if let value { values[key] = .bool(value) } }
    mutating func set(_ key: String, _ value: String?) { if let value { values[key] = .string(value) } }
}

/// Appends entries on its own queue (never blocks the camera or the main thread).
nonisolated final class GuideLogger: @unchecked Sendable {
    let sessionName: String
    let fileURL: URL
    private let captureDirectory: URL
    private let queue = DispatchQueue(label: "gophoto.guidelog")
    private var handle: FileHandle?
    private var captureCount = 0
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()
    private let prettyEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return e
    }()
    private static let timeFormat: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static var directory: URL {
        URL.documentsDirectory.appending(path: "GuideLogs", directoryHint: .isDirectory)
    }

    /// Newest first.
    static func logFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    init?() {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        stamp.locale = Locale(identifier: "en_US_POSIX")
        sessionName = "guide-" + stamp.string(from: Date())
        let dir = Self.directory
        fileURL = dir.appending(path: sessionName + ".jsonl")
        captureDirectory = dir.appending(path: sessionName, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: fileURL.path(), contents: nil)
            handle = try FileHandle(forWritingTo: fileURL)
        } catch {
            NSLog("GoPhoto guide log could not be created: %@", error.localizedDescription)
            return nil
        }
    }

    deinit { try? handle?.close() }

    private func entry(_ type: String, _ fields: LogFields) -> [String: LogValue] {
        var all = fields.values
        all["type"] = .string(type)
        all["time"] = .string(Self.timeFormat.string(from: Date()))
        all["uptime"] = .number(ProcessInfo.processInfo.systemUptime)
        return all
    }

    /// One line in the session file.
    func log(_ type: String, _ fields: LogFields) {
        let line = entry(type, fields)
        queue.async {
            guard var data = try? self.encoder.encode(line) else { return }
            data.append(0x0A)
            try? self.handle?.write(contentsOf: data)
        }
    }

    /// The shutter note: a line in the session file and its own document.
    func capture(_ fields: LogFields) {
        let doc = entry("capture", fields)
        queue.async {
            self.captureCount += 1
            if var data = try? self.encoder.encode(doc) {
                data.append(0x0A)
                try? self.handle?.write(contentsOf: data)
            }
            if let pretty = try? self.prettyEncoder.encode(doc) {
                let url = self.captureDirectory.appending(path: String(format: "capture-%03d.json", self.captureCount))
                try? pretty.write(to: url)
            }
        }
    }
}
