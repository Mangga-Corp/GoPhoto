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
    /// 35 mm-equivalent focal length from the original photo's EXIF, when it has one and the
    /// photo still has the camera's 4:3 frame (a crop changes the field of view).
    var focalLength35mm: Double?

    init(id: UUID = UUID(), image: UIImage, focalLength35mm: Double? = nil) {
        self.id = id
        self.image = image
        self.focalLength35mm = focalLength35mm
    }
}
