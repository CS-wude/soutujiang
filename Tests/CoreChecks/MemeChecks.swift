import Foundation
import ImageHelperCore

func runMemeChecks() {
    let query = "绷不住了 & 摸鱼+1"
    let request = SearchRequest(keyword: query, category: .stickers, provider: .memecub)
    let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    check(request.url?.host == "memecub.com", "meme search goes directly to library API")
    check(items.first(where: { $0.name == "q" })?.value == query, "meme search sends original phrase without web-search suffix")
    check(items.first(where: { $0.name == "category" })?.value == "cn-memes", "sticker search uses Chinese meme library")
    let gif = SearchRequest(keyword: "吗喽", category: .gif, provider: .memecub).url
    let gifItems = gif.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    check(gifItems.first(where: { $0.name == "kind" })?.value == "gif", "GIF category uses API animation filter")
    let popular = SearchRequest(keyword: "", category: .stickers, provider: .memecub, order: .popular).url
    let popularItems = popular.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    check(popularItems.first(where: { $0.name == "sort" })?.value == "popular", "popular button reads actual provider ranking without a fabricated search term")
    check(SearchRequest(keyword: "  ", category: .stickers, provider: .memecub).url == nil, "blank relevance query is not sent")

    let fixture = Data(#"{"data":[{"title":"fallback","title_zh":"蚌埠住了","url":"https://images.example/a.gif","thumb_url":"https://images.example/a.webp","page_url":"https://memecub.com/meme/a","kind":"gif","tags_zh":["绷不住了","憋笑"]},{"title":"duplicate","url":"https://images.example/a.gif"},{"title":"bad image","url":"file:///secret"},{"title":"private","url":"https://images.example/private.png","private":true},{"title":"摸鱼","url":"https://images.example/b.jpg","thumb_url":null,"page_url":"javascript:bad()","kind":"meme"}]}"#.utf8)
    do {
        let result = try MemeLibrary.decode(fixture)
        check(result.count == 2, "decode skips duplicate, unsafe and private results")
        check(result.first?.title == "蚌埠住了" && result.first?.tags.contains("憋笑") == true, "decode preserves Chinese title and reaction tags")
        check(result.last?.thumbnail == result.last?.url && result.last?.source.host == "memecub.com", "missing thumbnail uses same image and invalid source uses library home")
    } catch { check(false, "valid meme response decoded: \(error)") }
    for invalid in [Data("<html>blocked</html>".utf8), Data(#"{"error":"rate_limited"}"#.utf8), Data(#"{"data":"wrong shape"}"#.utf8)] {
        do { _ = try MemeLibrary.decode(invalid); check(false, "malformed service payload fails explicitly") }
        catch { check(true, "malformed service payload fails explicitly") }
    }
    do {
        let empty = try MemeLibrary.decode(Data(#"{"data":[]}"#.utf8))
        check(empty.isEmpty, "empty library result remains a valid empty result")
    } catch { check(false, "empty library response failed") }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SoutujiangCacheChecks-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = MemeCache(directory: directory)
    let key = URL(string: "https://memecub.com/api/v1/search?q=cat")!
    let other = URL(string: "https://memecub.com/api/v1/search?q=cat&sort=newest")!
    let moment = Date(timeIntervalSince1970: 10000)
    do {
        try cache.store(fixture, for: key, now: moment)
        check(cache.load(for: key, maxAge: 3600, now: moment.addingTimeInterval(20)) == fixture, "repeated query reads stored response without a network request")
        check(MemeCache(directory: directory).load(for: key, maxAge: 3600, now: moment.addingTimeInterval(20)) == fixture, "query cache survives app restart")
        check(cache.load(for: key, maxAge: 15, now: moment.addingTimeInterval(20)) == nil, "expired popular query is not served as fresh")
        check(cache.load(for: other, maxAge: 3600, now: moment) == nil, "sort and category query differences have separate cache entries")
    } catch { check(false, "cache write failed: \(error)") }
}

func runMemeNetworkChecks(base: String) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SoutujiangNetworkCache-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = MemeSearchClient(cacheDirectory: directory)
    func fetch(_ path: String) -> Result<MemeSearchResult, Error>? {
        var result: Result<MemeSearchResult, Error>?
        let task = client.fetch(url: URL(string: base + path)!, maxAge: 3600) { result = $0 }
        let deadline = Date().addingTimeInterval(10)
        while result == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        if result == nil { task?.cancel() }
        return result
    }
    if case .success(let page)? = fetch("/meme-ok") {
        check(page.images.first?.title == "reply 1" && !page.isCached, "first meme query reads real HTTP result")
    } else { check(false, "first meme HTTP query failed") }
    if case .success(let page)? = fetch("/meme-ok") {
        check(page.images.first?.title == "reply 1" && page.isCached, "second identical query does not hit server or spend search quota")
    } else { check(false, "cached meme query failed") }
    for path in ["/meme-rate", "/meme-credit", "/meme-invalid"] {
        if case .failure(let error)? = fetch(path) {
            if path == "/meme-rate" {
                if case .some(.limited) = error as? MemeServiceError { check(true, "HTTP 429 preserves quota error without silent web fallback") }
                else { check(false, "HTTP 429 lost its quota error") }
            } else if path == "/meme-credit" {
                if case .some(.credits) = error as? MemeServiceError { check(true, "HTTP 402 preserves credit error without purchases") }
                else { check(false, "HTTP 402 lost credit error") }
            } else { check(error is MemeServiceError, "invalid JSON shape is not rendered as results") }
        } else { check(false, "\(path) should fail explicitly") }
    }
    if case .success(let page)? = fetch("/meme-empty") { check(page.images.isEmpty, "empty search remains empty") }
    else { check(false, "empty query response failed") }
    if case .success(let page)? = fetch("/meme-empty") {
        check(page.images.first?.title == "reply 2" && !page.isCached, "newly indexed memes are not hidden by caching an empty search")
    } else { check(false, "newly indexed meme response failed") }
}
