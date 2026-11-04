//
//  DebugFixtures.swift
//  gophoto
//
//  DEBUG builds only: launch arguments for checking the session setup screens in the simulator.
//
//    -GoPhotoFixtureStore <empty|one|multiple|showcase|interaction>
//        Use a separate preferences folder (`PreferencesFixtures/<name>`, never the real one) and,
//        when it is empty, fill it with preferences made from the bundled onboarding photos.
//        empty / one / multiple: real on-device analysis (runs on first launch).
//        showcase / interaction: HAND-MADE fixture analyses (see `fixtureAnalysis`), for checking
//        the available and selected card states; they say nothing about real analysis output.
//    -GoPhotoFixtureReset YES
//        Delete that fixture folder first (a clean store for every UI test).
//    -GoPhotoScreen preferenceSelection
//        Open the Preference Selection flow instead of the normal start screen.
//
//  Not compiled into release builds.
//

#if DEBUG
import SwiftUI
import UIKit

enum DebugFixtures {
    /// Launch arguments land in UserDefaults' argument domain (not saved).
    /// Lowercase letters only: the name becomes a folder name (and is deleted by the reset flag),
    /// so anything else, such as "../Preferences", is ignored and the real store is used as usual.
    static var storeName: String? {
        guard let name = UserDefaults.standard.string(forKey: "GoPhotoFixtureStore"),
              !name.isEmpty, name.allSatisfy({ $0.isASCII && $0.isLowercase && $0.isLetter }) else { return nil }
        return name
    }
    private static var resetsStore: Bool { UserDefaults.standard.bool(forKey: "GoPhotoFixtureReset") }

    /// Fixture runs only, before any view reads the flags:
    /// `-GoPhotoScreen preferenceSelection` (or `-GoPhotoOnboarding completed`): onboarding done,
    /// so the app opens on Preference Selection like a returning user.
    /// `-GoPhotoOnboarding fresh`: onboarding not started, like a first launch.
    /// Written to the saved defaults (not the argument domain) so the app can still change them.
    static func prepareLaunchState() {
        guard storeName != nil else { return }
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: "GoPhotoScreen") == "preferenceSelection"
            ? "completed" : defaults.string(forKey: "GoPhotoOnboarding")
        switch mode {
        case "completed":
            defaults.set(true, forKey: "welcomeOnboardingCompleted")
            defaults.set(false, forKey: "welcomeOnboardingStarted")
        case "fresh":
            defaults.set(false, forKey: "welcomeOnboardingCompleted")
            defaults.set(false, forKey: "welcomeOnboardingStarted")
            defaults.set("photoSetup", forKey: "firstTimeOnboardingStep")
        default:
            break
        }
    }

    /// `-GoPhotoDeleteOnStart YES`: deletes the preference between Start Shooting's tap and the
    /// session start (a preference that became invalid after the screen validated it).
    static func beforeSessionStart(preferenceID: UUID) {
        guard storeName != nil, UserDefaults.standard.bool(forKey: "GoPhotoDeleteOnStart") else { return }
        PreferencesViewModel.shared.delete(id: preferenceID, allowingLast: true)
    }

    // MARK: Fake analysis (UI tests of the routes; NOT evidence that the real analysis works)

    /// `-GoPhotoFakeAnalysis <usable|optionalFailure|requiredFailure|noSubject|failOnce>`: the
    /// analysis returns a HAND-MADE result after 1.5 s instead of running Vision (which cannot run
    /// in the simulator). `failOnce`: required failure the first time, usable after a retry.
    private static var fakeAnalysisMode: String? {
        storeName == nil ? nil : UserDefaults.standard.string(forKey: "GoPhotoFakeAnalysis")
    }
    private static var fakeAnalysisRuns = 0

    static func fakeAnalysis(for items: [PhotoItem]) async -> PresetAnalysis? {
        guard var mode = fakeAnalysisMode else { return nil }
        try? await Task.sleep(for: .seconds(1.5))
        fakeAnalysisRuns += 1
        if mode == "failOnce" { mode = fakeAnalysisRuns == 1 ? "requiredFailure" : "usable" }

        func runs(humans: AnalysisEvidenceSummary.Outcome, pose: AnalysisEvidenceSummary.Outcome,
                  faces: AnalysisEvidenceSummary.Outcome) -> [[AnalysisEvidenceSummary.Run]?] {
            items.map { _ in [
                .init(source: .visionHumanRectangles, outcome: humans, detail: humans == .failed ? "fixture: no inference context" : ""),
                .init(source: .visionBodyPose, outcome: pose, detail: pose == .failed ? "fixture: no compute device" : ""),
                .init(source: .visionFaceRectangles, outcome: faces, detail: faces == .failed ? "fixture: face request failed" : ""),
            ] }
        }
        var analysis: PresetAnalysis
        switch mode {
        case "requiredFailure":
            analysis = fixtureAnalysis(items, shots: [], light: 0.5, side: nil, centerX: 0.5)
            analysis.evidence = AnalysisEvidenceSummary(photoRuns: runs(humans: .failed, pose: .failed, faces: .failed))
        case "noSubject":
            analysis = fixtureAnalysis(items, shots: [], light: 0.5, side: nil, centerX: 0.5)
            analysis.evidence = AnalysisEvidenceSummary(photoRuns: runs(humans: .nothingDetected, pose: .nothingDetected,
                                                                        faces: .nothingDetected))
        case "classic":
            // All full body, angles mixed, centred: "The Classic" (style card screenshots).
            analysis = fixtureAnalysis(items, shots: [.full], light: 0.5, side: nil, centerX: 0.5)
            analysis.evidence = AnalysisEvidenceSummary(photoRuns: runs(humans: .produced, pose: .produced, faces: .produced))
        case "optionalFailure":
            analysis = fixtureAnalysis(items, shots: [.full, .threeQuarter], light: 0.5, side: nil, centerX: 0.5)
            analysis.evidence = AnalysisEvidenceSummary(photoRuns: runs(humans: .produced, pose: .produced, faces: .failed))
        default:   // "usable"
            analysis = fixtureAnalysis(items, shots: [.full, .threeQuarter], light: 0.5, side: .below, centerX: 0.5)
            analysis.evidence = AnalysisEvidenceSummary(photoRuns: runs(humans: .produced, pose: .produced, faces: .produced))
        }
        return analysis
    }

    /// Fills an empty fixture store. Real stores are never touched (no `-GoPhotoFixtureStore`).
    static func seedIfNeeded() {
        guard let scenario = storeName else { return }
        if resetsStore {
            // Before PreferencesViewModel.shared loads it. Only ever the fixture folder.
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(at: base.appendingPathComponent("PreferencesFixtures/\(scenario)"))
        }
        let preferences = PreferencesViewModel.shared
        guard !preferences.hasPreferences else { return }

        switch scenario {
        case "showcase": seedShowcase(preferences)
        case "interaction": seedInteraction(preferences)
        case "shotsizes": seedShotSizes(preferences)
        default: seedReal(scenario, preferences)
        }
    }

    /// `-GoPhotoShotSizeFor <name>`: open Shot Size Selection directly for that preference.
    static var shotSizeTargetName: String? { UserDefaults.standard.string(forKey: "GoPhotoShotSizeFor") }

    static var initialRoute: [SessionSetupRoute] {
        guard storeName != nil, let name = shotSizeTargetName,
              let id = PreferencesViewModel.shared.preferences.first(where: { $0.name == name })?.id else { return [] }
        return [.shotSize(preferenceID: id)]
    }

    /// `-GoPhotoDeletePreferenceAfter <name>`: delete that fixture preference 4 s after launch
    /// (checks a preference disappearing while Shot Size Selection is open).
    static func scheduleDeletionIfRequested() {
        guard storeName != nil,
              let name = UserDefaults.standard.string(forKey: "GoPhotoDeletePreferenceAfter") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            let preferences = PreferencesViewModel.shared
            if let id = preferences.preferences.first(where: { $0.name == name })?.id {
                preferences.delete(id: id, allowingLast: true)
            }
        }
    }

    /// Shot Size Selection checks (HAND-MADE fixture analyses):
    /// - All Framings: Half, 3/4 and Full variants (last used).
    /// - Full Body Only: Full variant only (3/4 and Half fall back to Full).
    /// - Reanalyzing: Full variant; re-analysed for real when opened directly, which in the
    ///   simulator ends without any variant (loading state, then the error state).
    /// - No Framing: analysed, no variant at all (the simulator's real output).
    private static func seedShotSizes(_ preferences: PreferencesViewModel) {
        func add(_ name: String, _ numbers: [Int], _ shots: [PresetAnalysis.ShotSize]) -> UUID? {
            let items = photos(numbers)
            guard case .success(let id) = preferences.add(name: name, photos: items) else { return nil }
            preferences.setAnalysis(fixtureAnalysis(items, shots: shots, light: 0.5, side: .below, centerX: 0.5), for: id)
            return id
        }
        let all = add("All Framings", [1, 2, 3, 4, 5, 6], [.half, .threeQuarter, .full])
        _ = add("Full Body Only", [7, 8, 9, 10], [.full])
        let reanalyzing = add("Reanalyzing", [11, 12, 13, 14], [.full])
        _ = add("No Framing", [15, 16, 17, 18], [])
        if let all { preferences.recordLastSelected(id: all) }
        if shotSizeTargetName == "Reanalyzing", let reanalyzing { preferences.reanalyze(id: reanalyzing) }
    }

    private static func photos(_ numbers: [Int]) -> [PhotoItem] {
        numbers.compactMap { UIImage(named: String(format: "OnboardingPhoto%02d", $0)) }
            .map { PhotoItem(image: $0) }
    }

    private static func seedReal(_ scenario: String, _ preferences: PreferencesViewModel) {
        let specs: [(name: String, photos: [Int])]
        switch scenario {
        case "one":
            specs = [("Golden Hour Portraits", [1, 5, 8, 11])]
        case "multiple":
            specs = [("Golden Hour Portraits", [1, 5, 8, 11]),
                     ("Travel Portrait", [2, 6, 9, 12]),
                     ("Casual Portrait", [3, 4, 7, 10]),
                     ("Missing Photos", [])]          // no thumbnail, cannot be analysed
        default:
            specs = []                                 // "empty"
        }
        var ids: [UUID] = []
        for spec in specs {
            if case .success(let id) = preferences.add(name: spec.name, photos: photos(spec.photos)) {
                ids.append(id)
                preferences.reanalyze(id: id)
            }
        }
        // A previous session's preference, so "Last Used" and the preselection can be checked.
        if ids.count > 1 { preferences.recordLastSelected(id: ids[1]) }
    }

    private static func fixtureAnalysis(_ items: [PhotoItem], shot: PresetAnalysis.ShotSize, light: Double,
                                        side: PresetAnalysis.EyeSide?, centerX: CGFloat) -> PresetAnalysis {
        fixtureAnalysis(items, shots: [shot], light: light, side: side, centerX: centerX)
    }

    /// HAND-MADE analysis: just enough for a card to be available and show its chips. The photos
    /// are spread over `shots` (one variant each, with its photo count); no shots = no variants.
    private static func fixtureAnalysis(_ items: [PhotoItem], shots: [PresetAnalysis.ShotSize], light: Double,
                                        side: PresetAnalysis.EyeSide?, centerX: CGFloat) -> PresetAnalysis {
        var analysis = PresetAnalysis(analyzedAt: Date(), photoCount: items.count,
                                      subjectBox: CGRect(x: centerX - 0.15, y: 0.2, width: 0.3, height: 0.6),
                                      subjectPhotoCount: items.count, angle: .fixedRule)
        analysis.lightLevel = light
        if let side {
            analysis.eyeSide = side.rawValue
            analysis.eyeSideSource = PresetAnalysis.EyeSideSource.taste.rawValue
            analysis.eyeAboveShare = side == .above ? 1 : 0
            analysis.eyeSidePhotoCount = items.count
        } else {
            analysis.eyeSideSource = PresetAnalysis.EyeSideSource.mixed.rawValue
        }
        guard !shots.isEmpty else { return analysis }
        let assigned = items.enumerated().map { ($0.element, shots[$0.offset % shots.count]) }
        analysis.photoShotSizes = Dictionary(uniqueKeysWithValues: assigned.map { ($0.0.id.uuidString, $0.1.rawValue) })
        var variants: [String: PresetAnalysis] = [:]
        for shot in shots {
            var variant = analysis
            variant.shotSize = shot.rawValue
            variant.photoCount = assigned.filter { $0.1 == shot }.count
            variants[shot.rawValue] = variant
        }
        analysis.shotVariants = variants
        return analysis
    }

    /// Two fixture analyses, one real analysis (shows the analysing state), one without photos.
    private static func seedShowcase(_ preferences: PreferencesViewModel) {
        let golden = photos([1, 5, 8, 11]), travel = photos([2, 6, 9, 12])
        guard case .success(let goldenID) = preferences.add(name: "Golden Hour Portraits", photos: golden),
              case .success(let travelID) = preferences.add(name: "Travel Portrait", photos: travel),
              case .success(let casualID) = preferences.add(name: "Casual Portrait", photos: photos([3, 4, 7, 10]))
        else { return }
        preferences.add(name: "Missing Photos", photos: [])
        preferences.setAnalysis(fixtureAnalysis(golden, shot: .full, light: 0.62, side: .below, centerX: 0.5), for: goldenID)
        preferences.setAnalysis(fixtureAnalysis(travel, shot: .threeQuarter, light: 0.45, side: nil, centerX: 0.35), for: travelID)
        preferences.reanalyze(id: casualID)
        preferences.recordLastSelected(id: goldenID)
    }

    /// UI tests: three available preferences (fixture analyses) and one without photos. Nothing
    /// runs in the background, so every save the status line counts comes from the test's taps.
    private static func seedInteraction(_ preferences: PreferencesViewModel) {
        let specs: [(String, [Int], PresetAnalysis.ShotSize, Double, PresetAnalysis.EyeSide?, CGFloat)] = [
            ("Golden Hour Portraits", [1, 5, 8, 11], .full, 0.62, .below, 0.5),
            ("Travel Portrait", [2, 6, 9, 12], .threeQuarter, 0.45, nil, 0.35),
            ("Studio Headshots", [3, 4, 7, 10], .half, 0.32, .above, 0.5),
        ]
        var ids: [UUID] = []
        for (name, numbers, shot, light, side, x) in specs {
            let items = photos(numbers)
            guard case .success(let id) = preferences.add(name: name, photos: items) else { continue }
            preferences.setAnalysis(fixtureAnalysis(items, shot: shot, light: light, side: side, centerX: x), for: id)
            ids.append(id)
        }
        preferences.add(name: "Missing Photos", photos: [])
        if let first = ids.first { preferences.recordLastSelected(id: first) }
    }
}

extension DebugFixtures {
    /// `-GoPhotoDiagnoseVision YES`: runs the app's own `VisionEvidenceRunner` on the first bundled
    /// onboarding photos and writes what every Vision request returned to
    /// `Documents/vision-diagnosis.txt`. Diagnostics only; the analysis code is not touched.
    static func diagnoseVisionIfRequested() {
        guard UserDefaults.standard.bool(forKey: "GoPhotoDiagnoseVision") else { return }
        Task.detached {
            var lines = ["device: \(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "physical device")"]
            for number in [1, 2, 3, 4, 5, 8] {
                guard let source = UIImage(named: String(format: "OnboardingPhoto%02d", number)) else { continue }
                // An upright bitmap, like the analysis image.
                let format = UIGraphicsImageRendererFormat.default()
                format.scale = 1
                let upright = UIGraphicsImageRenderer(size: source.size, format: format).image { _ in
                    source.draw(at: .zero)
                }
                guard let cgImage = upright.cgImage else { continue }
                let bundle = await VisionEvidenceRunner.run(on: cgImage)
                lines.append("photo \(number) (\(cgImage.width)x\(cgImage.height))")
                for record in bundle.records {
                    lines.append("  \(record.source) -> \(record.state) | \(record.detail)")
                }
            }
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("vision-diagnosis.txt")
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// Fixture runs only, over the camera: the session the store created (what the camera was given)
/// and the start / end counts, for UI tests.
struct DebugSessionStatus: View {
    var body: some View {
        if DebugFixtures.storeName != nil {
            let preferences = PreferencesViewModel.shared
            let sessions = PhotoSessionStore.shared
            let session = sessions.current
            Text([
                "preference=\(session.flatMap { preferences.preference(id: $0.preferenceID)?.name } ?? "none")",
                "requested=\(session?.requestedShotSize.rawValue ?? "none")",
                "effective=\(session?.effectiveShotSize.rawValue ?? "none")",
                "fallback=\(session?.requiresShotSizeFallback ?? false)",
                "starts=\(sessions.startCount)",
                "ends=\(sessions.endCount)",
                "lastUsed=\(preferences.lastSelectedPreference?.name ?? "none")",
            ].joined(separator: ";"))
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.bottom, 4)
            .accessibilityIdentifier("debug.sessionStatus")
            .allowsHitTesting(false)
        }
    }
}

/// Fixture runs only: the saved last used preference and the save / session counts, for UI tests.
struct DebugFixtureStatus: View {
    var body: some View {
        let preferences = PreferencesViewModel.shared
        let sessions = PhotoSessionStore.shared
        Text("lastUsed=\(preferences.lastSelectedPreference?.name ?? "none");starts=\(sessions.startCount);ends=\(sessions.endCount);writes=\(preferences.persistCount)")
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("debug.fixtureStatus")
            .allowsHitTesting(false)
    }
}
#endif
