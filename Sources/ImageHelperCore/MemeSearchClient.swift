import Foundation

public struct MemeSearchResult {
    public let images: [MemeImage]
    public let isCached: Bool
}

public final class MemeSearchClient {
    private let cache: MemeCache
    public init(cacheDirectory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cache = MemeCache(directory: cacheDirectory ?? base.appendingPathComponent("Soutujiang/search-cache", isDirectory: true))
    }
    @discardableResult
    public func fetch(url: URL, maxAge: TimeInterval, completion: @escaping (Result<MemeSearchResult, Error>) -> Void) -> URLSessionDataTask? {
        guard ImageURL.validated(url.absoluteString) != nil else {
            DispatchQueue.main.async { completion(.failure(MemeServiceError.invalidResponse)) }; return nil
        }
        if let bytes = cache.load(for: url, maxAge: maxAge), let images = try? MemeLibrary.decode(bytes), !images.isEmpty {
            DispatchQueue.main.async { completion(.success(MemeSearchResult(images: images, isCached: true))) }
            return nil
        }
        return MemeRequest.start(url: url, cache: cache, completion: completion)
    }
}

private final class MemeRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let url: URL
    private let cache: MemeCache
    private let completion: (Result<MemeSearchResult, Error>) -> Void
    private var session: URLSession!
    private var bytes = Data()
    private var finished = false
    private static let limit = 2 * 1024 * 1024
    private init(url: URL, cache: MemeCache, completion: @escaping (Result<MemeSearchResult, Error>) -> Void) {
        self.url = url; self.cache = cache; self.completion = completion
    }
    static func start(url: URL, cache: MemeCache, completion: @escaping (Result<MemeSearchResult, Error>) -> Void) -> URLSessionDataTask {
        let worker = MemeRequest(url: url, cache: cache, completion: completion)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
        config.httpCookieStorage = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        worker.session = URLSession(configuration: config, delegate: worker, delegateQueue: nil)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Soutujiang/1.1", forHTTPHeaderField: "User-Agent")
        let task = worker.session.dataTask(with: request)
        task.resume(); return task
    }
    private func finish(_ result: Result<MemeSearchResult, Error>) {
        guard !finished else { return }
        finished = true; session.invalidateAndCancel()
        DispatchQueue.main.async { self.completion(result) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, response.expectedContentLength <= Self.limit else {
            completionHandler(.cancel); finish(.failure(MemeServiceError.invalidResponse)); return
        }
        if let error = MemeServiceError.forHTTP(http.statusCode) {
            completionHandler(.cancel); finish(.failure(error)); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished else { return }
        guard bytes.count + data.count <= Self.limit else { finish(.failure(MemeServiceError.invalidResponse)); return }
        bytes.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        if let error { finish(.failure(error)); return }
        do {
            let images = try MemeLibrary.decode(bytes)
            if !images.isEmpty { try? cache.store(bytes, for: url) }
            finish(.success(MemeSearchResult(images: images, isCached: false)))
        } catch { finish(.failure(error)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let destination = request.url, destination.host == url.host, destination.scheme == url.scheme else {
            completionHandler(nil); finish(.failure(MemeServiceError.invalidResponse)); return
        }
        completionHandler(request)
    }
}
