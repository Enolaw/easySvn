#!/usr/bin/env bash
# easySvn beta 打包脚本：构建 release 可执行文件并组装 .app + zip + dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-0.5.0-beta}"
APP_NAME="easySvn"
BUNDLE_ID="com.easysvn.app"
DIST_DIR="dist"
MIN_MACOS="13.0"
ICON_FILE="${ROOT}/Assets/AppIcon.icns"
ICON_PLIST_ENTRY=""

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "==> easySvn 打包 v${VERSION}"
echo "    DEVELOPER_DIR=${DEVELOPER_DIR}"

echo "==> 运行测试..."
swift test

echo "==> 构建 Release..."
swift build -c release

ARCH="$(uname -m)"
BUILD_DIR=".build/${ARCH}-apple-macosx/release"
BINARY="${BUILD_DIR}/EasySvnApp"

if [[ ! -f "${BINARY}" ]]; then
  BINARY="$(find .build -path '*/release/EasySvnApp' -type f | head -1)"
fi
if [[ ! -f "${BINARY}" ]]; then
  echo "错误：找不到 Release 可执行文件" >&2
  exit 1
fi

APP_PATH="${DIST_DIR}/${APP_NAME}.app"
rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS"
mkdir -p "${APP_PATH}/Contents/Resources"

cp "${BINARY}" "${APP_PATH}/Contents/MacOS/EasySvnApp"
chmod +x "${APP_PATH}/Contents/MacOS/EasySvnApp"

if [[ -f "${ICON_FILE}" ]]; then
  cp "${ICON_FILE}" "${APP_PATH}/Contents/Resources/AppIcon.icns"
  ICON_PLIST_ENTRY=$'    <key>CFBundleIconFile</key>\n    <string>AppIcon</string>\n'
  echo "==> 已包含应用图标"
else
  echo "==> 未找到 Assets/AppIcon.icns，将使用系统默认图标"
  echo "    可运行 ./scripts/generate-icon.sh 生成（需先准备 Assets/icon-1024.png）"
fi

BUILD_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
cat > "${APP_PATH}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hans</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>EasySvnApp</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
${ICON_PLIST_ENTRY}    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "==> 签名（ad-hoc）..."
codesign --force --sign - --deep "${APP_PATH}"

ARCHIVE="${DIST_DIR}/${APP_NAME}-${VERSION}-macos-${ARCH}.zip"
rm -f "${ARCHIVE}"
ditto -c -k --keepParent "${APP_PATH}" "${ARCHIVE}"

echo "==> 生成 DMG..."
DMG_STAGING="${DIST_DIR}/.dmg-staging"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}-macos-${ARCH}.dmg"
rm -rf "${DMG_STAGING}" "${DMG_PATH}"
mkdir -p "${DMG_STAGING}"
ditto "${APP_PATH}" "${DMG_STAGING}/${APP_NAME}.app"
ln -s /Applications "${DMG_STAGING}/Applications"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_STAGING}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" >/dev/null
rm -rf "${DMG_STAGING}"

echo ""
echo "打包完成："
echo "  App:  ${APP_PATH}"
echo "  Zip:  ${ARCHIVE}"
echo "  Dmg:  ${DMG_PATH}"
echo "  构建: ${BUILD_DATE}"
echo ""
echo "使用前请确保已安装 Subversion：brew install subversion"
