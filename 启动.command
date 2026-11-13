#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
APP_DIR="$PROJECT_DIR/dist/搜图酱.app"
if [[ ! -x "$APP_DIR/Contents/MacOS/FeishuImageHelper" ]]; then
  "$PROJECT_DIR/build.command"
fi
open "$APP_DIR"
