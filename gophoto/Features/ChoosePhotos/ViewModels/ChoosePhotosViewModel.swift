//
//  ChoosePhotosViewModel.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import Foundation

final class ChoosePhotosViewModel {
    static let maxPhotos = 20

    enum AddDestination { case limitReached, permission, picker, settings }

    // Bindings, set by the view
    var onItemsChange: (() -> Void)?
    var onEditingChange: (() -> Void)?
    /// Called after every add/remove so the owner can store the photos.
    var onPhotosChange: (([PhotoItem]) -> Void)?

    private let service: ChoosePhotosService
    private let preferenceName: String
    private(set) var items: [PhotoItem]
    private(set) var isEditing = false { didSet { onEditingChange?() } }

    init(service: ChoosePhotosService, preferenceName: String, items: [PhotoItem]) {
        self.service = service
        self.preferenceName = preferenceName
        self.items = items
    }

    var hasItems: Bool { !items.isEmpty }
    var subtitleText: String { hasItems ? "\(preferenceName) · \(items.count)/\(Self.maxPhotos)" : preferenceName }
    var editButtonTitle: String { isEditing ? "Done" : "Edit" }
    var limitMessage: String { "You can add up to \(Self.maxPhotos) photos." }

    func addTapped() -> AddDestination {
        guard items.count < Self.maxPhotos else { return .limitReached }
        switch service.access {
        case .notDetermined: return .permission
        case .authorized, .limited: return .picker
        case .denied: return .settings
        }
    }

    func requestAccess(completion: @escaping (_ canBrowse: Bool) -> Void) {
        service.requestAccess { completion($0.canBrowse) }
    }

    func makePickerViewModel() -> SelectPhotoViewModel {
        SelectPhotoViewModel(service: service, remaining: Self.maxPhotos - items.count, limit: Self.maxPhotos)
    }

    func append(_ newItems: [PhotoItem]) {
        guard !newItems.isEmpty else { return }
        items += newItems.prefix(Self.maxPhotos - items.count)
        onItemsChange?()
        onPhotosChange?(items)
    }

    func toggleEditing() {
        guard hasItems else { return }
        isEditing.toggle()
    }

    func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        if items.isEmpty { isEditing = false }
        onItemsChange?()
        onPhotosChange?(items)
    }
}
