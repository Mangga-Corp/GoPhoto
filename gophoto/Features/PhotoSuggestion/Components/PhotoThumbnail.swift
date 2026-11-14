import SwiftUI

struct PhotoThumbnail: View {
    let url: URL?
    var width: CGFloat = 96

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(GoPhotoDesign.secondaryBackground)
            }
        }
        .frame(width: width, height: width * 4 / 3)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: url) {
            guard let url else { return }
            image = await Task.detached { FaceCrop.thumbnail(at: url) }.value
        }
    }
}
