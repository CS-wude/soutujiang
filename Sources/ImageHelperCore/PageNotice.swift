import Foundation

public enum PageNotice {
    public static func requiresVerification(url: URL?, title: String?) -> Bool {
        let host = url?.host?.lowercased() ?? ""
        let path = url?.path.lowercased() ?? ""
        return host == "wappass.baidu.com" || path.contains("/captcha") || path.contains("/challenge")
            || (title?.contains("安全验证") ?? false) || (title?.lowercased().contains("captcha") ?? false)
    }
}
