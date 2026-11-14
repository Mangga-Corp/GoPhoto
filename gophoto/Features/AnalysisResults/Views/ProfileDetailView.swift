import SwiftUI

/// Route for the full consolidated profile.
struct ProfileRoute: Hashable {
    /// The framing whose photos the profile is built from (All = the session's profile).
    var filter: ResultsOverviewView.FramingFilter = .all
}

/// The consolidated Photo Preference Profile in full: each characteristic's
/// pattern, distribution, supporting photos, numeric summaries, coverage and
/// limitations. Renders `PreferenceProfile` only; nothing is recomputed.
struct ProfileDetailView: View {
    @ObservedObject var session: AnalysisSession
    var filter: ResultsOverviewView.FramingFilter = .all

    /// This framing's photos, and their profile (rebuilt from them; All = the session's).
    private var results: [PhotoResult] {
        filter == .all ? session.results : session.results.filter { ResultsOverviewView.group(of: $0) == filter }
    }
    private var profile: PreferenceProfile? {
        filter == .all ? session.profile : (results.isEmpty ? nil : ProfileAggregator.aggregate(results))
    }

    var body: some View {
        Group {
            if let profile {
                content(profile)
            } else {
                ContentUnavailableView("No profile yet", systemImage: "chart.bar.doc.horizontal",
                                       description: Text("Analyse some photos to build a profile."))
            }
        }
        .background(AnalysisResultsPalette.pageBackground)
        .navigationTitle(filter == .all ? "Preference Profile" : "Preference Profile · \(filter.title)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func thumb(_ id: UUID) -> UIImage? { session.imageStore.image(for: id) }

    private func content(_ profile: PreferenceProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ResultCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Based on \(profile.photosWithValidEvidenceCount) of \(profile.totalPhotoCount) photos")
                            .font(AppFont.headline)
                        Text("A pattern needs the same result in at least two photos. Photos without evidence for a characteristic are left out of it, never counted against it.")
                            .font(AppFont.footnote).foregroundStyle(.secondary)
                    }
                }

                ResultCard {
                    FindingSection(title: CharacteristicKind.cameraAngle.title,
                                   systemImage: CharacteristicKind.cameraAngle.systemImage,
                                   finding: profile.cameraAngle, coverage: profile.coverage[.cameraAngle],
                                   order: Array(CameraAngleRule.ordered.reversed()),
                                   label: { $0.label }, thumbnail: thumb)
                }

                if let viewpoint = profile.viewpoint {
                    ResultCard {
                        VStack(alignment: .leading, spacing: 16) {
                            FindingSection(title: "Camera height", systemImage: "arrow.up.and.down",
                                           finding: viewpoint.heightLevel, coverage: nil,
                                           order: CameraHeightLevel.ordered,
                                           label: { $0.label }, thumbnail: thumb, showCoverage: false)
                            FindingSection(title: "Horizon", systemImage: "level",
                                           finding: viewpoint.dutchAngle, coverage: nil,
                                           order: [.level, .slightTilt, .dutch],
                                           label: { $0.label }, thumbnail: thumb, showCoverage: false)
                            if let pitch = viewpoint.pitchDown, pitch.count >= 2 {
                                Text(String(format: "Phone tilt across %ld photos: typically %.0f° %@ (estimated, typical phone lens).",
                                            pitch.count, abs(pitch.median), pitch.median >= 0 ? "down" : "up"))
                                    .font(AppFont.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                ResultCard {
                    FindingSection(title: CharacteristicKind.subjectFraming.title,
                                   systemImage: CharacteristicKind.subjectFraming.systemImage,
                                   finding: profile.subjectFraming, coverage: profile.coverage[.subjectFraming],
                                   order: [.fullBody, .halfBody, .other],
                                   label: { $0.label }, thumbnail: thumb)
                }

                positioningCard(profile)
                depthCard(profile)

                if let environment = profile.environment {
                    EnvironmentProfileSection(profile: environment, thumbnail: thumb)
                }

                if !profile.limitations.isEmpty {
                    ResultCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Limitations", systemImage: "exclamationmark.circle").font(AppFont.headline)
                            ForEach(profile.limitations, id: \.self) { limitation in
                                Text("• " + limitation).font(AppFont.footnote).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: Positioning

    private func positioningCard(_ profile: PreferenceProfile) -> some View {
        let kind = CharacteristicKind.subjectPositioning
        let dots: [PositionMap.Dot] = results.compactMap { r in
            guard r.subjectPositioning.assessment.isDetermined, r.subjectPositioning.isMeasurementValid,
                  let c = r.subjectPositioning.center else { return nil }
            return PositionMap.Dot(id: r.id, point: c, index: r.selectionOrder + 1)
        }
        let m = profile.positioning

        return ResultCard {
            VStack(alignment: .leading, spacing: 14) {
                FindingSection(title: "Horizontal position", systemImage: kind.systemImage,
                               finding: profile.horizontalPosition, coverage: profile.coverage[kind],
                               order: [.left, .center, .right], label: { $0.label }, thumbnail: thumb)
                Divider()
                FindingSection(title: "Vertical position", systemImage: "arrow.up.and.down",
                               finding: profile.verticalPosition, coverage: nil,
                               order: [.upper, .middle, .lower], label: { $0.label }, thumbnail: thumb,
                               showCoverage: false)

                if !dots.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Subject centres").font(AppFont.subheadline.weight(.semibold))
                        PositionMap(dots: dots, typical: m.typicalCenter)
                        Text(m.typicalCenter == nil
                             ? "Subject centres do not agree closely enough to state a typical position."
                             : "The dashed circle marks the typical centre where photos agree.")
                            .font(AppFont.caption).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 6) {
                        SummaryRow(label: "Center X", summary: m.centerX, consistency: m.centerXConsistency)
                        SummaryRow(label: "Center Y", summary: m.centerY, consistency: m.centerYConsistency)
                        SummaryRow(label: "Subject width", summary: m.width)
                        SummaryRow(label: "Subject height", summary: m.height)
                        SummaryRow(label: "Share of frame", summary: m.area, consistency: m.areaConsistency)
                    }
                }
            }
        }
    }

    // MARK: Depth

    private func depthCard(_ profile: PreferenceProfile) -> some View {
        let kind = CharacteristicKind.environmentalDepth
        let d = profile.depth
        return ResultCard {
            VStack(alignment: .leading, spacing: 14) {
                FindingSection(title: kind.title, systemImage: kind.systemImage,
                               finding: profile.depthStructure, coverage: profile.coverage[kind],
                               order: [.separated, .layered, .foregroundDominant, .partialSeparation, .blended],
                               label: { $0.label }, thumbnail: thumb)
                if d.sampleCount > 0 {
                    Divider()
                    VStack(spacing: 6) {
                        SummaryRow(label: "Subject minus surroundings", summary: d.subjectMinusEnvironment, asPercent: false)
                        SummaryRow(label: "Surroundings nearer", summary: d.fractionEnvironmentNearer)
                        SummaryRow(label: "Surroundings farther", summary: d.fractionEnvironmentFarther)
                    }
                    Text("Relative depth within each photo, not distance.").font(AppFont.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
