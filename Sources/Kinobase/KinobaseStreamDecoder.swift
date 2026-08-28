import Foundation

public enum KinobaseStreamDecoder {
    public struct ParsedStreams: Sendable {
        public let translations: [KinobaseTranslationDTO]
        public let subtitles: [String: [String]]
    }

    /// Parses a Kinobase/PlayerJS playlist string of the format:
    /// [1080p]{Dubbing}https://cdn1/... or https://cdn2/...;{Rezka}...[720p]{Dubbing}...
    public static func parsePlaylist(from raw: String) -> ParsedStreams {
        var subtitlesMap: [String: [String]] = [:]
        var translationsQualities: [String: [String: [String]]] = [:]
        
        // Extract subtitles section if present
        var playlistPart = raw
        if let subIndex = raw.range(of: "[Форсированные")?.lowerBound ?? raw.range(of: "[Полные")?.lowerBound {
            playlistPart = String(raw[..<subIndex])
            let subPart = String(raw[subIndex...])
            subtitlesMap = parseSubtitles(from: subPart)
        }
        
        // Parse quality blocks: [1080p]... , [720p]...
        guard let qualityRegex = try? NSRegularExpression(pattern: "\\[([0-9]+p?)\\](.*?)(?=\\[[0-9]+p?\\]|$)", options: [.dotMatchesLineSeparators]),
              let translationRegex = try? NSRegularExpression(pattern: "\\{(.*?)\\}([^;\\[]+)") else {
            return ParsedStreams(translations: [], subtitles: [:])
        }
        
        let fullRange = NSRange(playlistPart.startIndex..., in: playlistPart)
        let qualityMatches = qualityRegex.matches(in: playlistPart, range: fullRange)
        
        for qMatch in qualityMatches {
            guard let qRange = Range(qMatch.range(at: 1), in: playlistPart),
                  let bodyRange = Range(qMatch.range(at: 2), in: playlistPart) else { continue }
            
            let quality = String(playlistPart[qRange])
            let body = String(playlistPart[bodyRange])
            
            let tMatches = translationRegex.matches(in: body, range: NSRange(body.startIndex..., in: body))
            for tMatch in tMatches {
                guard let tNameRange = Range(tMatch.range(at: 1), in: body),
                      let tUrlRange = Range(tMatch.range(at: 2), in: body) else { continue }
                
                let translation = String(body[tNameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let urls = String(body[tUrlRange])
                    .components(separatedBy: " or ")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.hasPrefix("http") }
                
                if !urls.isEmpty {
                    if translationsQualities[translation] == nil {
                        translationsQualities[translation] = [:]
                    }
                    translationsQualities[translation]?[quality] = urls
                }
            }
        }
        
        let translations = translationsQualities.map { studio, streams in
            KinobaseTranslationDTO(studio: studio, streams: streams, subtitles: subtitlesMap, seasons: [])
        }.sorted { $0.studio < $1.studio }
        
        return ParsedStreams(translations: translations, subtitles: subtitlesMap)
    }
    
    /// Parses subtitles: [Forced (Russian)]https://... or https://...
    public static func parseSubtitles(from raw: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        guard let regex = try? NSRegularExpression(pattern: "\\[(.*?)\\]([^\\[,]+)") else {
            return [:]
        }
        let matches = regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw))
        
        for m in matches {
            guard let nameRange = Range(m.range(at: 1), in: raw),
                  let urlRange = Range(m.range(at: 2), in: raw) else { continue }
            
            let name = String(raw[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let urls = String(raw[urlRange])
                .components(separatedBy: " or ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.hasPrefix("http") }
            
            if !urls.isEmpty {
                result[name] = urls
            }
        }
        return result
    }
}
