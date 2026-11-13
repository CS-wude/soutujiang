import AppKit
import WebKit
import UniformTypeIdentifiers
import ImageHelperCore

final class SearchPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

private struct SearchImage {
    let url: URL
    let thumbnail: URL
    let title: String
    let source: URL
    var sourceName = "通用搜索"
    var kind = ""
    var json: [String: String] { ["url": url.absoluteString, "thumbnail": thumbnail.absoluteString, "title": title, "sourceName": sourceName, "kind": kind] }
}

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private var panel: SearchPanel!
    private var grid: WKWebView!
    private var searchPage: WKWebView!
    private var statusItem: NSStatusItem!
    private var hotKey: GlobalHotKey!
    private let field = NSSearchField()
    private let category = NSSegmentedControl(labels: ["表情 / 热梗", "GIF 动图", "普通图片"], trackingMode: .selectOne, target: nil, action: nil)
    private let provider = NSPopUpButton()
    private let order = NSPopUpButton()
    private let providers: [SearchProvider] = [.memecub, .bing, .baidu]
    private let memeClient = MemeSearchClient()
    private var apiTask: URLSessionDataTask?
    private var previousCategory: SearchCategory = .stickers
    private var lastProvider: SearchProvider = .memecub
    private let status = NSTextField(wrappingLabelWithString: "")
    private let shortcut = NSTextField(labelWithString: "⌃⌥ 空格 · 随时唤出")
    private var permissionButton: NSButton!
    private var images: [SearchImage] = []
    private var lastSearchURL: URL?
    private var searchToken = UUID()
    private var activeNavigation: WKNavigation?
    private var loadedToken: UUID?
    private var transfer: URLSessionDownloadTask?
    private var operation = UUID()
    private var gridReady = false
    private var pendingRender: (String, Any)?
    private var activeCategory: SearchCategory = .stickers
    private lazy var resources: Bundle = {
        // Shipped .app resources must work without the developer's .build directory.
        if let url = Bundle.main.url(forResource: "FeishuImageHelper_FeishuImageHelper", withExtension: "bundle"), let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeMenus(); makeWindow()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showWindow(_:)), name: Notification.Name("local.wude.Soutujiang.show"), object: nil)
        hotKey = GlobalHotKey { [weak self] in self?.toggle(nil) }
        let result = hotKey.register()
        if result != 0 {
            shortcut.stringValue = "快捷键被占用 · 使用菜单栏入口"
            shortcut.textColor = .systemOrange
            shortcut.toolTip = "系统返回 \(result)，点击菜单栏图片图标也可打开窗口。"
        }
        showWindow(nil)
    }
    func applicationDidBecomeActive(_ notification: Notification) { updatePermissionButton() }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }
    private func makeMenus() {
        let main = NSMenu(), appMenu = NSMenu(), appItem = NSMenuItem()
        appItem.submenu = appMenu; main.addItem(appItem)
        appMenu.addItem(NSMenuItem(title: "退出搜图酱", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let edit = NSMenu(title: "编辑"), editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = edit; main.addItem(editItem)
        for (title, action, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        let find = NSMenuItem(title: "输入搜图关键词", action: #selector(focusSearch(_:)), keyEquivalent: "f")
        find.target = self; edit.addItem(find); NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "搜图酱")
        statusItem.button?.toolTip = "搜图酱 · Control + Option + 空格"
        let menu = NSMenu()
        for (title, action) in [("显示／隐藏搜图酱    ⌃⌥空格", #selector(toggle(_:))), ("使用说明", #selector(help(_:))), ("返回飞书", #selector(returnToFeishu(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出搜图酱", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
    private func makeWindow() {
        panel = SearchPanel(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760), styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "搜图酱"; panel.minSize = NSSize(width: 760, height: 590)
        panel.isFloatingPanel = true; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false; panel.delegate = self
        panel.onEscape = { [weak self] in self?.cancelTransfer(); self?.panel.orderOut(nil) }
        if let frame = NSScreen.main?.visibleFrame { panel.setContentSize(NSSize(width: min(1000, frame.width - 40), height: min(760, frame.height - 60))) }
        panel.center()
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, contentWorld: .defaultClient, name: "gridAction")
        if let url = resource("grid-bridge", "js"), let source = try? String(contentsOf: url, encoding: .utf8) {
            config.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        }
        grid = WKWebView(frame: .zero, configuration: config); grid.navigationDelegate = self
        grid.setContentHuggingPriority(.defaultLow, for: .vertical)
        grid.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        searchPage = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        searchPage.navigationDelegate = self
        searchPage.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15"
        let root = NSView(); panel.contentView = root
        let heading = NSTextField(labelWithString: "搜图酱")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        shortcut.font = .systemFont(ofSize: 12); shortcut.textColor = .secondaryLabelColor
        let header = NSStackView(views: [heading, NSView(), shortcut, button("返回飞书 ↗", #selector(returnToFeishu(_:)))])
        header.spacing = 14; header.alignment = .centerY
        field.placeholderString = "搜点什么？例如：谢谢、摸鱼、猫咪"
        field.font = .systemFont(ofSize: 15)
        field.target = self; field.action = #selector(search(_:))
        field.sendsSearchStringImmediately = false; field.sendsWholeSearchString = true
        field.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let searchButton = button("搜索", #selector(search(_:))); searchButton.bezelColor = .systemGreen
        let searchRow = NSStackView(views: [field, searchButton]); searchRow.spacing = 10
        category.selectedSegment = 0; category.target = self; category.action = #selector(changeFilter(_:))
        provider.addItems(withTitles: ["梗图库 · 免费 20 次/天/IP", "必应图片", "百度图片"]); provider.target = self; provider.action = #selector(changeFilter(_:))
        provider.toolTip = "梗图库使用 memecub，免密钥额度为每个 IP 每天 20 次搜索；命中本地缓存不消耗搜索次数。"
        permissionButton = button("开启一键粘贴", #selector(permission(_:)))
        let filters = NSStackView(views: [category, provider, NSView(), permissionButton]); filters.spacing = 10
        order.addItems(withTitles: ["相关优先", "图源热门", "最新收录"])
        order.target = self; order.action = #selector(changeFilter(_:))
        let tools = NSStackView(views: [button("图库热门", #selector(popular(_:))), order, NSView(), button("重试搜索", #selector(retry(_:))), button("在浏览器打开", #selector(browser(_:))), button("帮助", #selector(help(_:)))])
        tools.spacing = 8
        status.font = .systemFont(ofSize: 12); status.maximumNumberOfLines = 2
        status.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let stack = NSStackView(views: [header, searchRow, filters, tools, grid, status])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16), stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8)])
        let rows: [NSView] = [header, searchRow, filters, tools, grid, status]
        for row in rows { row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        if let url = resource("grid", "html") { grid.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
        updatePermissionButton()
        message("表情和热梗默认直连梗图库。免密钥每 IP 每天 20 次；重复查询有缓存。可点“图库热门”浏览。")
    }
    private func resource(_ name: String, _ ext: String) -> URL? { resources.url(forResource: name, withExtension: ext, subdirectory: "Resources") }
    private func render(_ function: String, _ value: Any = "") {
        guard gridReady else { pendingRender = (function, value); return }
        grid.callAsyncJavaScript("window.\(function)(value)", arguments: ["value": value], in: nil, in: .page) { _ in }
    }
    private func message(_ text: String, error: Bool = false) { status.stringValue = text; status.toolTip = text; status.textColor = error ? .systemOrange : .secondaryLabelColor }
    private func updatePermissionButton() {
        guard permissionButton != nil else { return }
        permissionButton.title = DraftInserter.hasPermission ? "一键粘贴已开启 ✓" : "开启一键粘贴"
    }
    @objc func showWindow(_ sender: Any?) {
        cancelTransfer()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? panel.screen ?? NSScreen.main
        if let screen { panel.setFrame(WindowPlacement.constrained(panel.frame, to: screen.visibleFrame), display: false) }
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(field); updatePermissionButton()
    }
    @objc private func toggle(_ sender: Any?) { cancelTransfer(); if panel.isVisible { panel.orderOut(nil) } else { showWindow(nil) } }
    @objc private func focusSearch(_ sender: Any?) { panel.makeFirstResponder(field) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { cancelTransfer(); sender.orderOut(nil); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(nil); return true }
    @objc private func permission(_ sender: Any?) {
        if DraftInserter.hasPermission { message("一键粘贴已开启。先在飞书点击聊天输入框，再唤出搜图酱并点图。"); return }
        let alert = NSAlert(); alert.messageText = "允许搜图酱将图片粘贴到飞书？"
        alert.informativeText = "需要你在 macOS“隐私与安全性 → 辅助功能”中允许搜图酱。它仅对飞书的聊天输入框执行粘贴，不会替你发送。不开启时也能手动粘贴。"
        alert.addButton(withTitle: "打开系统设置"); alert.addButton(withTitle: "稍后，手动粘贴")
        alert.beginSheetModal(for: panel) { response in if response == .alertFirstButtonReturn { DraftInserter.requestPermission() } }
    }
    private func cancelTransfer() { operation = UUID(); transfer?.cancel(); transfer = nil }
    private var selectedProvider: SearchProvider {
        providers.indices.contains(provider.indexOfSelectedItem) ? providers[provider.indexOfSelectedItem] : .memecub
    }
    @objc private func search(_ sender: Any?) {
        let kind = SearchCategory(rawValue: category.selectedSegment) ?? .stickers
        let source = selectedProvider
        let sorting = SearchOrder(rawValue: order.indexOfSelectedItem) ?? .relevance
        let request = SearchRequest(keyword: field.stringValue, category: kind, provider: source, order: sorting)
        guard let url = request.url else { message("先输入关键词，再按回车搜索。"); focusSearch(nil); return }
        if source == .memecub, apiTask != nil, lastProvider == .memecub, lastSearchURL == url {
            message("相同搜索正在进行中，继续等待即可；不会重复消耗搜索额度。")
            return
        }
        cancelTransfer(); apiTask?.cancel(); apiTask = nil; activeNavigation = nil; searchPage.stopLoading()
        searchToken = UUID(); loadedToken = nil; images = []; activeCategory = kind; lastProvider = source
        lastSearchURL = url; render("showLoading"); message("正在找图…")
        if source == .memecub {
            let token = searchToken
            let maxAge: TimeInterval = sorting == .relevance ? 24 * 3600 : 15 * 60
            apiTask = memeClient.fetch(url: url, maxAge: maxAge) { [weak self] result in
                guard let self, token == self.searchToken else { return }
                self.apiTask = nil; self.loadedToken = token
                switch result {
                case .failure(let error):
                    let text = (error is MemeServiceError) ? error.localizedDescription : "梗图库连接失败：\(error.localizedDescription)。可重试或手动切换必应图片。"
                    self.render("showNotice", text); self.message(text, error: true)
                case .success(let page):
                    let items = kind == .gif ? page.images.filter { $0.kind == "gif" } : page.images
                    self.images = items.map { SearchImage(url: $0.url, thumbnail: $0.thumbnail, title: $0.title,
                                                         source: $0.source, sourceName: "memecub 梗图库", kind: $0.kind) }
                    guard !self.images.isEmpty else {
                        let text = "梗图库暂无匹配结果。可换个梗名或情绪词，也可手动切换必应图片。"
                        self.render("showNotice", text); self.message(text); return
                    }
                    let caption = "\(self.images.count) 张梗图 · memecub · \(page.isCached ? "本地缓存，不消耗本次搜索额度" : "图源返回，免密钥每 IP 每天 20 次")"
                    self.render("renderResults", ["items": self.images.map(\.json), "generation": token.uuidString, "caption": caption])
                    self.message(caption + "。点击图片放入飞书草稿，发送由你确认。")
                }
            }
        } else { activeNavigation = searchPage.load(URLRequest(url: url, timeoutInterval: 35)) }
    }
    @objc private func changeFilter(_ sender: Any?) {
        let kind = SearchCategory(rawValue: category.selectedSegment) ?? .stickers
        if kind == .pictures && selectedProvider == .memecub { provider.selectItem(at: 1) }
        else if sender as? NSSegmentedControl === category, previousCategory == .pictures, kind != .pictures { provider.selectItem(at: 0) }
        previousCategory = kind
        order.isEnabled = selectedProvider == .memecub
        if !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (selectedProvider == .memecub && order.indexOfSelectedItem > 0) { search(nil) }
        else {
            cancelTransfer(); apiTask?.cancel(); apiTask = nil; searchToken = UUID(); activeNavigation = nil
            searchPage.stopLoading(); images = []; lastSearchURL = nil; lastProvider = selectedProvider
            render("showWelcome"); message("输入关键词后搜索，或点击“图库热门”。")
        }
    }
    @objc private func popular(_ sender: Any?) {
        if category.selectedSegment == SearchCategory.pictures.rawValue { category.selectedSegment = 0; previousCategory = .stickers }
        provider.selectItem(at: 0); order.isEnabled = true; order.selectItem(at: 1); field.stringValue = ""; search(nil)
    }
    @objc private func retry(_ sender: Any?) { search(nil) }
    @objc private func browser(_ sender: Any?) {
        guard let url = lastSearchURL else { message("先输入关键词搜索，或点击“图库热门”，再打开浏览器。"); return }
        if lastProvider == .memecub { NSWorkspace.shared.open(URL(string: "https://memecub.com/zh")!) }
        else { NSWorkspace.shared.open(url) }
    }
    @objc private func help(_ sender: Any?) { cancelTransfer(); apiTask?.cancel(); apiTask = nil; searchToken = UUID(); activeNavigation = nil; searchPage.stopLoading(); images = []; lastSearchURL = nil; render("showWelcome"); showWindow(nil) }
    @objc private func returnToFeishu(_ sender: Any?) {
        cancelTransfer()
        DraftInserter.openFeishu { [weak self] _, error in DispatchQueue.main.async {
            if let error { self?.message(error.localizedDescription, error: true) } else { self?.panel.orderOut(nil) }
        } }
    }
    private func extract(attempt: Int, token: UUID) {
        guard token == searchToken, loadedToken != token else { return }
        guard let file = resource("extract", "js"), let script = try? String(contentsOf: file, encoding: .utf8) else {
            message("搜图资源缺失，请重新构建应用。", error: true); return
        }
        searchPage.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self] result in
            guard let self, token == self.searchToken, self.loadedToken != token else { return }
            if case .success(let value) = result, let body = value as? [String: Any] {
                if PageNotice.requiresVerification(url: self.searchPage.url, title: body["title"] as? String) {
                    let text = "搜索网站要求安全验证。请切换“必应图片”，或在浏览器手动完成验证后再试。"
                    self.loadedToken = token; self.render("showNotice", text); self.message(text, error: true); return
                }
                let document = (body["url"] as? String).flatMap(URL.init(string:))
                let isCurrentDocument = document.flatMap { page in self.lastSearchURL.map { SearchDocument.matches(page, requested: $0) } } ?? false
                let raw = isCurrentDocument ? (body["items"] as? [[String: Any]] ?? []) : []
                let parsed = raw.compactMap { item -> SearchImage? in
                    guard let original = item["url"] as? String, let url = ImageURL.validated(original),
                          let thumb = item["thumbnail"] as? String, let thumbnail = ImageURL.validated(thumb) else { return nil }
                    let source = (item["source"] as? String).flatMap(ImageURL.validated) ?? url
                    return SearchImage(url: url, thumbnail: thumbnail, title: item["title"] as? String ?? "图片", source: source)
                }
                if !parsed.isEmpty {
                    self.images = parsed; self.loadedToken = token
                    self.render("renderResults", ["items": parsed.map(\.json), "generation": token.uuidString])
                    self.message("找到 \(parsed.count) 张图片。点击图片放入飞书输入框；“仅复制”和“保存原图”也可使用。")
                    return
                }
            }
            if attempt < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.extract(attempt: attempt + 1, token: token) }
            } else {
                let text = "暂时没有取得可选图片。可换个关键词、重试，或在浏览器查看搜索结果。"
                self.render("showNotice", text); self.message(text, error: true)
            }
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === grid, message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any], let action = body["action"] as? String,
              body["generation"] as? String == searchToken.uuidString,
              let index = body["index"] as? Int, images.indices.contains(index) else { return }
        let image = images[index]
        if action == "source" { NSWorkspace.shared.open(image.source); return }
        guard ["choose", "copy", "save"].contains(action) else { return }
        cancelTransfer()
        let token = UUID(); operation = token
        let kind = activeCategory
        let target = action == "choose" ? DraftInserter.captureTarget() : nil
        self.message("正在获取这张图片…")
        transfer = ImageDownloader.fetch(url: image.url, referer: lastSearchURL) { [weak self] result in
            guard let self, self.operation == token else { return }
            self.transfer = nil
            switch result {
            case .failure(let error): self.message(error.localizedDescription, error: true)
            case .success(let payload):
                if action == "save" { self.save(payload); return }
                if kind == .gif && !payload.isAnimated {
                    self.message("该结果实际返回静态图，未放入飞书。请换一张动图，或切换“普通图片”分类。", error: true); return
                }
                do {
                    _ = try payload.copy()
                    if action == "copy" { self.message("已复制\(payload.isAnimated ? "原动图文件" : "图片")，可返回飞书按 ⌘V。"); return }
                    guard DraftInserter.hasPermission else { self.message(DraftInsertionError.permission.localizedDescription, error: true); self.updatePermissionButton(); return }
                    guard let target else { self.message(DraftInsertionError.focus.localizedDescription, error: true); return }
                    let lease = PasteLease(operation: token, clipboardChangeCount: NSPasteboard.general.changeCount)
                    self.panel.orderOut(nil)
                    DraftInserter.insert(target: target, lease: lease, currentOperation: { [weak self] in self?.operation ?? UUID() }) { [weak self] error in
                        guard let self, self.operation == token else { return }
                        if let error { self.showWindow(nil); self.message(error.localizedDescription, error: true) }
                        else { self.message("已执行粘贴，请在飞书预览图片并自行发送。") }
                    }
                } catch { self.message(error.localizedDescription, error: true) }
            }
        }
    }
    private func save(_ image: ImagePayload) {
        let dialog = NSSavePanel(); dialog.title = "搜图酱 · 保存原图"
        dialog.nameFieldStringValue = "搜图酱-\(Int(Date().timeIntervalSince1970)).\(image.fileExtension)"
        dialog.allowedContentTypes = [UTType(filenameExtension: image.fileExtension) ?? .image]
        dialog.canCreateDirectories = true
        dialog.beginSheetModal(for: panel) { [weak self] response in
            guard response == .OK, let url = dialog.url else { return }
            do { try image.data.write(to: url, options: .atomic); self?.message("已保存原文件：\(url.lastPathComponent)，也可拖入飞书聊天。") }
            catch { self?.message("保存失败：\(error.localizedDescription)", error: true) }
        }
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if webView === searchPage, activeNavigation != nil, navigation === activeNavigation { let token = searchToken; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.extract(attempt: 0, token: token) } }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === grid {
            gridReady = true
            if let (function, value) = pendingRender { pendingRender = nil; render(function, value) }
        } else if activeNavigation != nil, navigation === activeNavigation { extract(attempt: 0, token: searchToken) }
    }
    private func failed(_ error: Error, webView: WKWebView) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        if webView === searchPage {
            let text = "搜索加载失败：\(error.localizedDescription)。可重试、切换搜索网站或在浏览器打开。"
            loadedToken = searchToken; render("showNotice", text); message(text, error: true)
        } else { message("结果界面加载失败，请重新打开搜图酱。", error: true) }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView === grid || (activeNavigation != nil && navigation === activeNavigation) { failed(error, webView: webView) }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === grid || (activeNavigation != nil && navigation === activeNavigation) { failed(error, webView: webView) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === grid { gridReady = false; webView.reload() }
        else { message("搜索页面已停止，请点击“重试搜索”。", error: true) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if webView === grid {
            let expected = resource("grid", "html")?.standardizedFileURL
            decisionHandler(url.standardizedFileURL == expected || url.absoluteString == "about:blank" ? .allow : .cancel)
        } else { decisionHandler(ImageURL.validated(url.absoluteString) != nil || url.absoluteString == "about:blank" ? .allow : .cancel) }
    }
}
