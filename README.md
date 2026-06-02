# Filmix

> ⚠️ **Demo project.** Created solely for educational purposes as an example of Clean Architecture in a multiplatform Swift Package.

---

## Overview

Filmix is a Swift Package that demonstrates a multiplatform client architecture built on Clean Architecture principles. It covers networking with Alamofire, HTML parsing with SwiftSoup, custom stream token decoding, and structured DTO modeling — all separated into focused, independently testable layers.

## Platforms

| Platform | Minimum Version |
|----------|----------------|
| iOS      | 16.0+          |
| tvOS     | 16.0+          |
| macOS    | 13.0+          |

## Installation

Add the package via Swift Package Manager in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/Filmix.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [.product(name: "Filmix", package: "Filmix")]
    )
]
```

Or add it through Xcode: **File → Add Package Dependencies** and paste the repository URL.

## Usage

### Search

```swift
let service: FilmixService = FilmixServiceImpl()
let page = try await service.search(query: "Inception")

for movie in page.movies {
    print(movie.title, movie.year, movie.rating)
}

// Load the next page if available
if let nextURL = page.nextPageURL {
    let nextPage = try await service.fetchPage(url: nextURL)
}
```

### Movie Detail

```swift
let detail = try await service.fetchDetail(path: "/films/12345-inception.html")
print(detail.title)               // "Inception"
print(detail.durationFormatted)   // "2ч 28м"
print(detail.userRating)          // "9.2"
print(detail.kinopoiskRating)     // "8.7"
```

### Translations & Streams

```swift
let translations = try await service.fetchTranslations(postId: 12345, isSeries: false)

if let best = translations.first {
    print(best.studio)            // "Дубляж"
    print(best.bestQuality)       // "1080p"
    print(best.bestURL)           // "https://..."
    print(best.sortedQualities)   // ["4K UHD", "1080p", "720p", ...]
}
```

### Series Seasons & Episodes

```swift
let translations = try await service.fetchTranslations(postId: 67890, isSeries: true)

for translation in translations {
    for season in translation.seasons {
        print(season.title)       // "Сезон 1"
        for episode in season.episodes {
            print(episode.title)  // "Серия 1"
            print(episode.streams["1080p"] ?? "—")
        }
    }
}
```

## Architecture

The package is organized into three layers following Clean Architecture:

```
Sources/Filmix/
├── Data/
│   └── FilmixService.swift        # Public protocol + implementation
├── DTO/
│   ├── FilmixMovieDTO.swift        # Listing-level movie model
│   ├── FilmixMovieDetailDTO.swift  # Full detail model
│   ├── FilmixMoviePageDTO.swift    # Paginated listing result
│   ├── FilmixMovieFrameDTO.swift   # Movie frame/screenshot
│   ├── FilmixSeasonDTO.swift       # TV season
│   ├── FilmixEpisodeDTO.swift      # TV episode with quality streams
│   ├── FilmixTranslationDTO.swift  # Dubbing/subtitle translation
│   └── Video/
│       ├── FilmixVideoDTO.swift
│       ├── FilmixVideoMessageDTO.swift
│       ├── FilmixVideoTranslateDTO.swift
│       ├── FilmixSerialDTO.swift
│       └── FilmixFolderDTO.swift
├── FilmixNetworkClient.swift       # Alamofire session wrapper
├── FilmixHTMLParser.swift          # SwiftSoup-based HTML parser
├── FilmixStreamDecoder.swift       # Token + quality map decoder
└── FilmixError.swift               # Typed error enum
```

**`FilmixService`** is the single public entry point. It delegates to:
- **`FilmixNetworkClient`** — manages the Alamofire session, cookies, and raw HTTP requests.
- **`FilmixHTMLParser`** — parses listing and detail pages into typed DTOs using SwiftSoup.
- **`FilmixStreamDecoder`** — decodes obfuscated stream tokens and maps them to quality labels like `1080p`, `720p`, etc.

## DTOs

| Type | Purpose |
|------|---------|
| `FilmixMovieDTO` | Compact movie model used in listings and search results |
| `FilmixMovieDetailDTO` | Full movie/series info including ratings, crew, frames |
| `FilmixMoviePageDTO` | Paginated listing result with optional next-page URL |
| `FilmixTranslationDTO` | Dubbing studio with quality→URL stream map or season list |
| `FilmixSeasonDTO` | Season title and its episodes |
| `FilmixEpisodeDTO` | Episode title, ID, and quality→URL stream map |
| `FilmixMovieFrameDTO` | Thumbnail and full-size screenshot URLs |

### `FilmixMovieDTO.ContentType`

```swift
enum ContentType {
    case movie
    case series(seasons: [FilmixSeasonDTO])
}
```

Seasons are populated lazily via `fetchTranslations` — the listing parser intentionally sets them to `[]`.

## Error Handling

```swift
do {
    let detail = try await service.fetchDetail(path: "/films/12345.html")
} catch FilmixError.articleNotFound {
    // HTML article element not found
} catch FilmixError.invalidURL(let url) {
    // Malformed URL
} catch FilmixError.decodingFailed {
    // JSON/response decode error
} catch {
    // Alamofire or network error
}
```

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [Alamofire](https://github.com/Alamofire/Alamofire) | 5.12.0+ | HTTP networking and session management |
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | 2.13.5+ | HTML parsing |

## Disclaimer

This project was created **for educational purposes only** as a demonstration of Clean Architecture in a Swift Package. It is not intended for production or commercial use.
