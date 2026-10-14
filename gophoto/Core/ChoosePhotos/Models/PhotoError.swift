//
//  PhotoError.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import Foundation

enum PhotoError: LocalizedError {
    case loadFailed
    var errorDescription: String? { "Some photos couldn’t be loaded. Please try again." }
}
