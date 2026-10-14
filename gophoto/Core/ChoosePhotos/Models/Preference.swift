//
//  Preference.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import Foundation

struct Preference {
    let id = UUID()
    var name: String
    var photos: [PhotoItem] = []
}
