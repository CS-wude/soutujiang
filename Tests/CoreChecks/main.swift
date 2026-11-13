import Foundation
import AppKit
import ImageIO
import ImageHelperCore

var failures = 0
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    checks += 1
    if condition() { print("PASS \(name)") }
    else { failures += 1; print("FAIL \(name)") }
}
let keyword = "猫咪 & 摸鱼 #今天 + 100%"
let pasteOperation = UUID()
let lease = PasteLease(operation: pasteOperation, clipboardChangeCount: 12)
check(lease.permits(currentOperation: pasteOperation, currentClipboardChangeCount: 12), "current image paste lease is valid")
check(!lease.permits(currentOperation: UUID(), currentClipboardChangeCount: 12), "a newer selection cancels pending image paste")
check(!lease.permits(currentOperation: pasteOperation, currentClipboardChangeCount: 13), "clipboard change cancels pending image paste")
check(!SearchDocument.matches(URL(string: "https://cn.bing.com/images/search?q=old")!, requested: URL(string: "https://www.bing.com/images/search?q=new")!), "old search document cannot populate a newer query")
check(SearchDocument.matches(URL(string: "https://cn.bing.com/images/search?q=cat+GIF")!, requested: URL(string: "https://www.bing.com/images/search?q=cat%20GIF")!), "search redirects and form spaces preserve the intended query")
check(PageNotice.requiresVerification(url: URL(string: "https://wappass.baidu.com/static/captcha/a.html"), title: "百度安全验证"), "verification page is reported instead of showing normal search hint")
check(!PageNotice.requiresVerification(url: URL(string: "https://www.bing.com/images/search?q=验证"), title: "验证 图片"), "ordinary search about verification is not treated as a challenge")
for provider in SearchProvider.allCases {
    let url = SearchRequest(keyword: keyword, category: .pictures, provider: provider).url
    let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    check(items.first(where: { $0.name == (provider == .bing ? "q" : "word") })?.value == keyword,
          "Chinese, &, #, +, % stay in one query parameter: \(provider)")
    check(url?.scheme == "https", "search uses HTTPS: \(provider)")
    check(url?.absoluteString.contains("%2B") == true, "literal plus is not decoded as form-query space: \(provider)")
}
check(SearchRequest(keyword: " \n\t", category: .pictures, provider: .bing).url == nil, "blank query leaves page unchanged")
let stickers = SearchRequest(keyword: "谢谢", category: .stickers, provider: .bing).url
let stickerItems = stickers.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
check(stickerItems.first(where: { $0.name == "q" })?.value == "谢谢 表情包", "sticker search includes Chinese sticker keyword")
let gif = SearchRequest(keyword: "开心", category: .gif, provider: .bing).url
let gifItems = gif.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
check(gifItems.first(where: { $0.name == "q" })?.value == "开心 GIF 动图", "GIF search uses animation keyword")
check(gifItems.contains(where: { $0.name == "qft" && $0.value?.contains("animatedgif") == true }), "Bing GIF search filters animation")
for bad in ["file:///etc/passwd", "javascript:alert(1)", "data:image/png;base64,abc", "https://u:p@example.com/a.png", "https:///", "not a url"] {
    check(ImageURL.validated(bad) == nil, "reject unsafe image URL: \(bad)")
}
check(ImageURL.validated("https://example.com/a.gif?x=1&y=2")?.host == "example.com", "accept HTTPS image URL")
check(ImageURL.validated("http://example.com/a.jpg") != nil, "accept HTTP image URL")

// Generated two-colour fixtures are independent of production decoding and contain no remote content.
func makeImage(_ pixel: [UInt8]) -> CGImage {
    let bytes = Data(Array(repeating: pixel, count: 4).flatMap { $0 })
    return CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: bytes as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}
let red = makeImage([255, 0, 0, 255])
let pngData = NSMutableData()
let pngDestination = CGImageDestinationCreateWithData(pngData, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(pngDestination, red, nil)
CGImageDestinationFinalize(pngDestination)
let png = pngData as Data
let orientedData = NSMutableData()
let wideBytes = Data(Array(repeating: [UInt8(255), 0, 0, 255], count: 6).flatMap { $0 })
let wide = CGImage(width: 3, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 12,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
    provider: CGDataProvider(data: wideBytes as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
let jpegDestination = CGImageDestinationCreateWithData(orientedData, "public.jpeg" as CFString, 1, nil)!
CGImageDestinationAddImage(jpegDestination, wide, [kCGImagePropertyOrientation: 6] as CFDictionary)
CGImageDestinationFinalize(jpegDestination)
let animation = NSMutableData()
let destination = CGImageDestinationCreateWithData(animation, "com.compuserve.gif" as CFString, 2, nil)!
CGImageDestinationAddImage(destination, red, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
CGImageDestinationAddImage(destination, makeImage([0, 0, 255, 255]), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
CGImageDestinationFinalize(destination)

for bad in [Data("<html>Not an image</html>".utf8), Data(), Data(repeating: 0, count: 25 * 1024 * 1024 + 1)] {
    do { _ = try ImagePayload(data: bad); check(false, "reject fake, empty or oversized image") }
    catch { check(true, "reject fake, empty or oversized image") }
}
let pasteboard = NSPasteboard.withUniqueName()
do {
    let payload = try ImagePayload(data: png)
    check(payload.fileExtension == "png" && !payload.isAnimated, "recognize PNG by bytes")
    try payload.copy(to: pasteboard)
    check(pasteboard.data(forType: .png) != nil, "static image is pasted as image data")
    check(pasteboard.string(forType: .fileURL) == nil, "static image is not a file attachment")
} catch { check(false, "PNG copy failed: \(error)") }
do {
    let payload = try ImagePayload(data: animation as Data)
    check(payload.fileExtension == "gif" && payload.isAnimated, "recognize multi-frame GIF")
    let file = try payload.copy(to: pasteboard)
    let url = file ?? URL(fileURLWithPath: "/nonexistent")
    check((try? Data(contentsOf: url)) == animation as Data, "GIF paste preserves exact original file")
    check(pasteboard.string(forType: .fileURL) == file?.absoluteString, "GIF clipboard exposes file URL")
    check(pasteboard.data(forType: .png) == nil, "GIF clipboard does not silently prefer a still PNG")
    if let file { try? FileManager.default.removeItem(at: file) }
} catch { check(false, "GIF copy failed: \(error)") }
do {
    try ImagePayload(data: orientedData as Data).copy(to: pasteboard)
    let data = pasteboard.data(forType: .png)!
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
    check((props[kCGImagePropertyPixelWidth] as? Int) == 2 && (props[kCGImagePropertyPixelHeight] as? Int) == 3,
          "photo copy applies EXIF rotation before encoding PNG")
} catch { check(false, "oriented JPEG copy failed: \(error)") }
pasteboard.releaseGlobally()

if let folder = ProcessInfo.processInfo.environment["IMAGE_HELPER_FIXTURE_DIRECTORY"] {
    let directory = URL(fileURLWithPath: folder, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try png.write(to: directory.appendingPathComponent("test.png"))
    try (animation as Data).write(to: directory.appendingPathComponent("test.gif"))
}
if let base = ProcessInfo.processInfo.environment["IMAGE_HELPER_TEST_BASE_URL"] {
    for (path, shouldSucceed) in [("png", true), ("gif", true), ("redirect", true), ("html", false), ("forbidden", false), ("oversize", false)] {
        var received: Result<ImagePayload, Error>?
        let task = ImageDownloader.fetch(url: URL(string: base + "/" + path)!, referer: nil) { received = $0 }
        let deadline = Date().addingTimeInterval(10)
        while received == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        if let received {
            switch received {
            case .success(let payload):
                check(shouldSucceed, "download /\(path) succeeds only for real images")
                if path == "gif" { check(payload.isAnimated && payload.data == animation as Data, "download retains every GIF frame byte") }
            case .failure(let error):
                check(!shouldSucceed, "download /\(path) rejected: \(error.localizedDescription)")
            }
        } else {
            task?.cancel()
            check(false, "download /\(path) timed out")
        }
    }
}

print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
