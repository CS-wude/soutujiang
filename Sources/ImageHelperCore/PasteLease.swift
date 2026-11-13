import Foundation

public struct PasteLease {
    public let operation: UUID
    public let clipboardChangeCount: Int
    public init(operation: UUID, clipboardChangeCount: Int) {
        self.operation = operation; self.clipboardChangeCount = clipboardChangeCount
    }
    public func permits(currentOperation: UUID, currentClipboardChangeCount: Int) -> Bool {
        operation == currentOperation && clipboardChangeCount == currentClipboardChangeCount
    }
}

public enum SearchDocument {
    public static func matches(_ document: URL, requested: URL) -> Bool {
        func query(_ url: URL) -> String? {
            guard let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery else { return nil }
            for pair in raw.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                if parts.count == 2, ["q", "word"].contains(String(parts[0])) {
                    return String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding
                }
            }
            return nil
        }
        guard let actual = query(document), let expected = query(requested) else { return false }
        return actual == expected
    }
}
