import UIKit
import AVFoundation
import AsyncDisplayKit

private final class AvatarPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Mutable node state is confined to the main thread; KVO callbacks dispatch back to it.
public final class AvatarVideoNode: ASDisplayNode, @unchecked Sendable {
    var onReady: ((Bool) -> Void)?
    var onFailure: (() -> Void)?
    private let surface = AvatarPlayerView()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var readyObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var loading: Task<Void, Never>?
    private var source: AvatarVideo?
    private var generation = UUID()
    private var allowed = false
    private var failed = false

    public override init() {
        super.init()
        isUserInteractionEnabled = false
    }
    public override func didLoad() {
        super.didLoad()
        view.addSubview(surface)
        surface.backgroundColor = .clear
        surface.isUserInteractionEnabled = false
        surface.playerLayer.videoGravity = .resizeAspectFill
        readyObservation = surface.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            DispatchQueue.main.async { [weak self] in self?.onReady?(layer.isReadyForDisplay) }
        }
    }
    public override func layout() { super.layout(); surface.frame = bounds }

    func setSource(_ source: AvatarVideo) {
        guard self.source != source else { return }
        reset()
        self.source = source
    }

    func setAllowed(_ allowed: Bool) {
        self.allowed = allowed
        if allowed {
            if player != nil {
                onReady?(surface.playerLayer.isReadyForDisplay)
                player?.play()
            }
            else if loading == nil, !failed { prepare() }
        } else {
            player?.pause()
            // A short scrolling pause can reuse an already prepared player.
            // AvatarNode explicitly resets it when its surface leaves the viewport.
            if loading != nil { releasePlayer() }
        }
    }

    private func prepare() {
        guard let source else { return }
        _ = view
        let token = generation
        loading = Task { @MainActor [weak self] in
            do {
                let url = try await AvatarResourceLoader.shared.fileURL(for: source.resource)
                let asset = AVURLAsset(url: url)
                let duration = try await asset.load(.duration).seconds
                let tracks = try await asset.loadTracks(withMediaType: .video)
                try Task.checkCancellation()
                guard duration.isFinite, duration > 0, duration <= AvatarVideo.maximumDuration + 0.05,
                      let track = tracks.first else {
                    throw URLError(.cannotDecodeContentData)
                }
                let transform = try await track.load(.preferredTransform)
                // Avatars never need audio tracks or an application audio-session change.
                let composition = AVMutableComposition()
                guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw URLError(.cannotDecodeContentData)
                }
                try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600)),
                                               of: track, at: .zero)
                videoTrack.preferredTransform = transform
                try Task.checkCancellation()
                guard let self, self.generation == token, self.allowed else { return }
                let item = AVPlayerItem(asset: composition)
                let player = AVQueuePlayer()
                player.isMuted = true
                player.volume = 0
                player.preventsDisplaySleepDuringVideoPlayback = false
                self.player = player
                self.looper = AVPlayerLooper(player: player, templateItem: item)
                self.itemObservation = player.observe(\.status, options: [.new]) { [weak self] player, _ in
                    if player.status == .failed {
                        DispatchQueue.main.async { [weak self] in self?.fail() }
                    }
                }
                self.surface.playerLayer.player = player
                let start = min(source.startTimestamp, max(0, duration - 0.05))
                if start > 0 {
                    await player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }
                guard self.generation == token, self.allowed else { return }
                self.loading = nil
                player.play()
            } catch {
                guard !Task.isCancelled else { return }
                if let self, self.generation == token { self.fail() }
            }
        }
    }

    private func fail() {
        failed = true
        releasePlayer()
        onFailure?()
    }
    private func releasePlayer() {
        generation = UUID()
        loading?.cancel()
        loading = nil
        player?.pause()
        onReady?(false)
        itemObservation = nil
        looper?.disableLooping()
        looper = nil
        surface.playerLayer.player = nil
        player?.removeAllItems()
        player = nil
    }
    func reset() {
        generation = UUID()
        releasePlayer()
        source = nil
        failed = false
    }
    deinit { loading?.cancel(); player?.pause() }
}
