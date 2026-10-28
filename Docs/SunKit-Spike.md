# S1 spike — SunKit, camera heading, compass calibration

What was checked in the source / by running the package, and what still needs a phone outdoors.

## SunKit 2.8.1 (verified from the tag's source, run on macOS)

- Apache-2.0, no dependencies, iOS 14+, needs `CoreLocation` (`CLLocation`). All maths is local.
- API used: `Sun(location: CLLocation, timeZone: TimeZone, date: Date)`, `sun.azimuth.degrees`,
  `sun.altitude.degrees`, `sun.isEveningGoldenHour`, `sun.sunset`, `sun.isNight`.
- **Azimuth is degrees clockwise from true north** (Jakarta, 28 Oct 2026: 06:00 → 102°, 15:00 → 258°).
  Same frame as the camera heading below, so the two compare directly.
- Altitude at Jakarta noon was 81° (sun near zenith, close to the hand-computed 83°).
- **Golden hour is not "30 min before sunset"**: SunKit uses sun elevation −4°…+6°. At Jakarta that
  gave 17:17–17:58 with sunset at 17:45, so it starts about 28 min before sunset. We use
  `isEveningGoldenHour` as is. Morning golden hour is ignored (the ticket says sunset).
- `Sun` init + `setDate` cost well under 1 ms, so it can be recomputed on every light reading.
- One `Sun` per call; the app passes `TimeZone.current` (only sunrise/sunset day boundaries use it).

## Camera heading (Core Motion, `xTrueNorthZVertical`)

- Reference frame: x = true north, y = west, z = up. `CMAttitude.rotationMatrix` maps reference →
  device, so the device z axis in the reference frame is the matrix's **third row** (m31, m32, m33).
  The back camera looks along −z: north = −m31, east = +m32. Heading = `atan2(east, north)`.
  Hand check: facing north → m31 = −1 → 0°; facing east → m32 = 1 → 90°.
- This is the camera direction, unlike `CLHeading`/compass heading, which follows the top edge of the
  phone and is wrong when the phone is held upright to shoot.
- Pointing the camera almost straight up/down has no stable horizontal direction: below 30% horizontal
  share the heading is dropped (`CameraHeading.minHorizontalShare`).
- True north needs location services on (Core Motion uses the location for magnetic declination);
  `CMMotionManager.availableAttitudeReferenceFrames()` is checked and the stream ends if it is missing.
- `HeadingService` has its own `CMMotionManager` (the tilt service has another). Two managers worked
  in the API's contract; Apple recommends one per app, so this is a candidate to merge later.

## Compass calibration

- `CMDeviceMotion.magneticField.accuracy` (`CMMagneticFieldCalibrationAccuracy`) is valid in this
  reference frame. Only `.medium` and `.high` count as reliable; `.uncalibrated` and `.low` make the
  heading unusable, so the "swap places" tip stays silent rather than guess.
- A heading older than 2 s is ignored (camera paused).

## NOT verified here (needs a physical iPhone, outdoors)

- Real heading error in degrees, near steel, cars, buildings and indoors.
- How long the compass takes to reach `.medium`, and how it behaves after the figure-8 prompt.
- Whether ±45° (enter) / 55° (leave) is wide enough against the real heading noise.
- Frame-brightness thresholds (`outdoorLuminance` 0.35, `veryBrightLuminance` 0.5) in real sun.
- Location permission prompt flow on a clean install.

## Attribution

SunKit asks for its logo + "Sunlitt" linking to https://sunlitt.app, and its license in the app's
acknowledgements. License/notice files are in `ThirdPartyNotices/SunKit/`. The visible in-app credit
is **not done**: the app has no settings/about screen to put it on.
