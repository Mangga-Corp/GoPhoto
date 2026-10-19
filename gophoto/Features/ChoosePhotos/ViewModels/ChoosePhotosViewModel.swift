//
//  ChoosePhotosViewModel.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import Foundation

final class ChoosePhotosViewModel {
    static let maxPhotos = 20
    static let minPhotos = 3

    enum AddDestination { case limitReached, permission, picker, settings }
    enum Mode { case onboarding, editor }

    // Bindings, set by the view
    var onItemsChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?
    /// Called after every change to the photos so the owner can store them.
    var onPhotosChange: (([PhotoItem]) -> Void)?
    /// Set by the owner; returns an error message, or nil when the new name is accepted.
    var onRename: ((String) -> String?)?

    let mode: Mode
    private let service: ChoosePhotosService
    private(set) var title: String
    private(set) var items: [PhotoItem]
    private(set) var isSelecting = false { didSet { onSelectionChange?() } }
    private(set) var checked: Set<UUID> = []
    private var didRequestAccessOnAppear = false

    init(service: ChoosePhotosService, preferenceName: String, items: [PhotoItem], mode: Mode = .editor) {
        self.service = service
        self.title = preferenceName
        self.items = items
        self.mode = mode
    }

    var isOnboarding: Bool { mode == .onboarding }
    var canRename: Bool { mode == .editor }
    var hasItems: Bool { !items.isEmpty }
    var subtitleText: String { hasItems ? "\(items.count)/\(Self.maxPhotos)" : "" }
    var limitMessage: String { "You can add up to \(Self.maxPhotos) photos." }

    var hasEnoughPhotos: Bool { items.count >= Self.minPhotos }

    /// Nil when the preference has enough photos.
    var minimumPhotosMessage: String? {
        guard !hasEnoughPhotos else { return nil }
        return "Each preference needs at least \(Self.minPhotos) photos. Add \(Self.minPhotos - items.count) more."
    }

    var namePromptTitle: String { "Name your preference" }
    var namePromptMessage: String { "Give this preference a name before we analyze your photos." }

    func isValid(name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Select mode (like the Photos app)

    var selectButtonTitle: String { isSelecting ? "Cancel" : "Select" }

    /// Title shown at the top: the preference name, or the selection count while selecting.
    var displayTitle: String {
        guard isSelecting else { return title }
        switch checked.count {
        case 0: return "Select Items"
        case 1: return "1 Photo Selected"
        default: return "\(checked.count) Photos Selected"
        }
    }

    var canTapDelete: Bool { isSelecting && !checked.isEmpty }
    var deleteConfirmTitle: String { checked.count == 1 ? "Delete Photo" : "Delete \(checked.count) Photos" }
    var deleteConfirmMessage: String {
        checked.count == 1
            ? "This photo will be deleted from this preference. This action can’t be undone."
            : "These photos will be deleted from this preference. This action can’t be undone."
    }

    func toggleSelecting() {
        guard hasItems || isSelecting else { return }
        checked.removeAll()
        isSelecting.toggle()
    }

    func toggleChecked(at index: Int) {
        guard isSelecting, items.indices.contains(index) else { return }
        let id = items[index].id
        if checked.contains(id) { checked.remove(id) } else { checked.insert(id) }
        onSelectionChange?()
    }

    func isChecked(at index: Int) -> Bool { checked.contains(items[index].id) }

    func deleteChecked() {
        guard !checked.isEmpty else { return }
        items.removeAll { checked.contains($0.id) }
        checked.removeAll()
        isSelecting = false
        onItemsChange?()
        onPhotosChange?(items)
    }

    // MARK: - Photos access

    /// Onboarding only: true once, and only if the system prompt hasn't been answered yet.
    func shouldRequestAccessOnAppear() -> Bool {
        guard isOnboarding, !didRequestAccessOnAppear else { return false }
        didRequestAccessOnAppear = true
        return service.access == .notDetermined
    }

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
}
