# 验证记录

日期：2026-11-12。开发机器：Apple Silicon Mac，使用 Command Line Tools 构建 macOS 13+ 应用。

## 已验证

- Release 应用构建成功；Info.plist 校验和本机 ad-hoc 签名校验通过。
- 临时移走开发目录中的 Release 资源 bundle 后，独立 `.app` 仍能启动并从自身 `Contents/Resources` 读取界面，避免依赖开发机器路径。
- 核心与本机真实 HTTP 集成检查 **43/43 通过**，覆盖搜索词中文与特殊符号、空查询、HTTP/HTTPS URL 限制、静态图片剪贴板、原 GIF 文件保留、EXIF 方向、错误响应、伪图片、超大下载、重定向、旧搜索拒绝、剪贴板变化及取消操作。
- 真实必应图片可显示表情包、GIF、普通图片搜索结果。直接图片网格已取得并展示图片。
- 从真实在线结果成功复制 JPEG 与原 GIF 文件。
- Control + Option + 空格可收起并重新唤出搜图酱；Command + Option + 空格是系统访达搜索，需区分 Control 与 Command。
- 开发期间用户授予辅助功能后，旧版一键粘贴路径已执行；所有版本均没有发送消息动作。
- 追加了最终版的原输入框／窗口／会话标题绑定，粘贴前再次检查操作令牌及剪贴板版本。不能确认目标时回退到手动粘贴。

## 限制

- 重新构建并更换 ad-hoc 签名后，macOS 本机授权可能需要重新开启；最终版严格目标绑定下的一键粘贴，需在权限有效且飞书聊天输入框有焦点时使用。不能用核心测试代替真实飞书 UI 验证。
- 当前百度图片触发安全验证，因此默认使用已实测可访问的必应。不绕过验证码。
- 部分原图站点有防盗链、TLS 问题或访问限制；失败时保留来源入口，不静默替换成另一张图片。
- GIF 分类中如果站点实际返回静态图，会明确拒绝自动粘贴，避免用缩略图冒充动画。
- 图片结果来自公开网页，页面结构变化可能使提取暂时不可用。可以重试、换关键词或在浏览器打开搜索结果。
- 当前构建只包含 Apple Silicon 架构，没有进行 Intel Mac、其他 macOS 版本或飞书企业策略的跨机器验收。

## 运行开发检查

```sh
swift run CoreChecks
python3 Tests/network_checks.py
./build.command
codesign --verify --deep --strict dist/搜图酱.app
plutil -lint dist/搜图酱.app/Contents/Info.plist
```

系统没有 XCTest 模块，因此采用可直接运行的 Swift 检查程序；HTTP 检查仅用 Python 标准库和本机临时服务。所有检查均调用实际交付的 Core 代码。
