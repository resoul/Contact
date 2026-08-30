# VisionProvider

A unified content provider package for the **Vision** tvOS application.

The package integrates and coordinates multiple content providers:
- 🎬 **Filmix** (`Filmix`) — Movies, TV series, cartoons, video quality choices, and audio tracks.
- 📺 **Seasonvar** (`Seasonvar`) — TV series, autocomplete search, detailed cards, seasons, translations, and direct MP4 streams.
- 🎛️ **VisionProvider** — Unified management and state layer powered by **Flux** (`VisionProviderManager`, `VisionProviderManagerProtocol`, `ProviderType`).

---

## 📦 Installation

### Swift Package Manager

In your `Package.swift`:

```swift
dependencies: [
    .package(path: "../vision-provider") // or remote git URL
]
```

Or add the target dependency:

```swift
.target(
    name: "Vision",
    dependencies: [
        .product(name: "VisionProvider", package: "VisionProvider")
    ]
)
```

---

## 🚀 Usage with Dependency Injection (DI) and Flux

```swift
import VisionProvider
import Flux

// 1. Instantiate via constructor (e.g. inside your DI Container)
let manager: VisionProviderManagerProtocol = VisionProviderManager(
    initialProvider: .filmix
)

// 2. Reactively observe active provider changes via Flux
let bag = SubscriptionBag()

manager.activeProvider.flux
    .sinkOnMain { provider in
        print("Active provider switched to: \(provider.title)")
    }
    .store(in: bag)

// 3. Switch active provider
await manager.setProvider(.seasonvar)

// 4. Direct access to underlying provider services
let filmixResults = try await manager.filmix.search(query: "Matrix")
let seasonvarResults = try await manager.seasonvar.search(query: "Breaking Bad")
```
