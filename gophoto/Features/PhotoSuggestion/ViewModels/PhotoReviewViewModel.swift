import Observation

@Observable
final class PhotoReviewViewModel {
    enum State: Equatable {
        case grading
        case ready
        case loading
        case failed(String)
    }

    static let preselectCount = 20
    static let minPhotos = ChoosePhotosViewModel.minPhotos
    static let maxPhotos = ChoosePhotosViewModel.maxPhotos

    private(set) var state: State = .grading
    /// Photos that passed the quality gate, best first.
    private(set) var photos: [PersonPhoto] = []
    private(set) var droppedCount = 0
    private(set) var selectedIDs: Set<String> = []

    @ObservationIgnored private let candidates: [PersonPhoto]
    @ObservationIgnored private let meter: PhotoQualityMetering
    @ObservationIgnored private let photoLoader: ChoosePhotosService

    init(candidates: [PersonPhoto],
         meter: PhotoQualityMetering = PhotoQualityMeter(),
         photoLoader: ChoosePhotosService = ChoosePhotosService()) {
        self.candidates = candidates
        self.meter = meter
        self.photoLoader = photoLoader
    }

    var selectedCount: Int { selectedIDs.count }
    var canContinue: Bool { state == .ready && (Self.minPhotos...Self.maxPhotos).contains(selectedCount) }
    var isFull: Bool { selectedCount >= Self.maxPhotos }

    func grade() async {
        guard state == .grading else { return }
        let qualities = await meter.measure(candidates)
        let kept = PhotoQualityGate.rank(qualities.filter(PhotoQualityGate.passes))
        droppedCount = qualities.count - kept.count
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        photos = kept.compactMap { byID[$0.assetID] }
        selectedIDs = Set(photos.prefix(Self.preselectCount).map(\.id))
        state = .ready
    }

    func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else if !isFull {
            selectedIDs.insert(id)
        }
    }

    func isSelected(_ id: String) -> Bool { selectedIDs.contains(id) }

    /// Loads the selected photos the same way the manual picker does. nil on failure.
    func loadSelection() async -> [PhotoItem]? {
        guard canContinue else { return nil }
        state = .loading
        let ids = photos.map(\.id).filter { selectedIDs.contains($0) }
        let assets = PhotoAssets.ordered(ids)
        let loaded: Result<[PhotoItem], Error> = await withCheckedContinuation { continuation in
            photoLoader.loadItems(for: assets) { continuation.resume(returning: $0) }
        }
        switch loaded {
        case .success(let items):
            state = .ready
            return items
        case .failure:
            state = .failed("Couldn't load the photos. Please try again.")
            return nil
        }
    }
}
