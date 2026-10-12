//
//  PhotoAccess.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

enum PhotoAccess {
    case notDetermined, authorized, limited, denied

    var canBrowse: Bool { self == .authorized || self == .limited }
}
