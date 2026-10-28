//
//  WeatherService.swift
//  gophoto
//
//  Core layer: the ONLY place that uses WeatherKit. Needs the WeatherKit capability and a network
//  connection; when either is missing the answer is nil and the lighting rules use their fallback.
//

import CoreLocation
import WeatherKit

protocol WeatherServiceProtocol: AnyObject {
    /// The weather here and now, or nil (offline, no capability, failure).
    func currentWeather(at location: CLLocation) async -> LightingWeather?
}

final class WeatherKitService: WeatherServiceProtocol {

    private var cached: (weather: LightingWeather, at: Date, location: CLLocation)?
    /// A reading this young, from this close by, is reused: it saves quota and battery.
    private static let maxAge: TimeInterval = 20 * 60
    private static let maxDistance: CLLocationDistance = 5_000

    func currentWeather(at location: CLLocation) async -> LightingWeather? {
        if let cached, Date().timeIntervalSince(cached.at) < Self.maxAge,
           cached.location.distance(from: location) < Self.maxDistance {
            return cached.weather
        }
        guard let current = try? await WeatherKit.WeatherService.shared.weather(for: location, including: .current) else {
            return nil
        }
        guard let weather = Self.lighting(for: current.condition) else { return nil }
        cached = (weather, Date(), location)
        return weather
    }

    /// WeatherKit has about thirty conditions; the lighting rules need five. Snow, wind and the
    /// like map to what the sky looks like, not to the name.
    static func lighting(for condition: WeatherKit.WeatherCondition) -> LightingWeather? {
        switch condition {
        case .clear, .mostlyClear, .hot, .partlyCloudy, .sunShowers:
            return .clear
        case .mostlyCloudy, .cloudy, .breezy, .windy, .blowingDust, .smoky:
            return .cloudy
        case .foggy, .haze:
            return .mist
        case .drizzle, .rain, .freezingDrizzle, .flurries, .snow, .sleet, .wintryMix, .blowingSnow, .sunFlurries:
            return .rain
        case .heavyRain, .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms,
             .freezingRain, .hail, .heavySnow, .blizzard, .tropicalStorm, .hurricane:
            return .heavyRain
        case .frigid:
            return .cloudy
        @unknown default:
            return nil
        }
    }
}
