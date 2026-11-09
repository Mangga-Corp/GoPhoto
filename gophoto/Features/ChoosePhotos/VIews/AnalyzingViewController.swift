//
//  AnalyzingViewController.swift
//  gophoto
//
//  Created by Sebastian Darren on 14/10/26.
//

import SwiftUI
import UIKit

// MARK: - Photo Card View
/// Komponen kartu foto individual dengan background solid (mencegah warna nyaru / bertumpuk),
/// border ungu dinamis, dan badge ceklis animasi.
private final class PhotoCardView: UIView {
    let imageView = UIImageView()
    let checkmarkContainer = UIView()
    let checkmarkIcon = UIImageView()

    private(set) var photoIndex: Int = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupViews() {
        clipsToBounds = false
        // Background solid putih agar gambar di atasnya tidak transparan / nyaru
        backgroundColor = UIColor(GoPhotoDesign.surface)

        // Image View
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        // Checkmark badge (Lingkaran ungu dengan ikon ceklis putih di kanan bawah)
        checkmarkContainer.backgroundColor = UIColor(GoPhotoDesign.primary)
        checkmarkContainer.clipsToBounds = true
        checkmarkContainer.translatesAutoresizingMaskIntoConstraints = false
        checkmarkContainer.layer.shadowColor = UIColor.black.cgColor
        checkmarkContainer.layer.shadowOpacity = 0.15
        checkmarkContainer.layer.shadowOffset = CGSize(width: 0, height: 2)
        checkmarkContainer.layer.shadowRadius = 3
        checkmarkContainer.alpha = 0
        addSubview(checkmarkContainer)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        checkmarkIcon.image = UIImage(systemName: "checkmark", withConfiguration: symbolConfig)
        checkmarkIcon.tintColor = .white
        checkmarkIcon.contentMode = .center
        checkmarkIcon.translatesAutoresizingMaskIntoConstraints = false
        checkmarkContainer.addSubview(checkmarkIcon)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            checkmarkContainer.widthAnchor.constraint(equalToConstant: 24),
            checkmarkContainer.heightAnchor.constraint(equalToConstant: 24),
            checkmarkContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            checkmarkContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            checkmarkIcon.centerXAnchor.constraint(equalTo: checkmarkContainer.centerXAnchor),
            checkmarkIcon.centerYAnchor.constraint(equalTo: checkmarkContainer.centerYAnchor)
        ])

        checkmarkContainer.layer.cornerRadius = 12
    }

    func configure(with photo: PhotoItem, index: Int) {
        self.photoIndex = index
        self.imageView.image = photo.image
    }

    func setAppearance(
        cornerRadius: CGFloat,
        borderWidth: CGFloat,
        borderColor: UIColor,
        showCheckmark: Bool,
        alphaVal: CGFloat
    ) {
        self.alpha = alphaVal
        self.layer.cornerRadius = cornerRadius
        self.imageView.layer.cornerRadius = cornerRadius
        self.imageView.layer.borderWidth = borderWidth
        self.imageView.layer.borderColor = borderColor.cgColor
        self.checkmarkContainer.alpha = showCheckmark ? 1.0 : 0.0
    }

    func animateCheckmarkAppearance() {
        checkmarkContainer.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        checkmarkContainer.alpha = 0
        UIView.animate(
            withDuration: 0.35,
            delay: 0.1,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.3,
            options: [.curveEaseOut]
        ) {
            self.checkmarkContainer.transform = .identity
            self.checkmarkContainer.alpha = 1.0
        }
    }
}

// MARK: - Pulsing Oval View
/// Komponen view khusus untuk animasi oval bernapas di belakang foto.
/// Menggunakan AutoLayout langsung (centerXAnchor & centerYAnchor),
/// sehingga dijamin 100% selalu terkunci di tengah secara default (bahkan tanpa foto sekalipun).
private final class PulsingOvalView: UIView {
    let primaryOvalLayer = CAShapeLayer()
    let secondaryOvalLayer = CAShapeLayer()

    let ovalBaseWidth: CGFloat
    let ovalBaseHeight: CGFloat
    let ovalBorderWidth: CGFloat
    let ovalColor: UIColor
    let ovalMinScale: CGFloat
    let ovalMaxScale: CGFloat
    let ovalAnimationDuration: CFTimeInterval

    init(
        width: CGFloat = 190,
        height: CGFloat = 200,
        borderWidth: CGFloat = 1.5,
        color: UIColor = UIColor(GoPhotoDesign.primary),
        minScale: CGFloat = 0.80,
        maxScale: CGFloat = 1.30,
        duration: CFTimeInterval = 2.0
    ) {
        self.ovalBaseWidth = width
        self.ovalBaseHeight = height
        self.ovalBorderWidth = borderWidth
        self.ovalColor = color
        self.ovalMinScale = minScale
        self.ovalMaxScale = maxScale
        self.ovalAnimationDuration = duration
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        backgroundColor = .clear

        let ovalRect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        let ovalPath = UIBezierPath(ovalIn: ovalRect).cgPath

        // Primary oval
        primaryOvalLayer.path = ovalPath
        primaryOvalLayer.fillColor = UIColor.clear.cgColor
        primaryOvalLayer.strokeColor = color.withAlphaComponent(0.50).cgColor
        primaryOvalLayer.lineWidth = borderWidth
        primaryOvalLayer.opacity = 0.70

        // Secondary oval (offset phase)
        secondaryOvalLayer.path = ovalPath
        secondaryOvalLayer.fillColor = UIColor.clear.cgColor
        secondaryOvalLayer.strokeColor = color.withAlphaComponent(0.25).cgColor
        secondaryOvalLayer.lineWidth = borderWidth * 0.7
        secondaryOvalLayer.opacity = 0.50

        layer.addSublayer(secondaryOvalLayer)
        layer.addSublayer(primaryOvalLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Kunci posisi sublayer selalu tepat di tengah PulsingOvalView
        let mid = CGPoint(x: bounds.midX, y: bounds.midY)
        primaryOvalLayer.position = mid
        secondaryOvalLayer.position = mid
    }

    func startPulsing() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        // Primary breathe
        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = ovalMinScale
        breathe.toValue = ovalMaxScale
        breathe.duration = ovalAnimationDuration
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        primaryOvalLayer.add(breathe, forKey: "breathe")

        // Secondary breathe with phase offset
        let breathe2 = CABasicAnimation(keyPath: "transform.scale")
        breathe2.fromValue = ovalMaxScale
        breathe2.toValue = ovalMinScale
        breathe2.duration = ovalAnimationDuration
        breathe2.autoreverses = true
        breathe2.repeatCount = .infinity
        breathe2.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        breathe2.beginTime = CACurrentMediaTime() + ovalAnimationDuration / 2
        secondaryOvalLayer.add(breathe2, forKey: "breathe2")

        // Opacity pulse
        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 0.5
        opacityAnim.toValue = 0.8
        opacityAnim.duration = ovalAnimationDuration
        opacityAnim.autoreverses = true
        opacityAnim.repeatCount = .infinity
        opacityAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        primaryOvalLayer.add(opacityAnim, forKey: "opacityPulse")
    }
}

// MARK: - AnalyzingViewController
final class AnalyzingViewController: UIViewController {
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?

    private let viewModel: AnalyzingViewModel
    private let photos: [PhotoItem]
    private var didStart = false

    // MARK: - ⚙️ Pengaturan Dimensi Foto Carousel
    /// Ukuran foto di tengah (sedang di-train, lebih besar)
    private let centerCardSize: CGFloat = 145
    /// Ukuran foto di samping kiri & kanan (sudah / belum di-train)
    private let sideCardSize: CGFloat = 100
    /// Jarak horizontal antar kartu foto
    private let photoSpacing: CGFloat = 14
    /// Radius kelengkungan sudut foto tengah
    private let centerCornerRadius: CGFloat = 20
    /// Radius kelengkungan sudut foto samping
    private let sideCornerRadius: CGFloat = 14

    // Dimensi pasti kontainer carousel
    private var containerWidth: CGFloat {
        sideCardSize + photoSpacing + centerCardSize + photoSpacing + sideCardSize
    }
    private var containerHeight: CGFloat {
        centerCardSize + 30
    }

    // MARK: - UI Components

    // Container pembungkus seluruh konten tengah agar berada pas di tengah layar
    private let contentContainer = UIView()

    // Title ("Finding your style")
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "Finding your style"
        l.font = .systemFont(ofSize: 32, weight: .bold)
        l.textColor = UIColor(GoPhotoDesign.primaryText)
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }()

    // Carousel Container
    private let carouselContainer = UIView()

    // Slot kartu aktif (Sistem REPLACE murni: hanya ada maksimal 3 kartu, tidak ada kartu bertumpuk di belakang)
    private var leftCard: PhotoCardView?
    private var centerCard: PhotoCardView?
    private var rightCard: PhotoCardView?

    // Pulsing Oval View (mengambil langsung pengaturan dari PulsingOvalView di atas)
    private lazy var pulsingOvalView = PulsingOvalView()

    // Reading label: "Reading photo 3 of 9"
    private let readingLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        l.textColor = UIColor(GoPhotoDesign.primaryText)
        l.textAlignment = .center
        return l
    }()

    // Segmented progress bar
    private let progressStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 5
        sv.distribution = .fillEqually
        sv.alignment = .fill
        return sv
    }()
    private var progressSegments: [UIView] = []

    // Checking description label ("Checking your angles")
    private let checkingLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15, weight: .regular)
        l.textColor = UIColor(GoPhotoDesign.secondaryText)
        l.textAlignment = .center
        return l
    }()

    // Estimated time label ("This usually takes about 15 seconds")
    private let estimateLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .regular)
        l.textColor = UIColor(GoPhotoDesign.secondaryText)
        l.textAlignment = .center
        return l
    }()

    // Cancel Button (tetap warna ungu di bagian bawah layar)
    private let cancelButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Cancel", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        b.setTitleColor(UIColor(GoPhotoDesign.primary), for: .normal)
        return b
    }()

    // State Tracking
    private var currentPhotoIndex = 0
    private var isAnimatingSlide = false
    private var pendingSlideIndex: Int?
    private var hasLaidOutInitialCarousel = false

    // MARK: - Lifecycle

    init(viewModel: AnalyzingViewModel, photos: [PhotoItem]) {
        self.viewModel = viewModel
        self.photos = photos
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = UIColor(GoPhotoDesign.background)

        setupLayout()
        setupSegmentedProgressBar()
        setupCallbacks()

        updateReadingText(currentIndex: 0, total: photos.count)
        checkingLabel.text = viewModel.initialMessage
        let initialSeconds = max(photos.count * 3, 10)
        estimateLabel.text = "This usually takes about \(initialSeconds) seconds"

        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if !hasLaidOutInitialCarousel && carouselContainer.bounds.width > 0 {
            hasLaidOutInitialCarousel = true
            layoutInitialCards(currentIndex: 0)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStart else { return }
        didStart = true
        pulsingOvalView.startPulsing()
        viewModel.start(with: photos)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.cancel()
    }

    // MARK: - Setup UI & Layout

    private func setupLayout() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        carouselContainer.translatesAutoresizingMaskIntoConstraints = false
        readingLabel.translatesAutoresizingMaskIntoConstraints = false
        progressStackView.translatesAutoresizingMaskIntoConstraints = false
        checkingLabel.translatesAutoresizingMaskIntoConstraints = false
        estimateLabel.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        // Pastikan carouselContainer tidak memotong layer oval yang membesar
        carouselContainer.clipsToBounds = false

        // Pasang oval bernapas di posisi paling belakang dengan AutoLayout (pasti selalu di tengah)
        pulsingOvalView.translatesAutoresizingMaskIntoConstraints = false
        carouselContainer.insertSubview(pulsingOvalView, at: 0)

        // Tambahkan elemen ke dalam contentContainer
        contentContainer.addSubview(titleLabel)
        contentContainer.addSubview(carouselContainer)
        contentContainer.addSubview(readingLabel)
        contentContainer.addSubview(progressStackView)
        contentContainer.addSubview(checkingLabel)
        contentContainer.addSubview(estimateLabel)

        view.addSubview(contentContainer)
        view.addSubview(cancelButton)

        let safe = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            // Oval terkunci 100% di tengah carouselContainer secara permanen
            pulsingOvalView.centerXAnchor.constraint(equalTo: carouselContainer.centerXAnchor),
            pulsingOvalView.centerYAnchor.constraint(equalTo: carouselContainer.centerYAnchor),
            pulsingOvalView.widthAnchor.constraint(equalToConstant: pulsingOvalView.ovalBaseWidth),
            pulsingOvalView.heightAnchor.constraint(equalToConstant: pulsingOvalView.ovalBaseHeight),

            // Content Container diposisikan di tengah vertikal layar
            contentContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contentContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -24),
            contentContainer.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: safe.trailingAnchor),

            // 1. Title Label di bagian atas kontainer
            titleLabel.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -24),

            // 2. Carousel Container
            carouselContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 36),
            carouselContainer.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            carouselContainer.widthAnchor.constraint(equalToConstant: containerWidth),
            carouselContainer.heightAnchor.constraint(equalToConstant: containerHeight),

            // 3. "Reading photo X of Y"
            readingLabel.topAnchor.constraint(equalTo: carouselContainer.bottomAnchor, constant: 24),
            readingLabel.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),

            // 4. Segmented Progress Bar
            progressStackView.topAnchor.constraint(equalTo: readingLabel.bottomAnchor, constant: 14),
            progressStackView.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            progressStackView.widthAnchor.constraint(equalToConstant: min(CGFloat(photos.count) * 32, 280)),
            progressStackView.heightAnchor.constraint(equalToConstant: 7),

            // 5. Checking step
            checkingLabel.topAnchor.constraint(equalTo: progressStackView.bottomAnchor, constant: 18),
            checkingLabel.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            checkingLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentContainer.leadingAnchor, constant: 24),
            checkingLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentContainer.trailingAnchor, constant: -24),

            // 6. Estimated time
            estimateLabel.topAnchor.constraint(equalTo: checkingLabel.bottomAnchor, constant: 6),
            estimateLabel.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            estimateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentContainer.leadingAnchor, constant: 24),
            estimateLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentContainer.trailingAnchor, constant: -24),
            estimateLabel.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            // 7. Cancel Button di bagian paling bawah
            cancelButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -32),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupSegmentedProgressBar() {
        progressSegments.removeAll()
        for _ in 0..<photos.count {
            let seg = UIView()
            seg.backgroundColor = UIColor(GoPhotoDesign.primarySubtle)
            seg.layer.cornerRadius = 3.5
            seg.clipsToBounds = true
            seg.translatesAutoresizingMaskIntoConstraints = false
            progressSegments.append(seg)
            progressStackView.addArrangedSubview(seg)
        }
        updateProgressBar(finishedCount: 0)
    }

    // MARK: - Carousel Management: Clean Replace Architecture (KOREKSI 2)

    private func frameForSlot(_ slot: Slot) -> CGRect {
        let midX = containerWidth / 2
        let midY = containerHeight / 2
        let shift = (centerCardSize / 2) + photoSpacing + (sideCardSize / 2)

        switch slot {
        case .left:
            return CGRect(x: midX - shift - (sideCardSize / 2), y: midY - (sideCardSize / 2), width: sideCardSize, height: sideCardSize)
        case .center:
            return CGRect(x: midX - (centerCardSize / 2), y: midY - (centerCardSize / 2), width: centerCardSize, height: centerCardSize)
        case .right:
            return CGRect(x: midX + shift - (sideCardSize / 2), y: midY - (sideCardSize / 2), width: sideCardSize, height: sideCardSize)
        case .offscreenLeft:
            return CGRect(x: midX - (shift * 1.8) - (sideCardSize / 2), y: midY - (sideCardSize / 2), width: sideCardSize * 0.8, height: sideCardSize * 0.8)
        case .offscreenRight:
            return CGRect(x: midX + (shift * 1.8) - (sideCardSize / 2), y: midY - (sideCardSize / 2), width: sideCardSize * 0.8, height: sideCardSize * 0.8)
        }
    }

    private enum Slot {
        case offscreenLeft
        case left
        case center
        case right
        case offscreenRight
    }

    /// Setup awal 3 kartu tanpa ada kartu sisa / bertumpuk di belakang
    private func layoutInitialCards(currentIndex: Int) {
        guard !photos.isEmpty, photos.indices.contains(currentIndex) else { return }
        self.currentPhotoIndex = currentIndex

        // Bersihkan jika ada view lama di container
        leftCard?.removeFromSuperview()
        centerCard?.removeFromSuperview()
        rightCard?.removeFromSuperview()
        leftCard = nil
        centerCard = nil
        rightCard = nil

        // 1. Kartu Kiri (jika ada foto sebelumnya yang sudah selesai)
        let leftIdx = currentIndex - 1
        if photos.indices.contains(leftIdx) {
            let card = PhotoCardView()
            card.configure(with: photos[leftIdx], index: leftIdx)
            card.frame = frameForSlot(.left)
            card.setAppearance(
                cornerRadius: sideCornerRadius,
                borderWidth: 0,
                borderColor: .clear,
                showCheckmark: true,
                alphaVal: 0.80
            )
            carouselContainer.addSubview(card)
            leftCard = card
        }

        // 2. Kartu Tengah (sedang di-train, lebih besar)
        let cCard = PhotoCardView()
        cCard.configure(with: photos[currentIndex], index: currentIndex)
        cCard.frame = frameForSlot(.center)
        cCard.setAppearance(
            cornerRadius: centerCornerRadius,
            borderWidth: 2.5,
            borderColor: UIColor(GoPhotoDesign.primary),
            showCheckmark: false,
            alphaVal: 1.0
        )
        carouselContainer.addSubview(cCard)
        centerCard = cCard

        // 3. Kartu Kanan (belum di-train)
        let rightIdx = currentIndex + 1
        if photos.indices.contains(rightIdx) {
            let card = PhotoCardView()
            card.configure(with: photos[rightIdx], index: rightIdx)
            card.frame = frameForSlot(.right)
            card.setAppearance(
                cornerRadius: sideCornerRadius,
                borderWidth: 0,
                borderColor: .clear,
                showCheckmark: false,
                alphaVal: 0.50
            )
            carouselContainer.addSubview(card)
            rightCard = card
        }

        // Pastikan kartu tengah berada di atas kartu samping jika ada overlap tepi
        carouselContainer.bringSubviewToFront(cCard)
    }

    /// Animasi Slide Murni (Replace, bukan tumpukan):
    /// - Kartu kiri lama keluar dan dihapus dari memori (`removeFromSuperview()`).
    /// - Kartu tengah menjadi kartu kiri (mengecil, border hilang, muncul ceklis).
    /// - Kartu kanan menjadi kartu tengah (membesar, dapat border ungu, alpha 1.0).
    /// - Kartu kanan baru masuk dari kanan luar layar.
    private func slideToPhoto(newIndex: Int) {
        guard photos.indices.contains(newIndex), newIndex > currentPhotoIndex else { return }

        if isAnimatingSlide {
            pendingSlideIndex = newIndex
            return
        }

        isAnimatingSlide = true
        self.currentPhotoIndex = newIndex

        let oldLeftCard = self.leftCard
        guard let movingToLeftCard = self.centerCard else {
            isAnimatingSlide = false
            return
        }

        let movingToCenterCard = self.rightCard

        // Siapkan kartu baru di kanan (jika ada foto berikutnya)
        var incomingRightCard: PhotoCardView?
        let nextRightIdx = newIndex + 1
        if photos.indices.contains(nextRightIdx) {
            let card = PhotoCardView()
            card.configure(with: photos[nextRightIdx], index: nextRightIdx)
            card.frame = frameForSlot(.offscreenRight)
            card.setAppearance(
                cornerRadius: sideCornerRadius,
                borderWidth: 0,
                borderColor: .clear,
                showCheckmark: false,
                alphaVal: 0.0
            )
            carouselContainer.addSubview(card)
            incomingRightCard = card
        }

        if let center = movingToCenterCard {
            carouselContainer.bringSubviewToFront(center)
        }

        // KOREKSI 4: Animasi diperhalus dengan spring curve optimal
        UIView.animate(
            withDuration: 0.65,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.15,
            options: [.curveEaseInOut]
        ) {
            // 1. Kartu kiri lama geser keluar dan hilang
            if let oldLeft = oldLeftCard {
                oldLeft.frame = self.frameForSlot(.offscreenLeft)
                oldLeft.alpha = 0
            }

            // 2. Kartu tengah geser ke kiri -> mengecil jadi kartu kiri
            movingToLeftCard.frame = self.frameForSlot(.left)
            movingToLeftCard.setAppearance(
                cornerRadius: self.sideCornerRadius,
                borderWidth: 0,
                borderColor: .clear,
                showCheckmark: true,
                alphaVal: 0.80
            )

            // 3. Kartu kanan geser ke tengah -> membesar jadi kartu tengah
            if let movingCenter = movingToCenterCard {
                movingCenter.frame = self.frameForSlot(.center)
                movingCenter.setAppearance(
                    cornerRadius: self.centerCornerRadius,
                    borderWidth: 2.5,
                    borderColor: UIColor(GoPhotoDesign.primary),
                    showCheckmark: false,
                    alphaVal: 1.0
                )
            }

            // 4. Kartu baru masuk ke slot kanan
            if let incoming = incomingRightCard {
                incoming.frame = self.frameForSlot(.right)
                incoming.alpha = 0.50
            }
        } completion: { [weak self] _ in
            guard let self = self else { return }

            // KOREKSI 2: Hapus kartu lama yang keluar dari view hierarchy (tidak menumpuk)
            oldLeftCard?.removeFromSuperview()

            // Re-assign pointer slot secara bersih
            self.leftCard = movingToLeftCard
            self.centerCard = movingToCenterCard
            self.rightCard = incomingRightCard

            // Animasikan pop icon ceklis di kartu kiri yang baru selesai
            movingToLeftCard.animateCheckmarkAppearance()

            self.isAnimatingSlide = false

            // Jika ada antrian animasi slide berikutnya
            if let next = self.pendingSlideIndex {
                self.pendingSlideIndex = nil
                self.slideToPhoto(newIndex: next)
            }
        }
    }

    // MARK: - Callbacks & Data Flow

    private func setupCallbacks() {
        viewModel.onPhotoFinished = { [weak self] finished, total in
            guard let self = self else { return }
            self.updateProgressBar(finishedCount: finished)
            let nextIndex = min(finished, total - 1)
            self.updateReadingText(currentIndex: nextIndex, total: total)
            if finished < total {
                self.slideToPhoto(newIndex: finished)
            }
        }

        viewModel.onCheckingUpdate = { [weak self] step, remainingSeconds in
            guard let self = self else { return }
            UIView.transition(with: self.checkingLabel, duration: 0.3, options: .transitionCrossDissolve) {
                self.checkingLabel.text = step
            }
            UIView.transition(with: self.estimateLabel, duration: 0.3, options: .transitionCrossDissolve) {
                if remainingSeconds <= 1 {
                    self.estimateLabel.text = "Almost done..."
                } else {
                    self.estimateLabel.text = "This usually takes about \(remainingSeconds) seconds"
                }
            }
        }

        viewModel.onFinish = { [weak self] in
            guard let self = self else { return }
            self.updateProgressBar(finishedCount: self.photos.count)
            self.onFinish?()
        }
    }

    private func updateReadingText(currentIndex: Int, total: Int) {
        if total == 0 {
            readingLabel.text = "Reading photos..."
        } else {
            let displayNum = min(currentIndex + 1, total)
            readingLabel.text = "Reading photo \(displayNum) of \(total)"
        }
    }

    private func updateProgressBar(finishedCount: Int) {
        for (index, segment) in progressSegments.enumerated() {
            let isFilled = index < finishedCount
            UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut]) {
                segment.backgroundColor = isFilled
                    ? UIColor(GoPhotoDesign.primary)
                    : UIColor(GoPhotoDesign.primarySubtle)
            }
        }
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        viewModel.cancel()
        if let onCancel = onCancel {
            onCancel()
        } else {
            dismiss(animated: true)
        }
    }
}
