import Observation
import UIKit

@Observable
final class FacePickerViewModel {
    enum State: Equatable {
        case idle
        case unsupported
        case needsAccess
        case limitedAccess
        case scanning(FaceGroupingProgress)
        case done
        case failed(String)
    }

    static let maxFaces = 600
    static let maxPhotos = 1500
    static let shownGroupCount = 6

    private(set) var state: State = .idle
    private(set) var groups: [PersonGroup] = []
    private(set) var covers: [String: UIImage] = [:]
    private(set) var pickedGroup: PersonGroup?
    private(set) var pickedPhotos: [PersonPhoto] = []
    private(set) var isShowingAllGroups = false

    @ObservationIgnored private var result: FaceGroupingResult?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private let service: FaceGrouping?

    init(service: FaceGrouping? = FaceGroupingAvailability.makeService()) {
        self.service = service
    }

    var shownGroups: [PersonGroup] {
        isShowingAllGroups ? groups : Array(groups.prefix(Self.shownGroupCount))
    }
    var hasMoreGroups: Bool { !isShowingAllGroups && groups.count > Self.shownGroupCount }
    var faceCount: Int { result?.facesByAsset.values.reduce(0) { $0 + $1.count } ?? 0 }
    var photosChecked: Int { result?.photosChecked ?? 0 }
    var includedPhotos: [PersonPhoto] { pickedPhotos.filter { PersonPhotoFilter.isIncluded($0.presence) } }
    var groupPhotos: [PersonPhoto] { pickedPhotos.filter { $0.presence == .group } }

    func start() {
        guard service != nil else { state = .unsupported; return }
        scanTask?.cancel()
        scanTask = Task { await requestAccessAndScan() }
    }

    func continueWithLimitedAccess() {
        scanTask?.cancel()
        scanTask = Task { await scan() }
    }

    func dismissLimitedAccess() {
        if state == .limitedAccess { state = .idle }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func showAllGroups() {
        isShowingAllGroups = true
    }

    func pick(_ group: PersonGroup) {
        pickedGroup = group
        let facesByAsset = result?.facesByAsset ?? [:]
        pickedPhotos = facesByAsset.compactMap { assetID, faces in
            let presence = PersonPhotoFilter.presence(of: group.id, in: faces)
            guard presence != .absent else { return nil }
            let face = faces.filter { $0.entityID == group.id }.max { $0.area < $1.area }
            return PersonPhoto(id: assetID, presence: presence,
                               thumbnailURL: result?.thumbnailURLs[assetID], faceBounds: face?.bounds)
        }
        .sorted { $0.id < $1.id }
    }

    func clear() {
        cancelScan()
        result = nil
        groups = []
        covers = [:]
        pickedGroup = nil
        pickedPhotos = []
        isShowingAllGroups = false
        state = .idle
        guard let service else { return }
        Task { await service.clear() }
    }

    private func requestAccessAndScan() async {
        switch await PhotoLibraryAccess.request() {
        case .denied: state = .needsAccess
        case .limited: state = .limitedAccess
        case .full: await scan()
        }
    }

    private func scan() async {
        guard let service else { return }
        state = .scanning(FaceGroupingProgress(photosChecked: 0, facesFound: 0))
        do {
            let found = try await service.scan(maxFaces: Self.maxFaces, maxPhotos: Self.maxPhotos) { [weak self] progress in
                Task { @MainActor in
                    guard let self, case .scanning = self.state else { return }
                    self.state = .scanning(progress)
                }
            }
            result = found
            groups = found.groups
            covers = await Self.covers(for: Array(found.groups.prefix(Self.shownGroupCount)),
                                       thumbnails: found.thumbnailURLs)
            state = .done
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed("Couldn't scan your photos. Please try again.")
        }
    }

    @concurrent
    nonisolated private static func covers(for groups: [PersonGroup],
                                           thumbnails: [String: URL]) async -> [String: UIImage] {
        var covers: [String: UIImage] = [:]
        for group in groups {
            guard let face = group.cover, let url = thumbnails[face.assetID],
                  let crop = FaceCrop.image(at: url, face: face.bounds) else { continue }
            covers[group.id] = crop
        }
        return covers
    }
}
