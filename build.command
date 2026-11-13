#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
cd "$PROJECT_DIR"
APP_DIR="$PROJECT_DIR/dist/搜图酱.app"
if pgrep -f "$APP_DIR/Contents/MacOS/FeishuImageHelper" >/dev/null 2>&1; then
  print -u2 "请先从菜单栏退出搜图酱，再重新构建，以免覆盖正在运行的应用。"
  exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
  print -u2 "重新构建需要 Apple Command Line Tools；已有的 dist/搜图酱.app 可直接双击使用。"
  exit 1
fi
swift build -c release --product FeishuImageHelper
PRODUCT_DIR="$(swift build -c release --show-bin-path)"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PRODUCT_DIR/FeishuImageHelper" "$APP_DIR/Contents/MacOS/FeishuImageHelper"
ditto "$PRODUCT_DIR/FeishuImageHelper_FeishuImageHelper.bundle" "$APP_DIR/Contents/Resources/FeishuImageHelper_FeishuImageHelper.bundle"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>搜图酱</string>
<key>CFBundleDisplayName</key><string>搜图酱</string>
<key>CFBundleExecutable</key><string>FeishuImageHelper</string>
<key>CFBundleIdentifier</key><string>local.wude.Soutujiang</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PLIST
codesign --force --sign - "$APP_DIR"
print "已构建：$APP_DIR"
