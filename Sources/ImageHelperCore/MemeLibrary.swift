import Foundation
import CryptoKit

public enum MemeServiceError: LocalizedError {
    case invalidResponse, limited, credits, http(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "梗图库返回的数据无法识别，请稍后重试，或手动切换必应图片。"
        case .limited: return "梗图库当前限流或免费额度已用完。免密钥额度为每个 IP 每天 20 次；缓存仍可使用，也可手动切换必应图片。"
        case .credits: return "梗图库额度暂不可用。可使用已缓存结果，或手动切换必应图片；搜图酱不会自动购买额度。"
        case .http(let code): return "梗图库暂不可用（HTTP \(code)）。可稍后重试或手动切换必应图片。"
        }
    }
    public static func forHTTP(_ code: Int) -> MemeServiceError? {
        if (200..<300).contains(code) { return nil }
        if code == 429 { return .limited }
        if code == 402 { return .credits }
        return .http(code)
    }
}

public struct MemeImage {
    public let url: URL
    public let thumbnail: URL
    public let source: URL
    public let title: String
    public let kind: String
    public let tags: [String]
}
public enum MemeLibrary {
    public static func decode(_ data: Data) throws -> [MemeImage] {
        guard data.count <= 2 * 1024 * 1024,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = body["data"] as? [[String: Any]] else { throw MemeServiceError.invalidResponse }
        var seen = Set<String>()
        return raw.prefix(200).compactMap { item -> MemeImage? in
            guard item["private"] as? Bool != true,
                  let original = item["url"] as? String, let url = ImageURL.validated(original),
                  seen.insert(url.absoluteString).inserted else { return nil }
            let thumbnail = (item["thumb_url"] as? String).flatMap(ImageURL.validated) ?? url
            let source = (item["page_url"] as? String).flatMap(ImageURL.validated) ?? URL(string: "https://memecub.com/zh")!
            let chinese = (item["title_zh"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = chinese.flatMap { $0.isEmpty ? nil : $0 } ?? (item["title"] as? String) ?? "梗图"
            let tags = (item["tags_zh"] as? [String] ?? []) + (item["tags"] as? [String] ?? [])
            return MemeImage(url: url, thumbnail: thumbnail, source: source, title: String(title.prefix(300)),
                             kind: item["kind"] as? String ?? "meme", tags: Array(tags.prefix(30)))
        }.prefix(50).map { $0 }
    }
}
public final class MemeCache {
    private struct Entry: Codable { let savedAt: Date; let data: Data }
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    private func file(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash).appendingPathExtension("json")
    }
    public func store(_ data: Data, for url: URL, now: Date = Date()) throws {
        guard data.count <= 2 * 1024 * 1024 else { throw MemeServiceError.invalidResponse }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoded = try JSONEncoder().encode(Entry(savedAt: now, data: data))
        try encoded.write(to: file(for: url), options: .atomic)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "json" }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for old in files.dropFirst(64) { try? FileManager.default.removeItem(at: old) }
    }
    public func load(for url: URL, maxAge: TimeInterval, now: Date = Date()) -> Data? {
        let location = file(for: url)
        guard let size = try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 3 * 1024 * 1024,
              let bytes = try? Data(contentsOf: location), let entry = try? JSONDecoder().decode(Entry.self, from: bytes),
              now.timeIntervalSince(entry.savedAt) >= 0, now.timeIntervalSince(entry.savedAt) <= maxAge else { return nil }
        return entry.data
    }
}
