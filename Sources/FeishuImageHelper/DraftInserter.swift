import AppKit
import ApplicationServices
import ImageHelperCore

enum DraftInsertionError: LocalizedError {
    case permission, missingApp, focus, event, cancelled
    var errorDescription: String? {
        switch self {
        case .permission: return "图片已复制。开启“一键粘贴”后，点图即可放入飞书；现在也可手动返回飞书按 ⌘V。"
        case .missingApp: return "图片已复制，但没有找到飞书，请先打开飞书。"
        case .focus: return "图片已复制。请先点击飞书的聊天输入框，再回搜图酱点图；也可直接按 ⌘V。"
        case .event: return "图片已复制，自动粘贴没有完成，请在飞书按 ⌘V。"
        case .cancelled: return "操作已取消：选择、聊天窗口或剪贴板已变化，未执行粘贴。"
        }
    }
}

struct DraftTarget {
    let pid: pid_t
    let composer: AXUIElement
    let window: AXUIElement
    let webArea: AXUIElement
    let heading: String
}

enum DraftInserter {
    static var hasPermission: Bool { AXIsProcessTrusted() }
    static var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.bytedance.macos.feishu")
        ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.larksuite.lark")
    }
    static func openFeishu(completion: @escaping (NSRunningApplication?, Error?) -> Void) {
        guard let url = applicationURL else { completion(nil, DraftInsertionError.missingApp); return }
        let config = NSWorkspace.OpenConfiguration(); config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: completion)
    }
    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func header(_ element: AXUIElement, depth: Int = 0) -> String? {
        // The locally verified messenger-chat hierarchy begins with the conversation heading.
        // Restrict traversal to that leading header branch; never enumerate message content.
        guard depth <= 6 else { return nil }
        if attribute(element, kAXRoleAttribute) as? String == kAXStaticTextRole,
           let text = attribute(element, kAXValueAttribute) as? String {
            let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty && name.count <= 150 && !name.contains("\n") ? name : nil
        }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement], let first = children.first else { return nil }
        return header(first, depth: depth + 1)
    }
    static func captureTarget() -> DraftTarget? {
        guard hasPermission,
              let app = ["com.bytedance.macos.feishu", "com.larksuite.lark"].lazy.compactMap({ NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }).first else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        guard let composer = elementAttribute(application, kAXFocusedUIElementAttribute),
              attribute(composer, kAXRoleAttribute) as? String == kAXTextAreaRole,
              let window = elementAttribute(composer, kAXWindowAttribute) else { return nil }
        var ancestor: AXUIElement? = composer
        for _ in 0..<24 {
            guard let current = ancestor else { break }
            if attribute(current, kAXRoleAttribute) as? String == "AXWebArea" {
                let raw = attribute(current, kAXURLAttribute)
                let url = (raw as? URL) ?? (raw as? String).flatMap(URL.init(string:))
                guard url?.isFileURL == true, url?.path.contains("/messenger-chat/") == true,
                      let heading = header(current) else { return nil }
                return DraftTarget(pid: app.processIdentifier, composer: composer, window: window, webArea: current, heading: heading)
            }
            ancestor = elementAttribute(current, kAXParentAttribute)
        }
        return nil
    }
    static func insert(target: DraftTarget, lease: PasteLease, currentOperation: @escaping () -> UUID,
                       completion: @escaping (Error?) -> Void) {
        guard hasPermission else { completion(DraftInsertionError.permission); return }
        guard lease.permits(currentOperation: currentOperation(), currentClipboardChangeCount: NSPasteboard.general.changeCount) else {
            completion(DraftInsertionError.cancelled); return
        }
        openFeishu { application, error in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard error == nil, let application, application.processIdentifier == target.pid else {
                    completion(error ?? DraftInsertionError.missingApp); return
                }
                guard lease.permits(currentOperation: currentOperation(), currentClipboardChangeCount: NSPasteboard.general.changeCount),
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
                      let actual = captureTarget(), actual.pid == target.pid,
                      CFEqual(actual.composer, target.composer), CFEqual(actual.window, target.window),
                      CFEqual(actual.webArea, target.webArea), actual.heading == target.heading else {
                    completion(DraftInsertionError.cancelled); return
                }
                guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
                      let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { completion(DraftInsertionError.event); return }
                down.flags = .maskCommand; up.flags = .maskCommand
                // Paste only. No Return key, no send API; only the original composer and clipboard qualify.
                down.postToPid(target.pid); up.postToPid(target.pid)
                completion(nil)
            }
        }
    }
    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if !hasPermission, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
}
