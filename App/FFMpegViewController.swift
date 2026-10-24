import UIKit
import AVFoundation
import UniformTypeIdentifiers
import FFMpegBinding

final class FFMpegViewController: UIViewController, UIDocumentPickerDelegate {
    private let work = DispatchQueue(label: "Contact.FFmpeg", qos: .userInitiated)
    private let preview = UIImageView()
    private let details = UILabel()
    private let status = UILabel()
    private let clock = UILabel()
    private let timeline = UISlider()
    private let play = UIButton(type: .system)
    private let remux = UIButton(type: .system)
    private let choose = UIButton(type: .system)
    private let sample = UIButton(type: .system)
    private var decoded: FFMpegDecodedVideo?
    private var source: URL?
    private var audio: AVAudioPlayer?
    private var timer: Timer?
    private var position: Double = 0
    private var startedAt = 0.0
    private var shownFrame = -1
    private var busy = false
    private var ownedSource: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let title = UILabel()
        title.text = "FFmpeg \(FFMpegGlobals.version())"
        title.font = .preferredFont(forTextStyle: .title1)
        title.adjustsFontForContentSizeCategory = true
        preview.backgroundColor = .black
        preview.contentMode = .scaleAspectFit
        preview.layer.cornerRadius = 12
        preview.clipsToBounds = true
        preview.accessibilityIdentifier = "ffmpeg.preview"
        preview.isAccessibilityElement = true
        preview.accessibilityLabel = "Frame decoded by FFmpeg"
        for label in [details, status] {
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .subheadline)
        }
        details.accessibilityIdentifier = "ffmpeg.details"
        status.accessibilityIdentifier = "ffmpeg.status"
        status.textColor = .secondaryLabel
        clock.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        clock.accessibilityIdentifier = "ffmpeg.time"
        timeline.accessibilityIdentifier = "ffmpeg.timeline"
        timeline.addTarget(self, action: #selector(seek), for: .valueChanged)
        play.setTitle("Play", for: .normal)
        play.accessibilityIdentifier = "ffmpeg.play"
        play.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
        remux.setTitle("Verify remux → MP4", for: .normal)
        remux.accessibilityIdentifier = "ffmpeg.remux"
        remux.addTarget(self, action: #selector(remuxVideo), for: .touchUpInside)
        choose.setTitle("Open video…", for: .normal)
        choose.addTarget(self, action: #selector(chooseVideo), for: .touchUpInside)
        sample.setTitle("Sample video", for: .normal)
        sample.addTarget(self, action: #selector(loadSample), for: .touchUpInside)
        let files = UIStackView(arrangedSubviews: [sample, choose])
        files.distribution = .fillEqually
        let stack = UIStackView(arrangedSubviews: [title, preview, details, timeline, clock, play, remux, files, status])
        stack.axis = .vertical
        stack.spacing = 12
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
            preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: 9.0 / 16.0)
        ])
        loadSample()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pause()
    }

    deinit {
        timer?.invalidate()
        if let ownedSource { try? FileManager.default.removeItem(at: ownedSource) }
    }

    @objc private func loadSample() {
        guard !busy else { return }
        guard let bundleURL = Bundle.main.url(forResource: "FFmpegSamples", withExtension: "bundle"),
              let bundle = Bundle(url: bundleURL),
              let url = bundle.url(forResource: "demo", withExtension: "mp4") else {
            status.text = "Sample video not found."
            return
        }
        decode(url)
    }

    private func decode(_ url: URL) {
        pause()
        decoded = nil
        audio = nil
        source = url
        shownFrame = -1
        preview.image = nil
        details.text = url.lastPathComponent
        setBusy(true)
        status.text = "FFmpeg is decoding video and audio…"
        let began = ProcessInfo.processInfo.systemUptime
        work.async { [weak self] in
            do {
                let value = try FFMpegMedia.decodeVideo(url.path, maxDuration: 8)
                let player = value.pcmData.isEmpty ? nil : try AVAudioPlayer(data: Self.wav(value.pcmData))
                player?.prepareToPlay()
                let elapsed = ProcessInfo.processInfo.systemUptime - began
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.decoded = value
                    self.audio = player
                    self.position = 0
                    self.timeline.maximumValue = Float(value.previewDuration)
                    self.details.text = "\(url.lastPathComponent)\n\(value.videoCodec) + \(value.audioCodec) · \(value.width)×\(value.height) · \(String(format: "%.1f", value.framesPerSecond)) fps\n\(value.videoFrameCount) frames · \(String(format: "%.2f", value.sourceDuration)) s · 48 kHz stereo PCM"
                    self.status.text = "Decoded in \(String(format: "%.2f", elapsed)) s. Previewing the first \(String(format: "%.1f", value.previewDuration)) s, up to 320 px / 30 fps."
                    self.setBusy(false)
                    self.render()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.status.text = error.localizedDescription
                    self?.setBusy(false)
                }
            }
        }
    }

    private func setBusy(_ value: Bool) {
        busy = value
        play.isEnabled = !value && decoded != nil
        timeline.isEnabled = !value && decoded != nil
        remux.isEnabled = !value && decoded != nil
        choose.isEnabled = !value
        sample.isEnabled = !value
    }

    @objc private func togglePlayback() {
        if timer != nil { pause(); return }
        guard let decoded else { return }
        if position >= decoded.previewDuration - 0.01 { position = 0 }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            status.text = "Audio session: \(error.localizedDescription)"
            return
        }
        audio?.currentTime = position
        if let audio, !audio.play() { status.text = "Could not start PCM audio."; return }
        startedAt = ProcessInfo.processInfo.systemUptime - position
        play.setTitle("Pause", for: .normal)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func pause() {
        timer?.invalidate()
        timer = nil
        audio?.pause()
        play.setTitle("Play", for: .normal)
    }

    private func tick() {
        guard let decoded else { return }
        position = min(decoded.previewDuration, ProcessInfo.processInfo.systemUptime - startedAt)
        // Synchronize frames to the decoded PCM while it is playing.
        if let audio, audio.isPlaying { position = min(decoded.previewDuration, audio.currentTime) }
        render()
        if position >= decoded.previewDuration - 0.01 { pause() }
    }

    @objc private func seek() {
        position = Double(timeline.value)
        audio?.currentTime = position
        startedAt = ProcessInfo.processInfo.systemUptime - position
        render()
    }

    private func render() {
        guard let decoded else { return }
        timeline.value = Float(position)
        clock.text = String(format: "%.2f / %.2f s", position, decoded.previewDuration)
        let index = decoded.frames.lastIndex(where: { $0.time <= position }) ?? 0
        if index != shownFrame {
            preview.image = UIImage(data: decoded.frames[index].pngData)
            shownFrame = index
        }
    }

    @objc private func remuxVideo() {
        guard !busy, let source, let original = decoded else { return }
        pause()
        setBusy(true)
        status.text = "Remuxing without re-encoding and verifying with FFmpeg…"
        work.async { [weak self] in
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            defer { try? FileManager.default.removeItem(at: output) }
            do {
                guard FFMpegRemuxer.remux(source.path, to: output.path) else {
                    throw NSError(domain: "Contact", code: 1, userInfo: [NSLocalizedDescriptionKey: "The MP4 container does not support this file's streams, or remuxing failed."])
                }
                let checked = try FFMpegMedia.decodeVideo(output.path, maxDuration: 8)
                guard checked.videoFrameCount == original.videoFrameCount,
                      checked.width == original.width, checked.height == original.height,
                      abs(checked.previewDuration - original.previewDuration) < 0.1,
                      checked.pcmData == original.pcmData,
                      checked.frames.map(\.pngData) == original.frames.map(\.pngData) else {
                    throw NSError(domain: "Contact", code: 2, userInfo: [NSLocalizedDescriptionKey: "Decoded data differs after remuxing."])
                }
                let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                DispatchQueue.main.async {
                    self?.status.text = "MP4 remux verified: \(checked.videoFrameCount) frames; PCM audio and images match · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))."
                    self?.setBusy(false)
                }
            } catch {
                DispatchQueue.main.async { self?.status.text = error.localizedDescription; self?.setBusy(false) }
            }
        }
    }

    @objc private func chooseVideo() {
        let types: [UTType] = [.movie, UTType(filenameExtension: "mkv"), UTType(filenameExtension: "webm")].compactMap { $0 }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !busy, let url = urls.first else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
            try FileManager.default.copyItem(at: url, to: copy)
            if let ownedSource { try? FileManager.default.removeItem(at: ownedSource) }
            ownedSource = copy
            decode(copy)
        } catch { status.text = error.localizedDescription }
    }

    private static func wav(_ pcm: Data) -> Data {
        var result = Data()
        func text(_ value: String) { result.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { result.append(contentsOf: $0) }
        }
        text("RIFF"); number(UInt32(36 + pcm.count)); text("WAVEfmt ")
        number(UInt32(16)); number(UInt16(1)); number(UInt16(2))
        number(UInt32(48000)); number(UInt32(192000)); number(UInt16(4)); number(UInt16(16))
        text("data"); number(UInt32(pcm.count)); result.append(pcm)
        return result
    }
}
