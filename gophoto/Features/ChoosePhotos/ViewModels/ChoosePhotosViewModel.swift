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
    private (set) var title: String
    var onRename: ((String) -> String?)?
    private(set) var items: [PhotoItem]
    private(set) var isEditing = false { didSet { onEditingChange?() } }

    enum Mode { case onboarding, editor }

    let mode: Mode
    private var didRequestAccessOnAppear = false

    init(service: ChoosePhotosService, preferenceName: String, items: [PhotoItem], mode: Mode = .editor) {
        self.service = service
        self.title = preferenceName
        self.items = items
        self.mode = mode
    }

    var isOnboarding: Bool { mode == .onboarding }
    var canRename: Bool { mode == .editor }

    /// Onboarding only: true once, and only if the system prompt hasn't been answered yet.
    func shouldRequestAccessOnAppear() -> Bool {
        guard isOnboarding, !didRequestAccessOnAppear else { return false }
        didRequestAccessOnAppear = true
        return service.access == .notDetermined
    }

    var hasItems: Bool { !items.isEmpty }
    var subtitleText: String { hasItems ? "\(items.count)/\(Self.maxPhotos)" : "" }
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
    
    /// Returns an error message, or nil when renamed.
    func rename(to newName: String) -> String? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != title else { return nil }
        if let error = onRename?(trimmed) { return error }
        title = trimmed
        return nil
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
