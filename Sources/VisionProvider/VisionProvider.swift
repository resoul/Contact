import Foundation
@_exported import Filmix
@_exported import Kinobase
@_exported import Seasonvar
@_exported import Flux

/// Enumeration of available content providers
public enum ProviderType: String, CaseIterable, Identifiable, Sendable, Codable, Equatable {
    case filmix = "Filmix"
    case kinobase = "Kinobase"
    case seasonvar = "Seasonvar"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .filmix: return "Filmix"
        case .kinobase: return "Kinobase"
        case .seasonvar: return "Seasonvar"
        }
    }
    
    public var iconName: String {
        switch self {
        case .filmix: return "film"
        case .kinobase: return "play.rectangle"
        case .seasonvar: return "tv"
        }
    }
    
    public var supportsMovies: Bool {
        switch self {
        case .filmix, .kinobase: return true
        case .seasonvar: return false
        }
    }
    
    public var supportsSeries: Bool {
        return true
    }
}
