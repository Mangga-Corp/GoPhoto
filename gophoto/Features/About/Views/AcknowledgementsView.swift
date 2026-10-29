//
//  AcknowledgementsView.swift
//  gophoto
//
//  About / acknowledgements: the credits SunKit and Apple Weather ask for.
//
import SwiftUI

struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let weatherService: WeatherServiceProtocol
    @State private var weatherAttribution: WeatherAttributionInfo?

    /// Apple's legal page for weather data, used until (or unless) WeatherKit supplies its own link.
    private static let fallbackLegalURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
    private static let sunlittURL = URL(string: "https://sunlitt.app")!

    init(weatherService: WeatherServiceProtocol = WeatherKitService()) {
        self.weatherService = weatherService
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Sun position") {
                    Link(destination: Self.sunlittURL) {
                        VStack(spacing: 8) {
                            Image("SunKitLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 96, height: 96)
                                .accessibilityHidden(true)
                            Text("Sunlitt")
                                .font(.title3.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    Text("The sun's position is computed on your phone with SunKit by Sunlitt, licensed under the Apache License 2.0.")
                        .font(.footnote)
                    NavigationLink("SunKit license") {
                        ScrollView {
                            Text(Self.licenseText)
                                .font(.caption.monospaced())
                                .padding()
                        }
                        .navigationTitle("SunKit license")
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }

                Section("Weather") {
                    weatherMark
                    Link("Other data sources",
                         destination: weatherAttribution?.legalPageURL ?? Self.fallbackLegalURL)
                }
            }
            .navigationTitle("Acknowledgements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { weatherAttribution = await weatherService.attribution() }
        }
    }

    /// Apple's mark when it could be loaded, its name as text otherwise (offline).
    @ViewBuilder private var weatherMark: some View {
        if let info = weatherAttribution {
            AsyncImage(url: colorScheme == .dark ? info.markDarkURL : info.markLightURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text("Apple Weather")
            }
            .frame(height: 20)
            .accessibilityLabel("Apple Weather")
        } else {
            Label("Apple Weather", systemImage: "apple.logo")
        }
    }

    private static let licenseText: String = {
        guard let url = Bundle.main.url(forResource: "SunKitLicense", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Apache License 2.0 — https://www.apache.org/licenses/LICENSE-2.0"
        }
        return text
    }()
}

#Preview {
    AcknowledgementsView()
}
