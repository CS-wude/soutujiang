import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum ImageHelperError: LocalizedError {
    case invalidImage, tooLarge, invalidURL, http(Int), unsupportedType, clipboard
    public var errorDescription: String? {
        switch self {
        case .invalidImage: return "链接没有返回完整图片，请打开大图后重试，或使用网页的复制图片。"
        case .tooLarge: return "图片超过 25 MB，或像素尺寸过大，请选择较小的图片。"
        case .invalidURL: return "这张图片的地址无法直接下载，请使用网页的复制图片或保存图片。"
        case .http(let code): return "图片站点拒绝下载（HTTP \(code)），请使用网页原有的复制或保存操作。"
        case .unsupportedType: return "暂不支持此图片格式，请选择 PNG、JPEG、GIF、WebP、TIFF 或 BMP。"
        case .clipboard: return "没有成功写入剪贴板，请重试。"
        }
    }
}

public struct ImagePayload {
    public let data: Data
    public let fileExtension: String
    public let isAnimated: Bool
    public static let maximumBytes = 25 * 1024 * 1024
    public init(data: Data) throws {
        guard data.count <= Self.maximumBytes else { throw ImageHelperError.tooLarge }
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0 else { throw ImageHelperError.invalidImage }
        guard width.doubleValue * height.doubleValue <= 80_000_000 else { throw ImageHelperError.tooLarge }
        guard let type = UTType(identifier),
              [.png, .jpeg, .gif, .webP, .tiff, .bmp].contains(where: { type.conforms(to: $0) }),
              let ext = type.preferredFilenameExtension else { throw ImageHelperError.unsupportedType }
        guard CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw ImageHelperError.invalidImage }
        self.data = data
        self.fileExtension = ext
        self.isAnimated = CGImageSourceGetCount(source) > 1
    }
    @discardableResult public func copy(to pasteboard: NSPasteboard = .general) throws -> URL? {
        let item = NSPasteboardItem()
        var originalFile: URL?
        // GIF/APNG/WebP animation travels as the original file: don't offer a still PNG fallback.
        if fileExtension == "gif" || isAnimated {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FeishuImageHelper", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
            try data.write(to: file, options: .atomic)
            item.setString(file.absoluteString, forType: .fileURL)
            if let type = UTType(filenameExtension: fileExtension) {
                item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
            }
            originalFile = file
        } else {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(width.intValue, height.intValue)
                  ] as CFDictionary) else { throw ImageHelperError.invalidImage }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ImageHelperError.invalidImage }
            item.setData(png, forType: .png)
            if let tiff = bitmap.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw ImageHelperError.clipboard }
        return originalFile
    }
}
