import SwiftUI

/// Overview of a finished analysis: counts, warnings, the consolidated profile
/// summary, and a browsable list of individual photo results.
struct ResultsOverviewView: View {
    @ObservedObject var session: AnalysisSession
    let onOpenCamera: () -> Void
    /// Which photos the overview shows: all, or one framing (shot size, or seated full body).
    @State private var filter: FramingFilter = .all

    nonisolated enum FramingFilter: Hashable, Identifiable {
        case all
        case shot(PresetAnalysis.ShotSize)
        case sitting
        var id: String { title }
        var title: String {
            switch self {
            case .all: "All"
            case .shot(.full): "Full"
            case .shot(.threeQuarter): "3/4"
            case .shot(.half): "Half"
            case .shot(.quarter): "1/4"
            case .sitting: "Sitting"
            }
        }
    }

    /// The framing group of one photo (same rules as the camera's shot sizes; seated full body apart).
    nonisolated static func group(of result: PhotoResult) -> FramingFilter? {
        guard let shot = PreferenceAnalyzer.shotSize(of: result) else { return nil }
        if shot == .full, PreferenceAnalyzer.posture(of: result) == .sitting { return .sitting }
        return .shot(shot)
    }

    private var options: [FramingFilter] {
        let groups = session.results.compactMap(Self.group(of:))
        let present = PresetAnalysis.ShotSize.allCases.map(FramingFilter.shot) + [.sitting]
        return [.all] + present.filter { option in groups.contains(option) }
    }

    var body: some View {
        let results = filter == .all ? session.results : session.results.filter { Self.group(of: $0) == filter }
        let profile = filter == .all ? session.profile : (results.isEmpty ? nil : ProfileAggregator.aggregate(results))
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if options.count > 1 {
                    Picker("Framing", selection: $filter) {
                        ForEach(options) { option in
                            let count = option == .all ? session.results.count
                                : session.results.filter { Self.group(of: $0) == option }.count
                            Text("\(option.title) \(count)").tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Show photos by framing")
                }
                if let profile {
                    summaryCard(profile)
                    if profile.isEmpty { noEvidenceCard(profile) } else { profileCard(profile, linked: true) }
                    blurCard(results)
                    warningsCard(profile, results: results)
                }
                photosSection(results)
                cameraSection
            }
            .padding(16)
        }
    }

    // MARK: Summary

    private func summaryCard(_ profile: PreferenceProfile) -> some View {
        ResultCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 24) {
                    stat("\(profile.totalPhotoCount)", "selected")
                    stat("\(profile.analyzedPhotoCount)", "analyzed")
                    stat("\(profile.photosWithValidEvidenceCount)", "with results")
                }
                Divider()
                VStack(spacing: 8) {
                    ForEach(CharacteristicKind.allCases) { kind in
                        let c = profile.coverage[kind]
                        HStack {
                            Label(kind.title, systemImage: kind.systemImage).font(.footnote)
                            Spacer()
                            Text("\(c?.determinedCount ?? 0) of \(profile.totalPhotoCount) photos")
                                .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.title.bold().monospacedDigit())
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Profile

    @ViewBuilder
    private func profileCard(_ profile: PreferenceProfile, linked: Bool) -> some View {
        if linked {
            NavigationLink(value: ProfileRoute(filter: filter)) { profileCardBody(profile, linked: true) }
                .buttonStyle(.plain)
        } else {
            profileCardBody(profile, linked: false)
        }
    }

    private func profileCardBody(_ profile: PreferenceProfile, linked: Bool) -> some View {
            ResultCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(filter == .all ? "Photo Preference Profile" : "Photo Preference Profile · \(filter.title)").font(.headline)
                        Spacer()
                        if linked {
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    profileRow(.cameraAngle, finding: profile.cameraAngle.pattern, strength: profile.cameraAngle.strength,
                               text: profile.cameraAngle.dominant?.label, fallback: profile.cameraAngle.summary)
                    profileRow(.subjectFraming, finding: profile.subjectFraming.pattern, strength: profile.subjectFraming.strength,
                               text: profile.subjectFraming.dominant?.label, fallback: profile.subjectFraming.summary)
                    profileRow(.subjectPositioning, finding: positionPattern(profile), strength: profile.horizontalPosition.strength,
                               text: positionText(profile), fallback: profile.horizontalPosition.summary)
                    profileRow(.environmentalDepth, finding: profile.depthStructure.pattern, strength: profile.depthStructure.strength,
                               text: profile.depthStructure.dominant?.label, fallback: profile.depthStructure.summary)
                    if let environment = profile.environment, !environment.isEmpty { environmentRow(environment) }
                    Text(linked ? "Tap for distributions, variation and the photos behind each finding."
                                : "Only this framing's photos. Choose All for the full details screen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
    }

    /// One line each for the scene tendency and the composition tendency, stated only when a pattern exists.
    private func environmentRow(_ e: EnvironmentProfile) -> some View {
        let scene = e.sceneDependent.sceneCategory
        let scale = e.transferable.subjectScale
        return VStack(alignment: .leading, spacing: 3) {
            Label("Environment and composition", systemImage: "photo.on.rectangle.angled").font(.caption).foregroundStyle(.secondary)
            if let dominant = scene.dominant {
                Text(dominant.displayName).font(.body.weight(.semibold))
            } else {
                Text(scene.pattern.label).font(.body.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(scale.dominant.map { "Subject: \($0.label.lowercased()) in most photos" } ?? scale.summary)
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func positionPattern(_ p: PreferenceProfile) -> PatternKind {
        p.horizontalPosition.pattern == .recurring || p.verticalPosition.pattern == .recurring
            ? .recurring : (p.horizontalPosition.pattern == .noEvidence ? .noEvidence : p.horizontalPosition.pattern)
    }

    private func positionText(_ p: PreferenceProfile) -> String? {
        let parts = [p.horizontalPosition.dominant?.label, p.verticalPosition.dominant?.label].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func profileRow(_ kind: CharacteristicKind, finding: PatternKind, strength: PatternStrength,
                            text: String?, fallback: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(kind.title, systemImage: kind.systemImage).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let text, finding == .recurring {
                    Text(text).font(.body.weight(.semibold))
                    Text(strength.label).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(finding.label).font(.body.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            if !(finding == .recurring) {
                Text(fallback).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func noEvidenceCard(_ profile: PreferenceProfile) -> some View {
        ResultCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("No profile could be built", systemImage: "exclamationmark.triangle").font(.headline).foregroundStyle(.orange)
                Text("None of the photos produced a measurable result, so no preferences are reported. This usually means the photos do not clearly show a person, or an analysis step could not run on this device.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Try photos in which a person is clearly visible and reasonably large in the frame.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Background blur

    /// How blurred these photos' backgrounds are (v18): the blur copy is rendered to match it.
    private func blurCard(_ results: [PhotoResult]) -> some View {
        let values = results.compactMap { session.backgroundBlur[$0.id] }.sorted()
        let median = values.isEmpty ? nil : (values[(values.count - 1) / 2] + values[values.count / 2]) / 2
        return ResultCard {
            VStack(alignment: .leading, spacing: 6) {
                Label("Background blur", systemImage: "camera.aperture").font(.headline)
                if let median {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%.2f", median)).font(.title2.bold().monospacedDigit())
                        Text(Self.blurLook(median)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("Median of \(values.count) of \(results.count) photos. Background sharpness ÷ person sharpness: about 1 = background as sharp as the person, about 0.2 = strong bokeh. Blur On matches this.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(session.backgroundBlur.isEmpty
                         ? "Not measured in this run. Analyze the preset again to measure it."
                         : "No photo here could be measured (no clear person, or the person is blurry).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    static func blurLook(_ ratio: Double) -> String {
        ratio >= BokehProcessor.sharpReferenceRatio ? "sharp background · no blur copy"
            : ratio >= 0.6 ? "light blur" : ratio >= 0.35 ? "medium blur" : "strong blur"
    }

    // MARK: Warnings

    @ViewBuilder
    private func warningsCard(_ profile: PreferenceProfile, results: [PhotoResult]) -> some View {
        let problems = results.filter { $0.status != .complete }
        let notes = profile.limitations.prefix(3)
        if !problems.isEmpty || !notes.isEmpty {
            ResultCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Things to know", systemImage: "info.circle").font(.headline)
                    ForEach(problems) { r in
                        Text("Photo \(r.selectionOrder + 1): \(r.status == .failed ? "could not be analyzed" : "some steps did not run"). Other photos are unaffected.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(Array(notes), id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                    if profile.limitations.count > notes.count {
                        NavigationLink("See all limitations", value: ProfileRoute(filter: filter)).font(.footnote)
                    }
                }
            }
        }
    }

    // MARK: Photos

    private func photosSection(_ results: [PhotoResult]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(filter == .all ? "Individual photos" : "\(filter.title) photos (\(results.count))").font(.headline)
            ForEach(results) { result in
                NavigationLink(value: PhotoDetailRoute(photoID: result.id)) {
                    PhotoResultRow(result: result, image: session.imageStore.image(for: result.id),
                               blur: session.backgroundBlur[result.id])
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Camera

    private var cameraSection: some View {
        let targets = session.results.filter {
            $0.subjectPositioning.assessment.isDetermined && $0.subjectPositioning.isMeasurementValid
        }.count
        return VStack(alignment: .leading, spacing: 8) {
            Button(action: onOpenCamera) {
                Label("Open Camera Guidance", systemImage: "camera.viewfinder")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)

            Text(targets >= 2
                 ? "Camera guidance will use the subject position and size from \(targets) photos."
                 : "Fewer than 2 photos have a measured subject, so the camera will open without position guidance.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Row

struct PhotoResultRow: View {
    let result: PhotoResult
    let image: UIImage?
    /// Background / person sharpness (v18), when measured.
    var blur: Double? = nil

    var body: some View {
        ResultCard {
            HStack(alignment: .top, spacing: 12) {
                PhotoThumb(image: image, size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Photo \(result.selectionOrder + 1)").font(.subheadline.weight(.semibold))
                        if result.status != .complete { statusTag }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    if let blur {
                        Text(String(format: "Background blur %.2f · ", blur) + ResultsOverviewView.blurLook(blur))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                              alignment: .leading, spacing: 6) {
                        ForEach(CharacteristicKind.allCases) { kind in chip(kind) }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusTag: some View {
        Text(result.status == .failed ? "Failed" : "Partial")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(result.status == .failed ? Color.red : Color.orange)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((result.status == .failed ? Color.red : Color.orange).opacity(0.14), in: Capsule())
    }

    private func chip(_ kind: CharacteristicKind) -> some View {
        let assessment = result.assessment(for: kind)
        return VStack(alignment: .leading, spacing: 0) {
            Text(kind.title).font(.caption2).foregroundStyle(.secondary)
            Text(PhotoValueText.text(for: kind, in: result))
                .font(.footnote.weight(.medium))
                .foregroundStyle(assessment.isDetermined ? Color.primary : Color.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}
