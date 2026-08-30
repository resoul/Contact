import Foundation
import Filmix
import Seasonvar
import Flux

/// Protocol for managing content providers and active state
public protocol VisionProviderManagerProtocol: AnyObject, Sendable {
    var filmix: FilmixService { get }
    var seasonvar: SeasonvarService { get }
    
    /// Reactive state of the current active provider (with automatic deduplication)
    var activeProvider: CurrentValueDistinct<ProviderType> { get }
    
    func setProvider(_ provider: ProviderType) async
    func currentProvider() async -> ProviderType
}

/// DI-friendly manager for coordinating content provider services and active selection
public final class VisionProviderManager: VisionProviderManagerProtocol, @unchecked Sendable {
    public let filmix: FilmixService
    public let seasonvar: SeasonvarService
    public let activeProvider: CurrentValueDistinct<ProviderType>
    
    public init(
        filmix: FilmixService = FilmixServiceImpl(),
        seasonvar: SeasonvarService = SeasonvarServiceImpl(),
        initialProvider: ProviderType = .filmix
    ) {
        self.filmix = filmix
        self.seasonvar = seasonvar
        self.activeProvider = CurrentValueDistinct(initialProvider)
    }
    
    public func setProvider(_ provider: ProviderType) async {
        await activeProvider.set(provider)
    }
    
    public func currentProvider() async -> ProviderType {
        await activeProvider.value
    }
}
