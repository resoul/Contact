//
//  SocialRoomSupport.swift
//  controller
//
//  Shared pieces for the voice room, chat, bubble cluster and ambient feed demos:
//  - VoiceLevelMeter: the microphone's loudness, 0…1 (AVAudioRecorder metering, nothing is saved).
//  - SpeechSimulator: a believable talking envelope (phrases and pauses) for people who are not you.
//  - LiquidSelector: tabs or a segmented control whose selection is a drop of liquid that stretches
//    from the old item to the new one and snaps.
//

import UIKit
import AVFoundation

enum RoomPalette {
    static let background = UIColor(red: 0.04, green: 0.06, blue: 0.07, alpha: 1)
    static let panel = UIColor(red: 0.09, green: 0.12, blue: 0.13, alpha: 1)
    static let chip = UIColor(red: 0.13, green: 0.17, blue: 0.18, alpha: 1)
    static let orange = UIColor(red: 1.0, green: 0.36, blue: 0.13, alpha: 1)
    static let pink = UIColor(red: 1.0, green: 0.42, blue: 0.5, alpha: 1)
    static let cyan = UIColor(red: 0.4, green: 0.86, blue: 0.98, alpha: 1)
    static let secondary = UIColor(white: 1, alpha: 0.55)
}

/// The microphone's level. Ask with `start(_:)`; it reports `false` if access was denied.
final class VoiceLevelMeter {
    private var recorder: AVAudioRecorder?
    private var smoothed: CGFloat = 0

    var isRunning: Bool { recorder?.isRecording ?? false }

    func start(_ completion: @escaping (Bool) -> Void) {
        let permissionResult: (Bool) -> Void = { granted in
            DispatchQueue.main.async {
                guard granted else { return completion(false) }
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
                    try session.setActive(true)
                    // Metering only: the "file" is thrown away.
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("meter.caf")
                    let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatAppleIMA4,
                                                                            AVSampleRateKey: 22_050, AVNumberOfChannelsKey: 1])
                    recorder.isMeteringEnabled = true
                    recorder.record()
                    self.recorder = recorder
                    completion(true)
                } catch {
                    completion(false)
                }
            }
        }
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: permissionResult)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(permissionResult)
        }
    }

    func stop() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        smoothed = 0
    }

    /// 0 (silence) … 1 (shouting), smoothed: fast up, slower down, like a VU meter.
    var level: CGFloat {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        let db = CGFloat(recorder.averagePower(forChannel: 0))
        let raw = max(0, min(1, (db + 50) / 42))
        smoothed = raw > smoothed ? smoothed + (raw - smoothed) * 0.6 : smoothed + (raw - smoothed) * 0.15
        return smoothed
    }
}

/// Someone talking: phrases of syllables with pauses in between.
struct SpeechSimulator {
    private var phraseLeft: Double
    private var pauseLeft: Double = 0
    private var syllable: Double = 0
    private var target: CGFloat = 0
    private(set) var level: CGFloat = 0
    private let energy: CGFloat

    init(energy: CGFloat = 1, startsTalking: Bool = true) {
        self.energy = energy
        phraseLeft = startsTalking ? Double.random(in: 1.5...4) : 0
        pauseLeft = startsTalking ? 0 : Double.random(in: 1...4)
    }

    mutating func step(_ dt: Double) {
        if phraseLeft > 0 {
            phraseLeft -= dt
            syllable -= dt
            if syllable <= 0 {
                syllable = Double.random(in: 0.09...0.22)
                target = CGFloat.random(in: 0.25...1) * energy
            }
            if phraseLeft <= 0 {
                pauseLeft = Double.random(in: 1.2...4.5)
            }
        } else {
            target = 0
            pauseLeft -= dt
            if pauseLeft <= 0 {
                phraseLeft = Double.random(in: 1.5...5)
            }
        }
        level += (target - level) * CGFloat(min(1, dt * (target > level ? 18 : 7)))
    }
}

/// Tabs or a segmented control whose selection is a drop of liquid. Items are SF Symbols (tabs) or
/// titles (segments). The drop's front races to the new item while its back clings to the old one.
final class LiquidSelector: UIControl {
    enum Style { case tabs, segments }

    private(set) var selectedIndex = 0
    private var interactivePosition: CGFloat?
    private let style: Style
    private let canvas = LiquidCanvasView()
    private var items: [UIView] = []
    private var head = Spring1D(0, stiffness: 22, dampingRatio: 0.6)
    private var tail = Spring1D(0, stiffness: 9, dampingRatio: 0.85)
    private let selectedTint: UIColor
    private let normalTint: UIColor

    init(
        symbols: [String]? = nil,
        titles: [String]? = nil,
        style: Style,
        liquid: UIColor,
        selectedTint: UIColor = .white,
        normalTint: UIColor = UIColor(white: 1, alpha: 0.6)
    ) {
        self.style = style
        self.selectedTint = selectedTint
        self.normalTint = normalTint
        super.init(frame: .zero)
        canvas.liquidColor = liquid
        canvas.gloss = 0.45
        canvas.rimWidth = 6
        canvas.isUserInteractionEnabled = false
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(canvas)
        if let symbols {
            items = symbols.map { symbol in
                let icon = UIImageView(image: UIImage(systemName: symbol))
                icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
                icon.contentMode = .center
                return icon
            }
        } else if let titles {
            items = titles.map { title in
                let label = UILabel()
                label.text = title
                label.font = .systemFont(ofSize: 15, weight: .semibold)
                label.textAlignment = .center
                return label
            }
        }
        items.forEach {
            $0.isUserInteractionEnabled = false
            addSubview($0)
        }
        tint()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var slot: CGFloat { bounds.width / CGFloat(max(items.count, 1)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds.insetBy(dx: -12, dy: -12)
        for (index, item) in items.enumerated() {
            item.frame = CGRect(x: slot * CGFloat(index), y: 0, width: slot, height: bounds.height)
        }
        canvas.isPaused = false
    }

    private func tint() {
        for (index, item) in items.enumerated() {
            let color = index == selectedIndex ? selectedTint : normalTint
            (item as? UIImageView)?.tintColor = color
            (item as? UILabel)?.textColor = color
        }
    }

    func select(_ index: Int, animated: Bool = true) {
        interactivePosition = nil
        canvas.isPaused = false
        guard index != selectedIndex, items.indices.contains(index) else { return }
        selectedIndex = index
        if !animated {
            head.value = CGFloat(index)
            tail.value = CGFloat(index)
        }
        UIView.transition(with: self, duration: 0.2, options: .transitionCrossDissolve) { self.tint() }
        canvas.isPaused = false
    }

    func setInteractivePosition(_ position: CGFloat) {
        interactivePosition = min(max(0, position), CGFloat(max(0, items.count - 1)))
        canvas.isPaused = false
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        guard let touch, bounds.contains(touch.location(in: self)) else { return }
        let index = Int(touch.location(in: self).x / slot)
        guard index != selectedIndex else { return }
        select(index)
        UISelectionFeedbackGenerator().selectionChanged()
        sendActions(for: .valueChanged)
    }

    private func step(_ dt: CFTimeInterval) {
        let target = interactivePosition ?? CGFloat(selectedIndex)
        head.step(toward: target, deltaTime: dt)
        tail.step(toward: target, deltaTime: dt)
        let inset: CGFloat = style == .tabs ? 4 : 3
        let height = bounds.height - inset * 2
        let width = style == .tabs ? height : slot - inset * 2
        func center(_ position: CGFloat) -> CGPoint {
            CGPoint(x: slot * (position + 0.5) + 12, y: bounds.midY + 12)
        }
        let a = center(head.value), b = center(tail.value)
        let stretch = abs(a.x - b.x)
        // The drop thins while it stretches between the two items.
        let squeeze = 1 - min(stretch / (slot * 2.5), 0.3)
        let half = CGSize(width: width / 2, height: height / 2 * squeeze)
        canvas.shapes = [
            IslandFluidShape(center: a, halfSize: half, cornerRadius: half.height, blend: 0),
            IslandFluidShape(center: b, halfSize: CGSize(width: half.width * 0.85, height: half.height * 0.85),
                             cornerRadius: half.height * 0.85, blend: height * 0.45),
        ]
        canvas.spikes = stretch > 2 ? [IslandFluidSpike(base: b, tip: a, baseRadius: half.height * 0.45,
                                                        tipRadius: half.height * 0.7, blend: 6)] : []
        if head.isSettled(at: target, tolerance: 0.001), tail.isSettled(at: target, tolerance: 0.001) {
            canvas.renderFrame()
            canvas.isPaused = true
        }
    }
}
