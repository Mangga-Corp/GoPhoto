import Photos

nonisolated enum FaceGroupingAvailability {
    /// Face grouping needs MediaIntelligence (iOS 27). Older phones keep the manual picker only.
    static var isSupported: Bool {
        if #available(iOS 27.0, *) { true } else { false }
    }

    static func makeService() -> FaceGrouping? {
        if #available(iOS 27.0, *) { FaceGroupAnalyzerService() } else { nil }
    }

    static func purgeLeftovers() async {
        if #available(iOS 27.0, *) { await FaceGroupAnalyzerService.purgeLeftovers() }
    }
}

nonisolated enum PhotoLibraryAccess {
    enum Level { case full, limited, denied }

    static func request() async -> Level {
        switch await PHPhotoLibrary.requestAuthorization(for: .readWrite) {
        case .authorized: .full
        case .limited: .limited
        default: .denied
        }
    }
}
