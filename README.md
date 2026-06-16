# easySvn

macOS 原生 SVN 图形化客户端（开发中），对标 Windows 平台的 TortoiseSVN。

## 文档

- [需求说明书](docs/需求说明书.md)
- [开发计划](docs/开发计划.md)
- [更新说明](docs/CHANGELOG.md)

## 项目结构

```
easySvn/
├── Package.swift              # Swift Package 清单
├── Sources/EasySvnApp/        # SwiftUI 图形界面（开发期可执行 target）
│   ├── Models/ Stores/        # 工作副本书签与持久化
│   ├── ViewModels/            # 状态加载
│   └── Views/                 # 侧边栏 + 状态列表
├── Sources/SvnKit/            # SVN 引擎层（封装 svn 命令行）
│   ├── ProcessRunner.swift    # 异步子进程执行器（支持取消）
│   ├── SvnBinaryLocator.swift # svn/svnadmin 可执行文件探测
│   ├── SvnClient.swift        # SVN 命令封装（status/info/log/list/commit/...）
│   ├── SvnError.swift         # 错误归一化（解析 svn 错误码）
│   ├── Auth/                  # 认证选项注入 + Keychain 凭据存储
│   ├── Models/                # 数据模型（SvnStatusEntry、SvnInfo、SvnLogEntry、SvnListEntry）
│   └── Parsers/               # --xml 输出解析器
├── Tests/SvnKitTests/         # 单元测试 + 基于本地 file:// 仓库的集成测试
└── docs/                      # 需求与计划文档
```

后续将优先推进冲突解决、分支合并、仓库浏览器（M3）；Finder 集成延后至 M4，届时再迁移至 Xcode App target。

## 环境要求

- macOS 13+，Xcode 16+（需要完整版 Xcode，Swift Testing 依赖）
- Subversion 命令行工具：`brew install subversion`

## 运行图形界面

```bash
# 如果 xcode-select 指向 CommandLineTools，需要指定 DEVELOPER_DIR
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

swift run EasySvnApp
```

或用 Xcode 打开（`open Package.swift -a Xcode`），选择 `EasySvnApp` scheme 后按 ⌘R。

窗口打开后点击左下角「检出…」可从远程仓库检出，或「添加工作副本」选择已有本地目录。连接需认证的服务器时会提示输入凭据（可保存到钥匙串）。变更列表支持 FSEvents 自动刷新（可在设置中关闭）。

## 构建与测试

```bash
swift build
swift test
```

集成测试会用 `svnadmin` 在临时目录创建本地 `file://` 仓库，不依赖网络。
可通过环境变量 `EASYSVN_TEST_TMP` 指定测试临时目录。

## 当前进度

- [x] M1：SVN 引擎层第一个闭环（进程执行器 + status/info XML 解析 + 基本命令）
- [x] M1：引擎层补全（log/list 解析、diff/cat/export/delete/move/cleanup、认证注入、Keychain 凭据存储），29 项测试
- [x] M2：最小可运行界面（侧边栏工作副本书签 + 文件状态列表，⌘R 刷新）
- [x] M2：Update / Commit / Revert、按状态排序、未版本控制/缺失批量操作、全选、URL 中文解码
- [x] M2：Diff 视图（双击/右键查看本地差异）、日志查看器（分页、搜索、变更文件 diff）
- [x] M2：Checkout 向导、认证设置、FSEvents 自动刷新（**M2 / v0.1 alpha 完成**）
- [x] M3：冲突解决（冲突列表、三方合并、快捷 resolve、树冲突信息）
- [x] M3：分支与合并（创建分支/标签、Switch、Merge 向导、mergeinfo）
- [x] M3：仓库浏览器（懒加载目录树、远程 CRUD、文件预览/日志、从此处检出）
- [x] M3：体验补全 + v0.5 beta（**v0.5.1** 已发布，见 [更新说明](docs/CHANGELOG.md)）
- [ ] M4：Finder 集成（徽章 + 右键菜单，需 Xcode App target）

## 引擎层使用示例

```swift
import SvnKit

let client = try SvnClient.detect()
    .withCredentials(SvnCredentials(username: "alice", password: "***"))

let changes = try await client.status(at: workingCopyURL)   // 本地变更
let history = try await client.log(at: wcPath, limit: 100)  // 提交历史
let tree = try await client.list("https://svn.example.com/repo/trunk") // 远程浏览
```
