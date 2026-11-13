import Foundation

public enum SearchCategory: Int, CaseIterable {
    case stickers, gif, pictures
}
public enum SearchProvider: Int, CaseIterable {
    case bing, baidu
}
public struct SearchRequest {
    public let keyword: String
    public let category: SearchCategory
    public let provider: SearchProvider
    public init(keyword: String, category: SearchCategory, provider: SearchProvider) {
        self.keyword = keyword; self.category = category; self.provider = provider
    }
    public var url: URL? {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let suffix: String
        switch category {
        case .stickers: suffix = " 表情包"
        case .gif: suffix = " GIF 动图"
        case .pictures: suffix = ""
        }
        var parts = URLComponents()
        parts.scheme = "https"
        switch provider {
        case .bing:
            parts.host = "www.bing.com"; parts.path = "/images/search"
            parts.queryItems = [URLQueryItem(name: "q", value: trimmed + suffix),
                                URLQueryItem(name: "adlt", value: "strict")]
            if category == .gif {
                parts.queryItems?.append(URLQueryItem(name: "qft", value: "+filterui:photo-animatedgif"))
            }
        case .baidu:
            parts.host = "image.baidu.com"; parts.path = "/search/index"
            parts.queryItems = [URLQueryItem(name: "tn", value: "baiduimage"),
                                URLQueryItem(name: "word", value: trimmed + suffix)]
        }
        // Search engines decode query strings as forms, where a bare '+' would become a space.
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url
    }
}

public enum ImageURL {
    public static func validated(_ string: String) -> URL? {
        guard let url = URL(string: string),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}
