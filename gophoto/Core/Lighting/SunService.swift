//
//  SunService.swift
//  gophoto
//
//  Core layer: the ONLY place that uses SunKit. Works offline; needs just a location and the time.
//

import CoreLocation
import SunKit

nonisolated struct SunService: Sendable {

    func position(at date: Date, location: CLLocation) -> SunPosition {
        let sun = Sun(location: location, timeZone: .current, date: date)
        return SunPosition(azimuth: sun.azimuth.degrees,
                           altitude: sun.altitude.degrees,
                           isGoldenHour: sun.isEveningGoldenHour)
    }
}
