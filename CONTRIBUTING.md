# 贡献指南

感谢你对 easySvn 的关注！欢迎通过 Issue 反馈问题、提出功能建议，或通过 Pull Request 提交代码。

## 开始之前

- 请先阅读 [README](README.md) 了解项目结构与运行方式
- Bug 修复可直接提 PR；较大功能建议先开 [Issue](https://github.com/Enolaw/easySvn/issues) 讨论

## 开发环境

- macOS 13+
- [Xcode 16+](https://developer.apple.com/xcode/)（Swift Testing 依赖完整 Xcode，Command Line Tools 不够）
- Subversion：`brew install subversion`

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build
swift test
```

集成测试会在临时目录创建本地 `file://` 仓库，不依赖网络。可通过环境变量 `EASYSVN_TEST_TMP` 指定临时目录。

## 提交 Pull Request

1. Fork 本仓库并创建分支（如 `fix/repo-browser-back-button`）
2. 修改代码并确保 `swift test` 全部通过
3. 提交信息用中文或英文均可，建议说明**为什么改**而不只列文件名
4. 向 `main` 分支发起 Pull Request，简要描述变更内容与测试情况

## 代码结构

| 目录 | 说明 |
|---|---|
| `Sources/SvnKit/` | SVN 命令封装、XML 解析、认证与 Keychain |
| `Sources/EasySvnApp/` | SwiftUI 界面、ViewModel、业务逻辑 |
| `Tests/SvnKitTests/` | 引擎层单元测试与集成测试 |
| `Tests/EasySvnAppTests/` | 应用层策略与工具类测试 |
| `docs/` | 需求、计划、更新说明 |
| `scripts/` | 打包与图标生成脚本 |

## 风格约定

- 与周围代码保持一致：命名、缩进、注释密度
- 只改与任务相关的文件，避免顺手重构无关代码
- 非显而易见的业务逻辑才加注释
- 测试中使用 `example.com`、`my-app` 等占位符，不要提交内网地址或真实项目名

## 打包验证（可选）

发布前可在本地验证打包：

```bash
./scripts/package.sh
```

## 反馈与讨论

- [GitHub Issues](https://github.com/Enolaw/easySvn/issues) — Bug 报告、功能请求
- [更新说明](docs/CHANGELOG.md) — 版本变更记录

## 许可证

贡献的代码将按项目的 [MIT 许可证](LICENSE) 发布。
