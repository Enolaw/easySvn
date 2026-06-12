# easySvn

macOS 原生 SVN 图形化客户端（开发中），对标 Windows 平台的 TortoiseSVN。

## 文档

- [需求说明书](docs/需求说明书.md)
- [开发计划](docs/开发计划.md)

## 项目结构

```
easySvn/
├── Package.swift              # Swift Package 清单
├── Sources/SvnKit/            # SVN 引擎层（封装 svn 命令行）
│   ├── ProcessRunner.swift    # 异步子进程执行器（支持取消）
│   ├── SvnBinaryLocator.swift # svn/svnadmin 可执行文件探测
│   ├── SvnClient.swift        # SVN 命令封装（status/info/checkout/commit/...）
│   ├── SvnError.swift         # 错误归一化（解析 svn 错误码）
│   ├── Models/                # 数据模型（SvnStatusEntry、SvnInfo）
│   └── Parsers/               # --xml 输出解析器
├── Tests/SvnKitTests/         # 单元测试 + 基于本地 file:// 仓库的集成测试
└── docs/                      # 需求与计划文档
```

后续里程碑将在此基础上添加 SwiftUI App target 与 FinderSync 扩展。

## 环境要求

- macOS 13+，Xcode 16+（需要完整版 Xcode，Swift Testing 依赖）
- Subversion 命令行工具：`brew install subversion`

## 构建与测试

```bash
# 如果 xcode-select 指向 CommandLineTools，需要指定 DEVELOPER_DIR
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

swift build
swift test
```

集成测试会用 `svnadmin` 在临时目录创建本地 `file://` 仓库，不依赖网络。
可通过环境变量 `EASYSVN_TEST_TMP` 指定测试临时目录。

## 当前进度

- [x] M1：SVN 引擎层第一个闭环（进程执行器 + status/info XML 解析 + 基本命令 + 17 项测试）
- [ ] M1：引擎层补全（log / diff / 认证 / 错误兼容）
- [ ] M2：MVP 界面（工作副本管理、状态视图、提交、日志）
