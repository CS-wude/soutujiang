import Foundation

public enum SearchCategory: Int, CaseIterable {
    case stickers, gif, pictures
}
public enum SearchProvider: Int, CaseIterable {
    case bing, baidu, memecub
}
public enum SearchOrder: Int, CaseIterable {
    case relevance, popular, newest
}
public struct SearchRequest {
    public let keyword: String
    public let category: SearchCategory
    public let provider: SearchProvider
    public let order: SearchOrder
    public init(keyword: String, category: SearchCategory, provider: SearchProvider, order: SearchOrder = .relevance) {
        self.keyword = keyword; self.category = category; self.provider = provider
        self.order = order
    }
    public var url: URL? {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || (provider == .memecub && order != .relevance) else { return nil }
        let suffix: String
        switch category {
        case .stickers: suffix = " 表情包"
        case .gif: suffix = " GIF 动图"
        case .pictures: suffix = ""
        }
        var parts = URLComponents()
        parts.scheme = "https"
        switch provider {
        case .memecub:
            parts.host = "memecub.com"; parts.path = "/api/v1/search"
            parts.queryItems = [URLQueryItem(name: "q", value: trimmed), URLQueryItem(name: "limit", value: "40")]
            if category == .pictures {
                parts.queryItems?.append(URLQueryItem(name: "kind", value: "photo"))
            } else {
                parts.queryItems?.append(URLQueryItem(name: "category", value: "cn-memes"))
                if category == .gif { parts.queryItems?.append(URLQueryItem(name: "kind", value: "gif")) }
            }
            if order != .relevance {
                parts.queryItems?.append(URLQueryItem(name: "sort", value: order == .popular ? "popular" : "newest"))
            }
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
