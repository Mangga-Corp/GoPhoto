//
//  PhotoItem.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit

struct PhotoItem {
    let id: UUID
    let image: UIImage

    init(id: UUID = UUID(), image: UIImage) {
        self.id = id
        self.image = image
    }
}
