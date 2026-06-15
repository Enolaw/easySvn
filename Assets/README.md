# 应用图标

## 准备素材

准备一张 **1024×1024** 的 PNG，建议：

- 正方形、透明或纯色背景
- 图形居中，四周留一点边距（macOS 会自动裁圆角）
- 保存为 `Assets/icon-1024.png`

## 生成 .icns

```bash
./scripts/generate-icon.sh
```

会生成 `Assets/AppIcon.icns`，打包脚本会自动带入 `.app`。

## 重新打包

```bash
./scripts/package.sh
```

安装后的 `easySvn.app` 在 Finder、Dock、启动台会显示该图标。

> 用 `swift run EasySvnApp` 开发调试时不会显示自定义图标，只有打包后的 `.app` 才会。
