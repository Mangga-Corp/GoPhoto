import Foundation

/// The seated attributes most of a set of photos agree on (usable readings only).
nonisolated enum SittingProfileAggregator {

    static func support(_ readings: [PostureReading]) -> SupportSurface? {
        majority(readings.compactMap { reading -> SupportSurface? in
            guard let attribute = reading.sitting?.supportSurface, attribute.isUsable,
                  attribute.value != .unknown else { return nil }
            return attribute.value
        })
    }

    static func legs(_ readings: [PostureReading]) -> LegConfiguration? {
        majority(readings.compactMap { reading -> LegConfiguration? in
            guard let attribute = reading.sitting?.legConfiguration, attribute.isUsable,
                  attribute.value != .unknown else { return nil }
            return attribute.value
        })
    }

    /// The value held by more than half of the photos, else nil.
    private static func majority<T: Hashable>(_ values: [T]) -> T? {
        let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        guard let best = counts.max(by: { $0.value < $1.value }), best.value * 2 > values.count else { return nil }
        return best.key
    }
}
