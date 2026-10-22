# TidyNest M1 Implementation Plan

> 本文为历史阶段计划与当时的验收记录，任务指令和待办不代表当前工作要求。当前协作规则见 [AGENTS.md](../AGENTS.md)，后续验收见 [历史验收记录](verification-history.md)；旧行为、测试结果及操作授权均限于对应记录时点。

**Goal:** 交付可以从 Finder 打开的本地原生 App，完成依赖检测、应用列表和目录查询。

**Architecture:** SwiftUI/AppKit 界面通过 TidyNestCore 查询本机 Mole。Core 分别读取 stdout/stderr，严格解析 JSON，异步支持取消。没有破坏性命令入口。

**Tech Stack:** Swift 6、SwiftUI、AppKit、Foundation、Swift Package Manager、系统自带工具。

**Spec:** `docs/design.md`；本文只实施该设计的 M1。

## Global Constraints

- macOS 14+；只使用系统框架，不引入外部包依赖。
- 中文界面，项目名 TidyNest；目录 tidy-nest。
- 2026-09-08 加载调整：启动恢复上次应用列表并检测依赖，不自动读取；磁盘仍需用户选择目录。
- 允许调用的 Mole 命令只有 --version、uninstall --list、analyze --json <目录>。
- 不清理、不卸载、不运行 dry-run、不自动安装或更新依赖、不提权。
- 参数通过独立 argv 数组传递；不拼接 shell 字符串。M1 使用 posix_spawn 显式建立进程组，并在最后回收前保留子进程 PID，确保取消只影响本次查询。
- 先基于本机 1.53.0 验证查询；不认识的版本明确标注并阻止未验证查询。
- 子进程须同时消费 stdout/stderr，避免管道阻塞；取消不能使过期结果覆盖新状态。
- App 包仅放项目 build 目录，不安装到 /Applications；本地 ad-hoc 签名不等于正式发行签名。

## Task 1: 查询核心与行为测试

文件：`Sources/TidyNestCore/MoleModels.swift`、`MoleService.swift`、`ProcessRunner.swift`；测试放 `Tests/TidyNestCoreTests/`。

对外接口（类型名与签名保持一致）：

```swift
public struct MoleInstallation: Sendable, Equatable {
    public let executableURL: URL
    public let version: String
    public var isSupported: Bool { /* 语义：已验证的 1.53.0 */ }
}
public struct MoleApplication: Identifiable, Sendable, Hashable {
    public let name: String
    public let bundleIdentifier: String
    public let source: String
    public let uninstallName: String
    public let path: String
    public let displaySize: String
    public var id: String { path }
}
public struct MoleDiskEntry: Identifiable, Sendable, Hashable {
    public let name: String
    public let path: String
    public let size: UInt64
    public let isDirectory: Bool
    public var id: String { path }
}
public struct MoleDiskReport: Sendable {
    public let path: String
    public let overview: Bool
    public let entries: [MoleDiskEntry]
    public let largeFiles: [MoleDiskEntry]
    public let totalSize: UInt64
    public let totalFiles: UInt64
}
public struct MoleService: Sendable {
    public init()
    public func detect() async throws -> MoleInstallation
    public func applications(using installation: MoleInstallation) async throws -> [MoleApplication]
    public func analyze(directory: URL, using installation: MoleInstallation) async throws -> MoleDiskReport
}
```

以上是接口契约，不是可复制的空实现。实现者应按测试编写完整代码。

- [x] 先写测试，验证缺省 large_files、错误 JSON、同名不同路径应用、非零退出状态、字面参数传递与取消；记录预期失败。
- [x] 使用手写小型 JSON fixture；例如应用记录：`{"name":"Example","bundle_id":"com.example.app","source":"App","uninstall_name":"Example","path":"/Applications/Example.app","size":"24 MB"}`。
- [x] 磁盘 fixture：`{"path":"/tmp/example","overview":false,"entries":[{"name":"notes.txt","path":"/tmp/example/notes.txt","size":12,"is_dir":false}],"total_size":12,"total_files":1}`；预期 largeFiles 为空、文件大小 12。
- [x] ProcessRunner 测试使用系统命令与临时测试脚本，不运行个人目录扫描或破坏性 Mole 命令。检验 stderr 大输出不死锁、取消能返回且进程退出。
- [x] 实现：明确检查 /opt/homebrew/bin/mole、/usr/local/bin/mole、当前用户 .local/bin/mole；解析版本；查询前核对兼容性。
- [x] 错误提供可理解的中文 LocalizedError；保留必要诊断，但不直接把任意控制字符作为 UI 输出。
- [x] 运行 `rtk proxy swift test`，记录实际通过结果与任何限制。

## Task 2: 原生窗口与查询状态

文件：`Sources/TidyNest/TidyNestApp.swift`、`WorkspaceModel.swift`、`RootView.swift`、`ApplicationsView.swift`、`DiskView.swift`、`SettingsView.swift`。只创建需要的文件，不为单次逻辑再拆抽象。

消费 Task 1 接口。界面至少包括：

- 应用与磁盘两个真实入口，侧栏底部有 Mole 连接状态；不放未实现的清理入口或虚假数据。
- 应用页：手动读取/刷新、上次列表恢复、名称搜索、列表与详情；同名应用用路径区分；来源、bundle ID、大小、Finder 定位。
- 磁盘页：NSOpenPanel 选择目录、查询、按大小排序的列表、目录下钻、返回上层、Finder 定位；显示真实统计。
- 启动只检测 Mole 并恢复上次列表；手动点击读取或刷新后才查询。无缓存时查询显示读取进度；有缓存或手动刷新时保留旧列表和选中项，显示更新时间、更新状态和取消按钮。成功空列表同样保存；错误与取消不覆盖快照。旧列表须等本次查询成功后才能发起移除计划检查。
- Task 取消后检查任务身份，防止旧结果覆盖页面；查询中禁用冲突操作。
- 设置：路径、版本、支持状态与重新检测；无安装/更新按钮。
- 用户面对的说明只表达查询行为与当前能力，不显示内部协议名或实现 TODO。

验证：Core 测试通过后加入 executable target；编译；实际打开 App 检查布局和上述流程。数据或状态逻辑有非平凡分支时先写行为测试；纯布局通过原生界面核对。

## Task 3: 本地打包与集成验证

文件：`scripts/build-app.sh`、`Resources/Info.plist`，必要的图标生成资源；修改 `Package.swift` 加入 TidyNest executable product 与 target。

- [x] 用 SPM 构建 release。
- [x] 组装 `build/TidyNest.app/Contents/MacOS/TidyNest`、Info.plist 与资源；版本 0.1.0，固定本地 Bundle ID `local.tidynest.app`，最低系统 14.0。
- [x] 使用本地 ad-hoc 签名；不修改用户钥匙串或依赖签名设置。
- [x] 运行相关测试与完整构建，检查 App bundle 和签名结构。
- [x] 打开 App，通过原生 UI 验证 Mole 检测、应用列表、示例目录查询、搜索与系统文件管理器定位。本机定位交给用户配置的 QSpace，未修改此设置。
- [x] 最终独立代码审查，修复实际问题；在 AGENTS.md 记录已工作的构建与测试命令。

## 进度

- 目录已确认为空，无现有项目或 Git 仓库；直接使用用户指定目录。
- 查询核心与界面按以上明确接口分工；打包和整体验证由主代理负责。
- 完整设计是后续 M2/M3 的依据，本轮不会把 M1 完成描述为完整清理 App 完成。

## 2026-09-07 验收记录

- 最终 `swift test`：8 项 WorkspaceModelTests、24 项 MoleCoreTests，全部通过；Core 测试用时 5.806 秒。
- 最终 release 编译成功；`codesign --verify --strict --verbose=2 build/TidyNest.app` 返回 valid on disk / satisfies its Designated Requirement。
- 原生窗口读取本机 71 个应用；名称搜索返回正确子集，详情包含位置、来源、Bundle ID 和大小。取消显示独立状态，设置可重新检测。
- 原生目录选择器读取任务 fixture：114 字节、2 个文件；下钻「子目录 空格」后为 69 字节、1 个文件，返回上层恢复原结果。
- 真实 Mole 1.53.0 核验空目录省略 total_files，大文件记录不含 is_dir；解码已适配这些格式，普通 entries 仍严格要求 is_dir。
- 在故意设置 MO_ANALYZE_PATH 的隔离进程中，Core 读取空目录、小文件、大文件目录均返回正确目标，退出码 0；大文件 fixture 使用稀疏文件，实际占用约 2 MiB。
- 退出验收：开始读取后立即 Cmd-Q，只读进程观察记录本次 8 个查询相关进程；App 退出后本次查询进程与进程组均无遗留。
- 独立代码审查的实际问题已修复并复审通过：Finder PATH、进程组归属、退出等待、版本变化、JSON 边界、环境覆盖路径与候选路径校验。
- 测试过程限制：初始 UI 测试运行曾被尚未完成的 Core 符号和缺少 UI target 阻断，不能视为有效的行为 red；最终状态与退出行为测试均通过。
- 验证环境为 macOS 15.7.4 / Apple Silicon / Xcode 16.4 / Mole 1.53.0。最低 macOS 14 的 API 编译检查不等于实机验收；Intel、受隐私权限保护目录、正式分发签名与清理功能尚未验收。

## 2026-09-08 应用列表加载优化验收

- 启动恢复 `~/Library/Caches/TidyNest/applications.json` 中上次成功的快照并检测 Mole；按后续用户要求取消自动读取，只有手动点击读取或刷新后才查询。
- 手动刷新保留列表、搜索词和仍存在的选中项；失败/取消保留旧快照并注明状态和更新时间。空列表也是成功快照；损坏缓存自动回退到重新读取；缓存写入失败不会隐藏已取得的查询结果。
- 旧列表只用于浏览，本次查询成功前不开放移除计划检查。每次真实查询仍由 Core 核验固定 Mole 版本。
- 新增 15 项测试：6 项缓存、8 项应用模型、1 项安装恢复；全量默认实际执行 139 项并通过，3 项 opt-in 未启用。缓存测试仅使用 `work/` 下独立 fixture。
- release App 打包、严格签名与安装后主程序/桥接二进制一致性检查通过，已更新 `/Applications/TidyNest.app`，旧版保存在 `work/app-install-backups/`。
- 首次缓存版本的原生窗口验证（自动读取行为已在后续调整中取消）：首次无需点击自动加载 72 个应用；退出重开后在后台更新期间已展示这 72 项；更新中搜索可用，手动刷新保留选中详情，移除检查停用；取消后列表、搜索和详情保留。
- 未改变 Mole 自身完整扫描的耗时，未记录精确启动毫秒值；macOS 14 和 Intel 本次未验收。

## 2026-09-08 手动刷新调整验收

- 按后续用户要求取消所有自动应用列表查询：启动/返回页面仅恢复缓存，重新检测或安装 Mole 成功后也等待用户点击读取或刷新；无缓存或损坏缓存同样等待手动读取。
- 更新原有测试，不增加用例数量。启动禁止自动读取的用例先在旧实现失败；调整后 142 项默认测试通过，3 项 opt-in 未启用。缓存持久化、取消、失败、选择保留与维护互斥回归继续通过。
- release 打包、严格签名及安装后二进制一致性检查通过，已更新 `/Applications/TidyNest.app`。
- 原生窗口验证启动和切换到磁盘后返回应用页均显示上次 72 项列表，刷新按钮可用且没有更新进度；前后缓存摘要和修改时间一致。此次没有主动刷新真实列表。
