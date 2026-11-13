# 参考资料

2026-11-12 按用户授权联网检索。实现独立编写，没有复制第三方库源码，没有引入第三方包。

- [soffes/HotKey](https://github.com/soffes/HotKey)：查阅 `Sources/HotKey/HotKeysController.swift` 中 Carbon 快捷键注册、事件分发、注销的结构；项目 MIT 许可。
- [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)：查阅全局快捷键功能与接口设计；本工具仅需一个固定快捷键，因此没有引入整库。
- [Apple WKUserScript](https://developer.apple.com/documentation/webkit/wkuserscript)：网页选图事件监听。
- [Apple WKContentWorld](https://developer.apple.com/documentation/webkit/wkcontentworld)：选图脚本与远程页面脚本隔离。
- [Apple WKUserContentController](https://developer.apple.com/documentation/webkit/wkusercontentcontroller)：脚本消息桥。
- [Apple NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard)：静态图片数据与 GIF 原文件剪贴板。
- [飞书即时消息功能更新日志](https://www.feishu.cn/hc/zh-CN/articles/360049067485)：官方说明图片和视频可拖拽或粘贴到输入框。具体客户端与 GIF 行为仍需实测。

搜索结果来自必应／百度公开网页。结果、验证机制、原图站点可达性会随网站改变；工具保留网页原有操作和浏览器打开入口。

v1.1 的表情／热梗首选来源改为 [memecub REST API](https://memecub.com/developers)，参考其[公开项目说明](https://github.com/liyupi/memecub)。使用公开免密钥额度；不安装该项目的 Skill 或 MCP，不复制其源码。服务限额与更详细的图源比较见 [MEME-SOURCES.md](MEME-SOURCES.md)。
