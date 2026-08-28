import Foundation
import Filmix
import Kinobase
import Seasonvar
import Flux

/// Protocol for managing content providers and active state
public protocol VisionProviderManagerProtocol: AnyObject, Sendable {
    var filmix: FilmixService { get }
    var kinobase: KinobaseService { get }
    var seasonvar: SeasonvarService { get }
    
    /// Reactive state of the current active provider (with automatic deduplication)
    var activeProvider: CurrentValueDistinct<ProviderType> { get }
    
    func setProvider(_ provider: ProviderType) async
    func currentProvider() async -> ProviderType
}

/// DI-friendly manager for coordinating content provider services and active selection
public final class VisionProviderManager: VisionProviderManagerProtocol, @unchecked Sendable {
    public let filmix: FilmixService
    public let kinobase: KinobaseService
    public let seasonvar: SeasonvarService
    public let activeProvider: CurrentValueDistinct<ProviderType>
    
    public init(
        filmix: FilmixService = FilmixServiceImpl(),
        kinobase: KinobaseService = KinobaseServiceImpl(),
        seasonvar: SeasonvarService = SeasonvarServiceImpl(),
        initialProvider: ProviderType = .filmix
    ) {
        self.filmix = filmix
        self.kinobase = kinobase
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
