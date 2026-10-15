//
//  ZoomableImageView.swift
//  gophoto
//
//  Created by Reynard Setiawan on 15/10/26.
//
//  Pinch to zoom, double-tap to zoom in/out, pan while zoomed: like the Photos app.
//  SwiftUI has no zooming scroll view, so this wraps UIScrollView.
//

import SwiftUI
import UIKit

/// SwiftUI wrapper. Use it like an Image: ZoomableImageView(image: uiImage)
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    /// Called when the user starts zooming in (used to load a sharper image)
    var onZoomIn: (() -> Void)? = nil

    func makeUIView(context: Context) -> ZoomingScrollView {
        ZoomingScrollView()
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        view.onZoomIn = onZoomIn
        // Only swap when it's a different image (avoids resetting zoom on every redraw)
        if view.image !== image {
            view.image = image
        }
    }
}

/// UIScrollView that holds one image and handles zoom + centering.
final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {

    private let imageView = UIImageView()
    /// Last size we fitted the image to; re-fit only when it changes (first layout / rotation)
    private var fittedForSize: CGSize = .zero

    var onZoomIn: (() -> Void)?

    var image: UIImage? {
        didSet {
            imageView.image = image
            // Same photo in higher resolution (same shape) → keep zoom & position
            if let old = oldValue, let new = image,
               abs(old.size.width / old.size.height - new.size.width / new.size.height) < 0.01 {
                return
            }
            fittedForSize = .zero      // different photo → re-fit
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never   // we center the image ourselves
        backgroundColor = .clear

        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedForSize {
            fittedForSize = bounds.size
            zoomScale = 1
            imageView.frame = CGRect(origin: .zero, size: fittedImageSize())
            contentSize = imageView.frame.size
        }
        centerImage()
    }

    /// Image size scaled to fit the screen without cropping (aspect fit)
    private func fittedImageSize() -> CGSize {
        guard let size = image?.size, size.width > 0, size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return bounds.size }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Keeps the photo in the middle when it's smaller than the screen
    private func centerImage() {
        let offsetX = max((bounds.width - contentSize.width) / 2, 0)
        let offsetY = max((bounds.height - contentSize.height) / 2, 0)
        imageView.center = CGPoint(x: contentSize.width / 2 + offsetX,
                                   y: contentSize.height / 2 + offsetY)
    }

    // MARK: - UIScrollViewDelegate

    /// Tells UIScrollView which view to scale when pinching
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        if zoomScale > minimumZoomScale {
            onZoomIn?()
        }
    }

    // MARK: - Double tap

    /// Zoomed in → back to fit. At fit → zoom 2.5× into the tapped spot.
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let scale: CGFloat = 2.5
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            let rect = CGRect(x: point.x - size.width / 2,
                              y: point.y - size.height / 2,
                              width: size.width, height: size.height)
            zoom(to: rect, animated: true)
        }
    }
}
