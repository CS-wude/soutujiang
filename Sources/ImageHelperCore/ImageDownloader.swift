import Foundation

/// One session per user-initiated transfer; no cookies, account credentials or page scripts are shared.
public final class ImageDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var session: URLSession!
    private var completed = false
    private let completion: (Result<ImagePayload, Error>) -> Void

    private init(completion: @escaping (Result<ImagePayload, Error>) -> Void) {
        self.completion = completion
    }

    @discardableResult
    public static func fetch(url: URL, referer: URL?, completion: @escaping (Result<ImagePayload, Error>) -> Void) -> URLSessionDownloadTask? {
        guard ImageURL.validated(url.absoluteString) != nil else {
            DispatchQueue.main.async { completion(.failure(ImageHelperError.invalidURL)) }
            return nil
        }
        let worker = ImageDownloader(completion: completion)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        config.httpCookieStorage = nil
        worker.session = URLSession(configuration: config, delegate: worker, delegateQueue: nil)
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        if let referer, ImageURL.validated(referer.absoluteString) != nil {
            // Origin only: don't forward the user's complete search query to an image host.
            var origin = URLComponents()
            origin.scheme = referer.scheme; origin.host = referer.host; origin.port = referer.port
            request.setValue(origin.url?.absoluteString, forHTTPHeaderField: "Referer")
        }
        let task = worker.session.downloadTask(with: request)
        task.resume()
        return task
    }

    private func finish(_ result: Result<ImagePayload, Error>) {
        guard !completed else { return }
        completed = true
        session.invalidateAndCancel()
        DispatchQueue.main.async { self.completion(result) }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > ImagePayload.maximumBytes || totalBytesExpectedToWrite > ImagePayload.maximumBytes {
            finish(.failure(ImageHelperError.tooLarge))
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard !completed else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse else { throw ImageHelperError.invalidImage }
            guard (200..<300).contains(response.statusCode) else { throw ImageHelperError.http(response.statusCode) }
            let values = try location.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? Int.max) <= ImagePayload.maximumBytes else { throw ImageHelperError.tooLarge }
            let payload = try ImagePayload(data: Data(contentsOf: location))
            finish(.success(payload))
        } catch { finish(.failure(error)) }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, ImageURL.validated(url.absoluteString) != nil else {
            completionHandler(nil); finish(.failure(ImageHelperError.invalidURL)); return
        }
        completionHandler(request)
    }
}
