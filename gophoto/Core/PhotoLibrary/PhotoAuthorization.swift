//
//  PhotoAuthorization.swift
//  gophoto
//
//  Created by Reynard Setiawan on 12/10/26.
//
//  Read/write access to the Photos library (needed to show and delete photos).

import Photos


enum PhotoAccess: Equatable {
    case notDetermined   // never asked
    case allowed         // full or limited (app-made photos are always visible)
    case denied          // denied or restricted → point user to Settings
}

///Protocol for real and mock photoAuthorization
protocol PhotoAuthorizationProtocol: AnyObject {
    func currentAccess() -> PhotoAccess
    func requestAccess() async -> PhotoAccess
}

final class PhotoAuthorization: PhotoAuthorizationProtocol {
    func currentAccess() -> PhotoAccess {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAccess() async -> PhotoAccess {
        Self.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    private static func map(_ status: PHAuthorizationStatus) -> PhotoAccess {
        switch status {
        case .notDetermined:          .notDetermined
        case .authorized, .limited:   .allowed
        case .denied, .restricted:    .denied
        @unknown default:             .denied
        }
    }
}

///To use mock, use debug mode
#if DEBUG
final class MockPhotoAuthorization: PhotoAuthorizationProtocol {
    var access: PhotoAccess
    /// What the fake iOS prompt answers
    var answerOnRequest: PhotoAccess
    private(set) var requestCount = 0

    init(access: PhotoAccess = .allowed, answerOnRequest: PhotoAccess = .allowed) {
        self.access = access
        self.answerOnRequest = answerOnRequest
    }

    func currentAccess() -> PhotoAccess { access }

    func requestAccess() async -> PhotoAccess {
        requestCount += 1
        if access == .notDetermined { access = answerOnRequest }
        return access
    }
}
#endif
