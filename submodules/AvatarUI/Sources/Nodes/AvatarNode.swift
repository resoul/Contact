import UIKit
import AsyncDisplayKit

/// A single avatar surface. UIKit owners explicitly supply visibility; Texture owners also get hierarchy hooks.
public final class AvatarNode: ASDisplayNode, AvatarPlaybackParticipant {
    public var onStateUpdated: ((AvatarDisplayState) -> Void)?
    public var state: AvatarDisplayState { displayState }
    public var image: UIImage? { imageNode.image }
    public var avatarCornerRadius: CGFloat? { didSet { setNeedsLayout() } }
    private let placeholder = AvatarPlaceholderNode()
    private let imageNode = ASImageNode()
    private var videoNode: AvatarVideoNode?
    private var descriptor: AvatarDescriptor?
    private var presentation: AvatarPresentation = .thumbnail
    private var ownerVisible = false
    private var playbackAllowed = false
    private var playbackEnabled = true
    private var playbackResourcesReleased = true
    private var videoFailed = false
    private var displayState = AvatarDisplayState.initials
    private var generation = UUID()
    private var imageTask: Task<Void, Never>?
    private var requestedPixels = 0
    private var registered = false

    public override init() {
        super.init()
        addSubnode(placeholder)
        addSubnode(imageNode)
        imageNode.contentMode = .scaleAspectFill
        imageNode.isUserInteractionEnabled = false
        imageNode.clipsToBounds = true
        imageNode.isHidden = true
    }
    public override func didLoad() { super.didLoad(); view.clipsToBounds = true }

    public func apply(_ descriptor: AvatarDescriptor, presentation: AvatarPresentation = .thumbnail) {
        let same = self.descriptor?.id == descriptor.id && self.descriptor?.version == descriptor.version
            && self.descriptor?.image == descriptor.image && self.descriptor?.video == descriptor.video
            && self.descriptor?.thumbnailVideo == descriptor.thumbnailVideo
            && self.presentation == presentation
        self.descriptor = descriptor
        self.presentation = presentation
        placeholder.apply(descriptor)
        if !same {
            generation = UUID()
            imageTask?.cancel()
            imageTask = nil
            requestedPixels = 0
            imageNode.image = nil
            imageNode.isHidden = true
            videoNode?.reset()
            videoNode?.removeFromSupernode()
            videoNode = nil
            playbackAllowed = false
            playbackResourcesReleased = true
            videoFailed = false
            setState(.initials)
        }
        if !registered { registered = true; AvatarPlaybackCoordinator.shared.register(self) }
        AvatarPlaybackCoordinator.shared.update()
        setNeedsLayout()
    }

    public func setVisible(_ ownerVisible: Bool) {
        guard self.ownerVisible != ownerVisible else { return }
        self.ownerVisible = ownerVisible
        if !ownerVisible {
            if imageTask != nil || imageNode.image == nil { requestedPixels = 0 }
            imageTask?.cancel()
            imageTask = nil
        }
        else {
            if videoFailed { videoNode?.reset(); videoFailed = false }
            requestImage()
        }
        AvatarPlaybackCoordinator.shared.update()
        if !ownerVisible { releasePlaybackResources() }
    }
    /// Scrolling suspends playback while retaining a ready player. Leaving the
    /// viewport or covering the owning screen releases its decoder and buffers.
    public func setPlaybackEnabled(_ enabled: Bool, releaseResources: Bool = false) {
        if playbackEnabled != enabled {
            playbackEnabled = enabled
            AvatarPlaybackCoordinator.shared.update()
        }
        if !enabled && releaseResources { releasePlaybackResources() }
    }
    private func releasePlaybackResources() {
        guard !playbackResourcesReleased else { return }
        videoNode?.reset()
        playbackResourcesReleased = true
    }
    public override func didEnterHierarchy() { super.didEnterHierarchy(); setVisible(true) }
    public override func didExitHierarchy() { super.didExitHierarchy(); setVisible(false) }

    public override func layout() {
        super.layout()
        placeholder.frame = bounds
        imageNode.frame = bounds
        videoNode?.frame = bounds
        cornerRadius = avatarCornerRadius ?? min(bounds.width, bounds.height) / 2
        requestImage()
    }

    private func requestImage() {
        guard ownerVisible, let resource = descriptor?.image, bounds.width > 0 else { return }
        let target = Int((max(bounds.width, bounds.height) * view.traitCollection.displayScale).rounded(.up))
        let pixels = [64, 128, 256, 512, 1024, 2048].first(where: { $0 >= target }) ?? 2048
        guard pixels > requestedPixels else { return }
        requestedPixels = pixels
        imageTask?.cancel()
        let token = generation
        imageTask = Task { @MainActor [weak self] in
            do {
                let image = try await AvatarResourceLoader.shared.image(for: resource, pixelSize: pixels)
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                self.imageNode.image = image
                self.imageNode.isHidden = false
                self.imageTask = nil
                if !self.playbackAllowed || self.videoNode?.isHidden != false { self.setState(.photo) }
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.imageTask = nil
                if self.imageNode.image == nil { self.setState(.unavailable) }
            }
        }
    }

    private var playbackVideo: AvatarVideo? {
        presentation == .chatList ? descriptor?.thumbnailVideo : descriptor?.video
    }
    var wantsAvatarPlayback: Bool { ownerVisible && playbackEnabled && presentation.priority > 0 && playbackVideo != nil && !videoFailed }
    var avatarPlaybackPriority: Int { presentation.priority }
    func setAvatarPlaybackAllowed(_ allowed: Bool) {
        guard playbackAllowed != allowed else { return }
        playbackAllowed = allowed
        if allowed, let video = playbackVideo {
            let node = videoNode ?? AvatarVideoNode()
            if videoNode == nil {
                videoNode = node
                node.isHidden = true
                node.onReady = { [weak self, weak node] ready in
                    guard let self, let node, self.videoNode === node else { return }
                    node.isHidden = !ready || !self.playbackAllowed
                    if ready && self.playbackAllowed { self.setState(.video) }
                    else { self.setState(self.imageNode.image == nil ? .initials : .photo) }
                }
                node.onFailure = { [weak self] in
                    guard let self else { return }
                    self.videoFailed = true
                    self.setState(self.imageNode.image == nil ? .unavailable : .photo)
                    AvatarPlaybackCoordinator.shared.update()
                }
                addSubnode(node)
                node.frame = bounds
            }
            node.setSource(video)
            playbackResourcesReleased = false
            node.setAllowed(true)
        } else {
            videoNode?.setAllowed(false)
            videoNode?.isHidden = true
            setState(imageNode.image == nil ? .initials : .photo)
        }
    }

    private func setState(_ state: AvatarDisplayState) {
        guard displayState != state else { return }
        displayState = state
        onStateUpdated?(state)
    }

    public func prepareForReuse() {
        generation = UUID()
        imageTask?.cancel()
        imageTask = nil
        ownerVisible = false
        descriptor = nil
        videoNode?.reset()
        videoNode?.removeFromSupernode()
        videoNode = nil
        imageNode.image = nil
        imageNode.isHidden = true
        requestedPixels = 0
        AvatarPlaybackCoordinator.shared.unregister(self)
        registered = false
        playbackAllowed = false
        playbackResourcesReleased = true
        videoFailed = false
        setState(.initials)
    }
    deinit { imageTask?.cancel() }
}
