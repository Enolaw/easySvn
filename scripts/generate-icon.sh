#!/usr/bin/env bash
# 将 Assets/icon-1024.png 转为 macOS AppIcon.icns
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${ROOT}/Assets/icon-1024.png"
ICONSET="${ROOT}/Assets/AppIcon.iconset"
OUTPUT="${ROOT}/Assets/AppIcon.icns"

if [[ ! -f "${SOURCE}" ]]; then
  echo "错误：找不到图标源文件 ${SOURCE}" >&2
  echo "请先放入一张 1024×1024 的 PNG，命名为 icon-1024.png" >&2
  exit 1
fi

WIDTH="$(sips -g pixelWidth "${SOURCE}" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
HEIGHT="$(sips -g pixelHeight "${SOURCE}" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
if [[ "${WIDTH}" != "1024" || "${HEIGHT}" != "1024" ]]; then
  echo "错误：icon-1024.png 必须是 1024×1024（当前 ${WIDTH}×${HEIGHT}）" >&2
  exit 1
fi

rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"

sips -z 16 16 "${SOURCE}" --out "${ICONSET}/icon_16x16.png" >/dev/null
sips -z 32 32 "${SOURCE}" --out "${ICONSET}/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "${SOURCE}" --out "${ICONSET}/icon_32x32.png" >/dev/null
sips -z 64 64 "${SOURCE}" --out "${ICONSET}/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "${SOURCE}" --out "${ICONSET}/icon_128x128.png" >/dev/null
sips -z 256 256 "${SOURCE}" --out "${ICONSET}/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "${SOURCE}" --out "${ICONSET}/icon_256x256.png" >/dev/null
sips -z 512 512 "${SOURCE}" --out "${ICONSET}/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "${SOURCE}" --out "${ICONSET}/icon_512x512.png" >/dev/null
cp "${SOURCE}" "${ICONSET}/icon_512x512@2x.png"

iconutil -c icns "${ICONSET}" -o "${OUTPUT}"
rm -rf "${ICONSET}"

echo "已生成：${OUTPUT}"
