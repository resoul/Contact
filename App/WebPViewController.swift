import UIKit
import UniformTypeIdentifiers
import WebPBinding

final class WebPViewController: UIViewController, UIDocumentPickerDelegate {
    private struct Photo {
        let name: String
        let data: Data
        let image: UIImage
    }

    private struct Conversion {
        let photo: Photo
        let data: Data
        let decoded: UIImage
        let milliseconds: Double
    }

    private let mode = UISegmentedControl(items: ["Lossy", "Lossless"])
    private let quality = UISlider()
    private let qualityLabel = UILabel()
    private let cards = UIStackView()
    private let activity = UIActivityIndicatorView(style: .medium)
    private let conversionQueue = DispatchQueue(label: "org.airlance.Contact.webp", qos: .userInitiated)
    private var photos: [Photo] = []
    private var generation = UUID()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        let title = label("WebP", style: .largeTitle)
        title.font = .systemFont(ofSize: 32, weight: .bold)
        let subtitle = label("JPEG and PNG: original side-by-side with result", style: .subheadline)
        subtitle.textColor = .secondaryLabel
        mode.selectedSegmentIndex = 0
        mode.addTarget(self, action: #selector(convertPhotos), for: .valueChanged)
        quality.minimumValue = 0
        quality.maximumValue = 100
        quality.value = 90
        quality.isContinuous = false
        quality.accessibilityLabel = "Quality WebP"
        quality.addTarget(self, action: #selector(convertPhotos), for: .valueChanged)
        qualityLabel.font = .preferredFont(forTextStyle: .subheadline)

        let picker = UIButton(type: .system)
        picker.setTitle("Open JPEG / PNG", for: .normal)
        picker.addTarget(self, action: #selector(openPhoto), for: .touchUpInside)
        let actions = UIStackView(arrangedSubviews: [picker, UIView(), activity])
        actions.alignment = .center

        cards.axis = .vertical
        cards.spacing = 16
        let note = label("Lossless preserves pixels after converting to sRGB. Quality 100 in "Lossy" mode does not mean lossless. WebP size depends on the shot", style: .footnote)
        note.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [title, subtitle, mode, qualityLabel, quality, actions, cards, note])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
        ])

        do {
            guard let url = Bundle.main.url(forResource: "WebPSamples", withExtension: "bundle"),
                  let bundle = Bundle(url: url) else {
                throw CocoaError(.fileNoSuchFile)
            }
            for (name, ext, title) in [("boats", "jpg", "JPEG · Boats"), ("rivers", "png.bin", "PNG · Rivers")] {
                guard let file = bundle.url(forResource: name, withExtension: ext) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let data = try Data(contentsOf: file)
                guard let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
                photos.append(Photo(name: title, data: data, image: image))
            }
            convertPhotos()
        } catch {
            cards.addArrangedSubview(label("Failed to open examples: \(error.localizedDescription)", style: .body))
        }
    }

    @objc private func convertPhotos() {
        let lossless = mode.selectedSegmentIndex == 1
        let value = CGFloat(quality.value.rounded())
        qualityLabel.text = lossless ? "Lossless · transparency is preserved" : "Quality: \(Int(value)) / 100"
        quality.isEnabled = !lossless
        let token = UUID()
        generation = token
        activity.startAnimating()
        let inputs = photos
        conversionQueue.async { [weak self] in
            let results: [Result<Conversion, Error>] = inputs.map { photo in
                Result {
                    let start = CFAbsoluteTimeGetCurrent()
                    let data = try lossless
                        ? WebP.convert(toLosslessWebP: photo.image)
                        : WebP.convert(toWebP: photo.image, quality: value)
                    guard let decoded = WebP.convert(fromWebP: data) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    return Conversion(photo: photo, data: data, decoded: decoded,
                                      milliseconds: (CFAbsoluteTimeGetCurrent() - start) * 1000)
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == token else { return }
                activity.stopAnimating()
                cards.arrangedSubviews.forEach { $0.removeFromSuperview() }
                for result in results {
                    switch result {
                    case let .success(conversion): cards.addArrangedSubview(card(conversion))
                    case let .failure(error): cards.addArrangedSubview(label(error.localizedDescription, style: .body))
                    }
                }
            }
        }
    }

    private func card(_ conversion: Conversion) -> UIView {
        let photo = conversion.photo
        let heading = label(photo.name, style: .headline)
        let images = UIStackView(arrangedSubviews: [photoView(photo.image), photoView(conversion.decoded)])
        images.axis = .horizontal
        images.spacing = 12
        images.distribution = .fillEqually
        let sizes = UIStackView(arrangedSubviews: [
            label("Original · \(bytes(photo.data.count))", style: .caption1),
            label("WebP · \(bytes(conversion.data.count))", style: .caption1),
        ])
        sizes.distribution = .fillEqually
        sizes.spacing = 12
        let difference = (1 - Double(conversion.data.count) / Double(photo.data.count)) * 100
        let change = difference >= 0
            ? String(format: "smaller by %.1f%%", difference)
            : String(format: "larger by %.1f%%", -difference)
        let details = label(String(format: "%d × %d · %@ · %.0f мс", photo.image.cgImage?.width ?? 0,
                                   photo.image.cgImage?.height ?? 0, change, conversion.milliseconds), style: .caption1)
        details.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [heading, images, sizes, details])
        stack.axis = .vertical
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        stack.backgroundColor = .secondarySystemGroupedBackground
        stack.layer.cornerRadius = 16
        return stack
    }

    private func photoView(_ image: UIImage) -> UIView {
        let background = CheckerboardView()
        background.layer.cornerRadius = 8
        background.clipsToBounds = true
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(imageView)
        NSLayoutConstraint.activate([
            background.heightAnchor.constraint(equalToConstant: 155),
            imageView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: background.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        return background
    }

    private func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    private func label(_ text: String, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }

    @objc private func openPhoto() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.jpeg, .png], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
            photos = [Photo(name: url.lastPathComponent, data: data, image: image)]
            convertPhotos()
        } catch {
            let alert = UIAlertController(title: "Failed to open phot", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}

private final class CheckerboardView: UIView {
    override func draw(_ rect: CGRect) {
        let tile: CGFloat = 10
        for row in 0..<Int(ceil(bounds.height / tile)) {
            for column in 0..<Int(ceil(bounds.width / tile)) {
                UIColor(white: (row + column) % 2 == 0 ? 0.94 : 0.86, alpha: 1).setFill()
                UIRectFill(CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile))
            }
        }
    }
}
