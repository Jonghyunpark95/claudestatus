#!/bin/bash
#
# ClaudeMascot.app 빌드 — swiftc 로 한 파일을 컴파일해서 .app 번들로 조립한다.
# Xcode 는 필요 없고 Command Line Tools 만 있으면 된다.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
APP="$ROOT/ClaudeMascot.app"
PORT="${MASCOT_PORT:-4573}"

NODE_BIN="$(command -v node || true)"
if [ -z "$NODE_BIN" ]; then
  echo "! node 를 찾지 못했습니다. 앱이 서버를 자동으로 못 띄웁니다 (수동 실행은 가능)."
fi

echo "빌드 중…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# ---------------------------------------------------------------- Info.plist
# MascotRoot / MascotNode 는 앱이 서버를 자동 실행할 때 쓰는 경로다.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ClaudeMascot</string>
  <key>CFBundleDisplayName</key><string>Claude 마스코트</string>
  <key>CFBundleIdentifier</key><string>com.claudemascot.pet</string>
  <key>CFBundleExecutable</key><string>ClaudeMascot</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>

  <!-- Dock 아이콘 없이 메뉴바에서만 산다 -->
  <key>LSUIElement</key><true/>

  <key>MascotRoot</key><string>${ROOT}</string>
  <key>MascotNode</key><string>${NODE_BIN}</string>
  <key>MascotPort</key><string>${PORT}</string>

  <!-- 로컬 서버(http://127.0.0.1)만 예외로 허용 -->
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSExceptionDomains</key>
    <dict>
      <key>127.0.0.1</key>
      <dict>
        <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
      </dict>
    </dict>
  </dict>
</dict>
</plist>
PLIST

# ---------------------------------------------------------------- 컴파일
swiftc -O \
  -target "$(uname -m)-apple-macosx12.0" \
  -framework Cocoa -framework WebKit \
  -o "$APP/Contents/MacOS/ClaudeMascot" \
  "$HERE/ClaudeMascot.swift"

# 로컬 서명 (서명이 없으면 일부 macOS 버전에서 실행이 막힌다)
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✓ 빌드 완료: $APP"
echo ""
echo "실행:  open \"$APP\""
echo "      (메뉴바 오른쪽에 아이콘이 생기고, 바탕화면 오른쪽 아래에 캐릭터가 뜹니다)"
