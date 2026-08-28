import Foundation

public enum SeasonvarStreamDecoder {
    /// Decodes obfuscated Seasonvar video file string (e.g. #2Ly9kYXRh...)
    public static func decodeVideoURL(from raw: String) -> String {
        var clean = raw
        if clean.hasPrefix("#2") {
            clean = String(clean.dropFirst(2))
        }
        
        let noiseTokens = ["\\/\\/b2xvbG8=", "//b2xvbG8="]
        for token in noiseTokens {
            clean = clean.replacingOccurrences(of: token, with: "")
        }
        
        guard let data = Data(base64Encoded: clean),
              let urlString = String(data: data, encoding: .utf8) else {
            return ""
        }
        
        if urlString.hasPrefix("//") {
            return "https:\(urlString)"
        }
        return urlString
    }
    
    /// Cleans episode title from <br> tags, formatting into a human-readable title
    public static func cleanTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<br>", with: " ")
            .replacingOccurrences(of: "<br/>", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
