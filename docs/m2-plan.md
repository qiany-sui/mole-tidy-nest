# TidyNest M2 Implementation Plan

> 本文为历史阶段计划与当时的验收记录，任务指令和待办不代表当前工作要求。当前协作规则见 [AGENTS.md](../AGENTS.md)，后续验收见 [历史验收记录](verification-history.md)；旧行为、测试结果及操作授权均限于对应记录时点。

**Goal:** 在原生 App 中交付可检查的缓存清理及普通应用移除计划、逐项移入废纸篓、取消和本地结果记录。

**Architecture:** 固定 Mole 1.53.0 的规则与保护算法子集，移植为独立 Swift 引擎。App 通过 stdin JSON / stdout NDJSON 调用随包构建的 TidyNestBridge；引擎保存计划、再次校验、持锁执行，原版 Mole 仅提供已验证查询。

**Tech Stack:** Swift 6、SwiftUI、AppKit、Foundation、CryptoKit、Darwin、SPM；无外部依赖。

**Spec:** `docs/design.md`。本文细化 M2 的首批动作，不替代 M1 或承诺全部 Mole 功能。

## Global Constraints

- macOS 14+，先验证本机 macOS 15.7.4 / Apple Silicon / Mole 1.53.0。
- 中文界面、注释解释原因；沿用现有绿色浅深色布局，不加假数据或无实现按钮。
- M2 实施时仅在当前项目工作，当时无 Git 仓库，不初始化、不提交、不发布；2026-09-08 后的本地 Git 与发布约定见 `AGENTS.md`。
- shell 使用 `rtk` 前缀；文件改动按模块分工，测试构建协调串行。
- 不替换用户的 mole/mo、不调用 clean/uninstall 执行、dry-run、sudo、zap、autoremove 或强退其他 App。
- 首批动作仅 `trashItem`；没有永久删除、清空废纸篓、跨卷复制后删除或清空整个缓存目录。
- 自动化只处理本任务新建隔离 fixture；真实个人缓存和已安装 App 不作删除测试。
- Mole 派生材料保留 GPL 原文、固定版本来源及移植差异。原始 shell 只作审计材料，不执行。
- 所有首批缓存和日志候选都是明确枚举的普通文件，默认不勾选。应用本体是执行卸载计划的必选项，界面可取消勾选并清除依赖选择；未选本体不能确认，残留依赖本体确定成功。
- 系统组件、其他 Apple 应用、Homebrew、厂商专用卸载器、共享容器、偏好域、编译模型、普通缓存/日志硬链接、目标或祖先符号链接均不进入首批动作。Xcode 本体按精确路径作为 Apple 应用的特例，开发数据继续保留。

## 已确认的实现边界

Mole 的通用 cache/log 两条规则可以收窄，完整 clean/uninstall 运行时不能成为逐项执行器。真正复用的内容为 bundle 保护数据、bundle 匹配、用户白名单及硬保护语义、Deno/模型保护及敏感状态风险识别；运行状态、快照与执行由 Swift 实现。来源材料放 `Sources/TidyNestEngine/Resources/MoleUpstream`，引擎读取其中的固定保护数组。

初始范围只处理 `~/Library/Caches/<完整 bundle ID>` 和 `~/Library/Logs/<完整 bundle ID>`，owner 必须是在下述支持安装范围内可精确识别、安装集合未变化的唯一普通 App。扫描未知归属目录时展示跳过原因，不推测可清理。应用本体路径仅允许已检测安装列表中的 `/Applications` 或 `~/Applications` 内普通 `.app`；残留仍限上述 Cache/Logs 内逐个文件。应用已缺失时不把未知目录推测为孤立残留。

2026-09-08：规则版本更新为 `mole-1.53.0-subset-2`。普通应用本体由所选路径、当前 Bundle ID 与完整包快照定位，多副本不再阻止该本体的移除计划；同标识的缓存与日志不纳入计划，执行前也拒绝这类文件项。Xcode 仅开放本体移除，其他 Apple 应用和 Xcode 开发数据仍保留。应用包及其成员可由当前用户或 root 拥有，组写例外仅限 root:wheel，仍拒绝全员写入和特殊模式。包内普通硬链接必须按同卷 inode 完整配齐，链接计数及身份一致；包外硬链接和包外符号链接继续拒绝。普通缓存/日志仍限当前用户且无硬链接。成员身份字段（含属组）与路径用固定顺序数组无损编码，未提高 32 MiB 上限；原位、暂存和 Trash 均完整复验，估算体积按 inode 去重。系统目录范围、父链、同卷、运行状态与安装集合复核继续生效，实际移动受系统权限约束，不修改权限、不使用 sudo。

本轮验收：177 项默认测试通过（3 项 opt-in 未启用），release 与已安装 App 严格签名通过。隔离执行验证多副本本体选择、共享数据保留、内部硬链接整包移动、执行前包外链接变化与 gid 身份保护。真实 `/Applications/Xcode.app` 仅做只读快照，135,501 个成员、29,629,273 字节记录完整保存/读回并再次匹配；原生计划仍因 Raycast、QSpace Pro 的真实文件占用被保留，释放占用后勾选结果待验收。未对真实应用执行移除，root 属主包的系统 Trash 移动尚未验收。

2026-09-08 占用检查增量：规则版本更新为 `mole-1.53.0-subset-4`。诊断区分应用/后台进程运行与外部访问，显示名称、PID、读写/映射/目录类型及具体路径。仅整包本体放行已确认外部进程的数字描述符、只读、无锁 REG 文件；DIR 句柄仍能通过 openat 写成员，继续保留。可写、锁、txt/mem 映射、未知进程或不完整记录继续阻止处理，缓存/日志不放宽。lsof NUL 字段完整解析后再分类，转义按字节只解码一次，再核对路径范围；不依赖启动时的 locale。计划页增加「重新检查此应用」，沿用精确目标、清除旧计划/选择/确认，保留忙碌与退出互斥；不自动关闭进程或重试执行。

2026-09-08 包装应用增量：规则版本为 `mole-1.53.0-subset-3`。已知 `WrappedBundle → Wrapper/<名称>.app` 布局开放整个外层应用包的移除，不跟随包装链接授权额外路径。唯一安装可列出全局精确 Bundle ID 缓存/日志；另增加 `tidynest.container-cache.exact-file.v1` 和 `tidynest.container-log.exact-file.v1`，只授权有界、无链接、完整唯一归属元数据对应容器内的 `Data/Library/Caches`、`Data/Library/Logs` 普通文件。Documents、Application Support、Preferences、tmp、共享容器与容器根/元数据保留。无法完整读取 Containers 直属归属信息或存在重复 ID 时保留容器数据，独立核验通过的应用本体仍可处理。全部正/负匹配的元数据证据均须复核；选中容器项时在接受执行前、实际移动前和 Trash 前重验归属。已暂存的当前项完成复验与记账，正常取消停止后续项。

2026-09-11 可选数据库增量：经用户明确要求，规则版本更新为 `mole-1.53.0-subset-5`。现有缓存/日志范围内，数据库扩展名、SQLite 文件头及会话、Cookie、凭据等内容风险不再强制排除，改为默认不勾选的普通文件候选；操作影响在详情和最终确认中显示，说明可能退出登录、丢失本地状态或出现应用异常，并提示核对数据库配套文件。移除只处理已选 ID，不自动选取配套文件。原有目录范围、安装及容器唯一归属、应用保护、编译模型、长期保护、白名单、占用、快照、权限、链接和同卷核验不变；旧计划须重新生成。

安装唯一归属核验合并 Mole 已观测列表，并完整检查固定 Mole 的 8 个安装根目录：`/Applications`、`~/Applications`、`/System/Applications`、`/Library/Input Methods`、`~/Library/Input Methods`、`~/Library/Application Support/Setapp/Applications`、`/opt/homebrew/Caskroom`、`/usr/local/Caskroom`，另检查 `/Volumes`。不自动扫描桌面或下载目录，不因额外扫描申请或绕过隐私权限。范围内任何读取失败都会使计划不完整；唯一归属结论仅覆盖这一支持范围，运行中同 bundle ID 检查不能证明范围外不存在未启动的应用副本。

App 包内部链接按 `lstat + readlink` 记录链接对象，不跟随；只接受指向包内部的相对链接。顶层/祖先链接和指向包外的链接阻止执行。这项细化使普通 Framework 包能被审查，同时保持链接不扩展执行范围。

同卷私有 staging 使用 `~/Library/Application Support/TidyNest/Engine/Transactions/<runID>/<itemID>/<basename>`。目录首次创建 0700，计划/日志 0600；已有不安全目录拒绝使用，不自动 chmod。执行时逐组件 `openat(O_NOFOLLOW|O_DIRECTORY)` 固定父链，核对身份，以 `renameatx_np(..., RENAME_EXCL)` 移至 staging，复验对象/成员，再调用系统 Trash。复验失败或 Trash 失败时，只在原位置不存在的前提下 EXCL 恢复；冲突则保留 staging 并报告具体位置，绝不覆盖。

该顺序不提供源 inode 条件 rename，也不冻结已有 fd 写者。预检与 rename、复验与 Trash 仍有竞态窗口；专项测试验证可检测的变化、恢复及待核对结果，不宣称完全消除并发风险。同 UID 恶意修改私有引擎目录、root 干预不属于本工具可隔离的安全边界。跨卷、无法核验的共享/活跃状态或权限不完整时保留目标。

## 公共模块与接口契约

新增 `TidyNestProtocol`（只有 Codable/Sendable 数据和校验），`TidyNestEngine`（规则、扫描、存储、执行），`TidyNestBridge`（固定 CLI 入口）。现有 `TidyNestCore` 增加桥接客户端，继续保留 M1 查询。

协议 JSON 编解码统一使用 `MaintenanceJSON.encoder()/decoder()`，日期使用 ISO8601。对外模型有完整 public initializer，字段使用 Swift camelCase，编码不做 snake_case 变换。

```swift
public enum MaintenanceKind: String, Codable, Sendable { case clean, uninstall }
public enum PlanSelection: String, Codable, Sendable { case optional, required, blocked }
public enum MaintenanceItemKind: String, Codable, Sendable { case file, application }
public enum MaintenanceAction: String, Codable, Sendable { case trashItem }
public enum MaintenanceStatus: String, Codable, Sendable { case completed, partial, cancelled, blocked, failed, unknown }
public enum ItemOutcome: String, Codable, Sendable { case trashed, skipped, failed, cancelled, unknown }
public enum MaintenanceEventKind: String, Codable, Sendable { case progress, candidate, itemResult, result }
```

数据记录（全部 Codable、Sendable；标明 ID 的类型同时 Identifiable，计划项目同时 Hashable）：

- `PlanIssue`: `path: String, reason: String`。
- `MaintenanceItem`: `itemID: String`（id）、`ruleID: String, path: String, displayName: String, kind: MaintenanceItemKind, action: MaintenanceAction, estimatedBytes: UInt64?, reason: String, impact: String, selection: PlanSelection, blockedReason: String?, dependsOnItemIDs: [String]`。
- `MaintenancePlan`: `schemaVersion: Int, planID: String`（id）、`runID: String, kind: MaintenanceKind, title: String, engineVersion: String, engineDigest: String, rulesVersion: String, configurationDigest: String, createdAt: Date, scopeRoots: [String], scanComplete: Bool, scanIssues: [PlanIssue], items: [MaintenanceItem]`。
- `MaintenanceItemResult`: `itemID: String`（id）、`path: String, outcome: ItemOutcome, reason: String?, trashPath: String?, retainedPath: String?, estimatedBytes: UInt64?`。
- `MaintenanceResult`: `planID: String, runID: String`（id）、`title: String, status: MaintenanceStatus, startedAt: Date, finishedAt: Date, items: [MaintenanceItemResult], selectedBytes: UInt64, trashedBytes: UInt64, freeBytesDelta: Int64?, message: String?`。
- `EngineCapabilities`: `schemaVersion: Int, engineVersion: String, engineDigest: String, rulesVersion: String, supportedRuleIDs: [String], supportedActions: [MaintenanceAction]`。
- `MaintenanceEvent`: `schemaVersion: Int, runID: String, sequence: Int, type: MaintenanceEventKind, message: String?, candidate: MaintenanceItem?, itemResult: MaintenanceItemResult?, plan: MaintenancePlan?, applyResult: MaintenanceResult?, error: String?`。
- `MaintenanceRequest`: `planID: String?, selectedItemIDs: [String]?, confirmed: Bool?, appPath: String?, expectedBundleID: String?, protectedPath: String?`，所有参数 init 默认 nil。

CLI 固定入口：`capabilities`、`list-apps`、`scan-clean`、`plan-uninstall`、`apply-plan`、`history`、`protections`、`protect-path`、`unprotect-path`。未知命令/字段/缺失必需输入拒绝，不支持传入任意计划文件、测试根目录或 shell 命令。`list-apps` 输出现有 Mole 列表等价 JSON。

查询入口输出一份 JSON。scan-clean/plan-uninstall/apply-plan 输出 NDJSON；schema=1、同一 runID、sequence 从 1 连续递增、恰好一个末尾 result；progress 至少报告阶段，不伪造百分比。候选事件可选，最终计划才可供确认。执行退出码 completed=0、partial=2、blocked=3、failed/unknown=4、cancelled=130。

请求、单条 NDJSON、查询响应和单个存储记录统一限制为 32 MiB，由共享协议常量定义。保存计划前检查编码大小，不能把超过存储上限的计划交给用户确认。客户端在发送前拒绝过大的请求；应用本体快照包含在私有计划中，不通过界面事件传输。接受前取消可以返回 cancelled＋空项目；接受后必须保留选中项目的最终结果或待核对状态。completed 必须非空且全部为 trashed，partial 必须同时包含成功与未成功项目，trashed 必须有系统返回的位置。

Core 客户端公共 API（类实例持有本次桥接进程控制状态；同一实例只允许一项活动请求）：

```swift
public final class MaintenanceService: Sendable {
    public init()
    public func capabilities() async throws -> EngineCapabilities
    public func scanClean(onEvent: @escaping @Sendable (MaintenanceEvent) -> Void) async throws -> MaintenancePlan
    public func planUninstall(application: MoleApplication, onEvent: @escaping @Sendable (MaintenanceEvent) -> Void) async throws -> MaintenancePlan
    public func apply(planID: String, selectedItemIDs: [String], onEvent: @escaping @Sendable (MaintenanceEvent) -> Void) async throws -> MaintenanceResult
    public func history() async throws -> [MaintenanceResult]
    public func protections() async throws -> [String]
    public func protect(path: String) async throws
    public func unprotect(path: String) async throws
    public func forceEndCurrentTask()
}
```

`apply` 仅由 UI 的最终确认操作调用，发送 confirmed=true；协议/引擎仍再次校验计划和选择。正常 Task cancellation 发一次 SIGINT，继续读取最终结果；scan 取消可抛 CancellationError，apply 必须保留返回 cancelled/partial 等结果。显式强制结束才 TERM，5 秒后 KILL，缺最终结果为 unknown。

## Task 1: 固定规则、计划与执行引擎

**Owner files:** `Sources/TidyNestProtocol/`、`Sources/TidyNestEngine/`（排除根代理负责的 Resources）、`Sources/TidyNestBridge/`、`Tests/TidyNestEngineTests/`。实现者先交付公共模型，告知其他任务接口可编译，再完成引擎。

**Consumes:** 上述协议、资源中的固定来源/保护数据、现有 MoleService 的 detect/applications；不得修改 Core 或 UI。

**Produces:** `public actor MaintenanceEngine` 及 `public init()`、`public func handle(command: String, request: MaintenanceRequest, emit: @escaping @Sendable (MaintenanceEvent) -> Void) async throws -> Data?`。查询返回编码 Data，流式入口通过 emit；可采用等价 CLI 内部调用划分，但不得改变外部协议。测试专用上下文 init 为 internal，通过 @testable 注入 fixture home/app roots/catalog/runtime/trash 操作；CLI 不暴露这些覆盖。

- [x] 建立并通过真实文件 fixture 测试：只选择 A 时 B 内容/存在性不变；scan 后新增 C 不加入动作；目标替换、父目录替换、SQLite、symlink、hardlink 与保护目录均保留。初版首次可运行时已通过，不声称每项初版功能都观察过行为红灯；后续边界修复有独立红绿证据。
- [x] 实现固定规则和保护读取：Mole 默认白名单/用户文件替换语义/硬安全合并，App 长期保护；最终配置和相关环境 DENO_DIR 摘要绑定计划，未知或不合法配置拒绝执行。
- [x] 枚举候选文件并保存精确 lstat/父链快照。目录成员完整清单包括相对路径、类型、dev/inode、owner/mode、大小、纳秒时间；包内链接不跟随。统计未知为 nil，扫描错误明确记录，不把不完整扫描授权执行。
- [x] 安装归属合并 Mole 已观测列表，完整复验上述固定 8 根及 `/Volumes`，每项执行前再次核验；唯一归属仅在支持范围内成立。可选残留仅 exact bundle ID Cache/Logs。范围内无法证明唯一或完整时，相关计划不可执行。
- [x] 执行前重新检测运行 App/包内 helper 和相关打开文件；除 subset-4 明确容忍的整包外部只读普通文件外，无法确认空闲时保留目标，已发生操作但结果不确定时显示 unknown，禁止 sudo。原版受保护 App/厂商管理应用不执行。测试注入的空闲状态仅在测试上下文。
- [x] 私有计划存储拒绝 symlink/非 owner/过宽权限；不接受外部计划文件。加载时验证 schema、引擎/规则/配置摘要及计划内所有路径、规则、选择/依赖约束。计划在执行 accepted 时标记已消费，重复 apply 拒绝。
- [x] `flock` 执行锁覆盖多个引擎进程。按选择集合逐项执行，App 必选且第一项；本体未确定成功，依赖残留全部跳过。正常取消只停止后续项，当前项完成记账。
- [x] fd-relative 同卷 staging / 移后复验 / EXCL恢复 / 系统Trash；所有结果包含真实Trash或保留位置。移动根ctime和父时间的已知变化与不允许的内容变化分别核验。最终 Trash 仅打开系统返回的具体对象，使用 `O_NOFOLLOW_ANY` 及完整成员核验，不要求枚举 Trash 父目录；source/staging 检查保持。
- [x] 事务日志 accepted → moveIntent → staged → trashIntent → succeeded，失败为 restored/needsReview；intent 同步成功才操作，真实结果同步后再发事件。计划、消费及最终记录原子发布；缺最终记录或单条损坏时恢复为 unknown，绝不自动重放。保留结果历史，不扫描整个用户Trash。
- [x] 测试未知ID、漏选必选/依赖、配置变化、重复执行、锁竞争、部分失败、取消、恢复冲突、App成员新增与运行状态变化；用可控注入在真实文件操作边界制造竞态，不以fake成功代替文件结果。
- [x] CLI 读取有上限的stdin JSON、输出串行编号事件；等待信号源注册就绪后启动引擎，取消只请求收尾，不在信号处理路径直接操作文件。正常调用不读取交互shell，资源/计划/协议错误提供中文原因。
- [x] 运行 engine 相关测试及完整测试，报告真实证据和仍存在的系统调用竞态边界。

## Task 2: 桥接客户端与流式进程

**Owner files:** `Sources/TidyNestCore/MaintenanceService.swift`、`BridgeProcessRunner.swift`、`Tests/TidyNestCoreTests/MaintenanceServiceTests.swift`；必要的小范围 `ProcessRunner.swift` 修改需先与根代理说明。

**Consumes:** TidyNestProtocol 公共模型与 CLI 契约。**Produces:** 上述 MaintenanceService 公共 API。

- [x] 建立并通过字节分段 NDJSON 测试：中文 UTF8 被切分、两个事件合并一块、无换行尾行、超长行、超过旧 1 MiB 上限但仍合法的计划、无result、重复/跳号/错runID、退出码与结果冲突均正确处理。
- [x] 只从 `Bundle.main.bundleURL/Contents/Helpers/TidyNestBridge` 解析真实执行器。内部测试 init 可以注入 fixture executable，公开 API 不暴露任意路径。
- [x] stdin 传结构化请求，stdout/stderr 同时消费且分别处理；未知协议不能从文字猜成功。序列/结果校验失败时保留必要诊断，apply 报unknown待核对，禁止自动重试。双管道使用 `Darwin.read` 并重试 EINTR；有界 gate 测试证明短 progress 在 final 产生前送达。
- [x] 复用已验证的 spawn独立组＋WNOWAIT所有权方式；正常取消SIGINT并等待，apply取消不能丢stdout。强制终止限本次未回收的进程组。
- [x] 真实脚本测试双管道、stdin字面字符串、非零业务退出仍可返回结果、合作取消和强制退出。没有测试个人文件或写用户Mole配置。
- [x] history/protections 路径与schema严格解码；所有调用串行防止同一service的活动进程引用被覆盖。
- [x] 通过包含 UI 状态模型的完整自动化测试，保持原来32项用例通过；真实界面执行验收另列。

## Task 3: 原生计划、确认和结果页面

**Owner files:** `Sources/TidyNest/` 与 `Tests/TidyNestUITests/`。**Consumes:** Core MaintenanceService、Protocol模型、现有WorkspaceModel和M1页面。

- [x] 建立并通过状态测试：扫描完成默认不选；本体默认选中但可取消，取消同步清除依赖和旧确认；blocked不选；确认后精确发送IDs；取消执行保留最终结果；新扫描/选择变化清除旧确认；记录失败不伪装成功。
- [x] 新增「清理」「操作记录」，保留现有应用/磁盘及深浅色。清理页主动扫描；实时显示阶段，最终按Cache/Logs分组、搜索、多选、路径/依据/影响/占用详情；未知占用独立处理。
- [x] 原应用详情新增「检查移除计划」，由真实路径及bundle ID生成计划；本体必选，可选残留逐文件，受保护原因可读。不显示“完整卸载”。
- [x] 确认sheet呈现准确目标清单与“移入废纸篓”的影响、总已选占用；最终明确按钮才调用apply。执行期间禁用冲突的M1/M2请求，不允许连续点击重复执行。
- [x] 实现逐项执行结果、cancelling 等待最终事件及强制结束二次提示；成功、部分、取消、被阻止、失败、待核对分别显示。状态模型及客户端测试通过，本轮专用 fixture 的真实执行和结果记录已验收；实际执行中取消/强制结束的窗口路径另列限制。
- [x] 结果展示已移动占用、实际Trash/保留位置及原因；不把Trash占用宣称已释放。操作记录读取本地引擎结果，不添加导出或上传。
- [x] 详情支持长期保护当前项目，设置列出App自有保护项及明确取消保护。配置变化立即使当前计划过期并要求重新扫描。
- [x] 实现执行中关闭窗口/退出时的等待或取消剩余选择，并等待收尾；单纯查询关闭沿用现有取消。退出等待最终结果的模型测试通过；真实执行期间选择「等待完成后退出」，两项结果记账后退出、无桥接进程遗留。取消剩余后退出的窗口路径另列限制。
- [x] UI模型可注入真实边界查询闭包进行隔离状态测试；生产默认连接随包Bridge，不能显示fake演示数据。
- [x] 编译及20项界面状态测试通过；已完成的真实窗口路径见下方验收记录。无M2执行权限时展示具体原因，不自动申请或修改系统权限。

## Task 4: 来源、打包与整体验收（根代理）

- [x] 保存M1源码快照供无Git环境的diff复审；创建协议/引擎/桥接target及测试target。
- [x] 固定来源为 Mole V1.53.0；Homebrew源归档SHA256为 `35c812d5298a08c672062ac4e1d5a523876144ff0708f9c5c77385d52faccc77`；复制本地GPL LICENSE、必要原文摘录、静态数组JSON和来源摘要，不下载或执行未知脚本。
- [x] build-app.sh 构建App与Bridge，把Bridge放 `Contents/Helpers`，SPM资源bundle放 `Contents/Resources`；先签内部执行器、最后签App，strict/deep 校验通过；版本0.2.0，保持Bundle ID。
- [x] 跑完整测试、真实隔离fixture扫描与系统Trash验证；未选fixture保持内容与存在性不变。App包/残留依赖、取消和冲突路径由隔离fixture测试验证，未把真实App或个人缓存作为执行测试数据。
- [x] 原生UI已验证完整扫描、默认不勾选、单项选择、详情和准确确认清单，返回后未执行并可取消勾选；未确认清理真实个人数据。其余真实窗口路径按下方待验清单保留，不给生产CLI增加测试根开关。
- [x] 独立审查执行边界并修复有证据问题；最终构建/签名检查通过，本文记录实现、验收证据与限制。其他协作说明由根代理同步。

## 进度与决策

- M1基线：2026-09-07重跑32项测试通过。
- 用户要求继续，沿用已确认总体设计；本轮将M2做成可测试的完整路径，不主动对用户真实软件或缓存执行。
- 暂按所有动作移入废纸篓；用户可选处理方式问题已发出，实施前保留合理答复时间。
- 无Git仓库，使用当前指定目录和源码快照复审；不虚构提交或新分支。
- 系统 Trash 接收的是暂存对象，因此 Finder「放回原处」可能回到暂存目录。确认及结果界面说明按记录中的原路径手动恢复；M2 不提供自动恢复或修改废纸篓私有元数据。
- 安装 bundle ID 与保护路径的大小写变体作保守归并；授权执行根保持严格校验。每项处理前复验安装集合及保护配置，仅从预期安装集合扣除本次已有明确移入废纸篓结果的 App 本体。

## 已验证证据（2026-09-07）

- 19:10 根代理全量测试基线通过：20项 XCTest 界面状态测试＋87项 Swift Testing 报告，其中2项显式开关测试默认跳过，共105项实际通过。此后新增1项 lsof 实际格式分类测试，观察两处错误提示后修复，24项客户端限定回归全部通过。当前默认套件共106项＋2项显式开关跳过项；不把跳过项或不同轮次重复用例重复计数。
- 最后 lsof 诊断修复后的 release 重建及 `codesign --verify --deep --strict` 检查通过，并用该包完成下述原生 fixture 验收。随包Bridge与资源定位一致；当前仍是本机架构、ad-hoc签名构建。
- 18:51:35 根代理显式运行系统Trash全链路烟测通过：仅新建隔离fixture中的唯一A被移动，系统返回位置与原快照及内容匹配，未选B的内容和存在性不变。较早一次因Trash父目录不可枚举而返回unknown的记录未自动改写；修复后的最终核验只读取系统返回的具体对象。
- Engine后续修复有真实行为红绿证据：合法换行路径、规则/选择约束、大小写归属及保护、执行中安装或配置变化、记录截断、断链白名单、最终Trash文件/包核验、非标准元数据与iOS包装归属。初版功能首次可运行时已绿；编译或资源缺失不计作行为红灯。
- 客户端24项专项测试通过，包括短progress在final之前送达的有界gate、双管道、协议/选择/结果一致性、预接受取消、显式强制结束，以及 lsof 的 p/f/n 完整占用记录。exit 0/1 的有效命中都保留对象，只改善提示，未增加放行分支。信号注册屏障依据系统注册契约及同步顺序审查，不声称确定性复现了纳秒级注册窗口。
- 真实窗口已验证：启动、71项应用列表及详情、设置中的保护空列表、空历史；完整扫描得到15项候选，默认0勾选，单项选择与详情正确，确认sheet准确列出1项并提示按原路径手动恢复。返回核对后没有执行，并可取消勾选。Codex Usage计划明确显示应用仍在运行，勾选和确认均禁用；Tiny RDM及SimpleComic因打开文件被阻止，没有关闭用户正在使用的应用以放行。
- 新建唯一的 `TidyNest QA 0c0137ea.app` 及两份微小测试缓存。原生列表读取到测试App，移除计划有3项：本体必选、A/B默认不选。对B添加保护使旧计划立即失效；设置显示准确测试路径，明确确认取消保护后列表恢复为空。重新生成计划后仅确认本体＋A，B不选。
- 19:33 从最终原生 App 实际执行这两个测试对象，执行期间弹出退出选择并选择等待完成后退出。重新打开后，非空历史及详情准确显示本体和A的 completed/trashed、原路径与系统返回的位置；没有遗留 TidyNestBridge。测试App及A离开原位，未选B的 dev/inode/size/mtime/hash完全不变，Trash中的App成员hash与执行前一致。B在验收完成后原样归档到 `work/m2-native-retained-cache`，不留新增测试缓存目录。
- 对Trash中A的独立Python内容读取被系统以EPERM拒绝，因此没有把该项独立内容比对说成通过，也未改变权限或换宿主重试。原生引擎已在操作进程中完成最终对象快照核验；结果记录和其它后置检查通过。详细证据见 `work/m2-native-result.json`。
- 安装扫描曾因额外Desktop访问等待TCC；已收敛到固定8根＋Volumes，没有申请权限或通过其他宿主权限绕过。

## 2026-09-08 应用身份误报修复

- 已确认 iPhone/iPad 包装应用可被 Mole 列表报告为 `bundle_id: unknown`，而维护引擎可从已支持的包装布局读取真实 ID。原先把路径和 ID 合并匹配，会把这种差异误报为应用已缺失。
- 现在分别报告“本次安装检查未找到应用”和“应用仍存在但标识与列表不一致”；已识别为包装结构时明确说明当前不支持移除或清理。严格 ID 比较不变，不生成可执行候选，不扩大移除范围。
- 空计划只有在检查完成时才显示“没有可移除的项目”；检查未完成时显示警示和检查提示入口。
- 新增 3 项引擎回归测试，覆盖真实包装结构及 unknown ID、普通应用的 unknown/大小写/不同 ID、缺失路径。先观察旧诊断失败，再确认修复后通过。全量默认实际执行 142 项并通过，3 项 opt-in 未启用。
- release 打包、严格签名与安装后二进制核对通过；旧版备份为 `work/app-install-backups/b0bc1058-2f4e-467b-bda5-bc2ac6d48468/TidyNest-before-identity-diagnostic.app`。
- 已从更新后的 `/Applications/TidyNest.app` 原生窗口对用户截图中的包装应用生成检查结果：显示“应用仍然存在”与“当前版本暂不支持移除或清理”，中央为“未能完成检查”警示，0 项且确认按钮禁用。只做检查，未确认或执行真实应用/缓存的移除。

## 尚未完成的真实界面验收与限制

下列项目不能由编译、模型测试或引擎fixture通过代替：

- [ ] 已开始文件动作后的取消/强制结束、部分失败及待核对状态的真实窗口验收；这些边界已有模型、客户端和引擎隔离测试。真实只读扫描的取消与明确强制结束、真实fixture正常执行及历史明细已通过。
- [ ] 执行中选择「取消剩余并退出」及窗口关闭按钮的完整真实窗口验收；模型测试通过。执行中通过菜单退出并选择「等待完成后退出」的真实路径已通过。

macOS14实机、Intel、跨卷实机拒绝、复杂ACL专项验证，以及正式发行签名/公证尚未验收。固定范围外未启动的应用副本不在唯一归属保证内；系统调用竞态和手动按原路径恢复的边界仍适用。这些限制不因当前本机编译、自动化测试或已完成的窗口检查而消失。


## 2026-09-08 包装应用维护增量计划

目标：用户已明确选择支持外层应用本体，以及能确认归属的缓存、日志；文稿、存档、偏好和共享容器保留。沿用现有计划、选择、确认、逐项 Trash 与恢复机制，不执行真实个人数据的移除验收。

- [x] 先用隔离包装应用复现本体被阻止，并覆盖本体与全局精确 Bundle ID 缓存、日志的选择及依赖；开放已知 `WrappedBundle → Wrapper/<名称>.app`，复用外层包完整快照和执行复验。
- [x] 增加可读容器元数据的保守归属核验：只读取 `~/Library/Containers` 直属容器的有界、无链接元数据，以完整 `MCMMetadataIdentifier` 对应唯一安装；未知、不可读、重复归属均保留，不推测 UUID。仅枚举已确认容器的 `Data/Library/Caches` 和 `Data/Library/Logs` 普通文件，不列出容器根或其他数据。
- [x] 容器规则使用独立 ID，保存元数据身份、摘要及父链；生成结束、执行前、每项执行及暂存后复验。应用本体失败或取消时，依赖的缓存和日志保留。用隔离测试覆盖路径/硬链接、身份变化、重复归属和存档保留。
- [x] 运行相关红绿测试、完整默认测试和 release 打包；审查本次 diff，更新现有说明。原生窗口只检查真实目标的新计划与提示，不确认移除。

参考：[Apple 文件系统说明](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html)区分可重建的 Caches 与 Documents/Application Support。容器元数据按明确识别的本地布局处理，未知格式不作为归属证据。

自动化验收：新行为先红后绿；新增 16 项引擎测试，默认实际 195 项全部通过，3 项 opt-in 未启用。审查发现的移动边界新增同 ID 容器、扫描负匹配证据变化，以及最终核验/暂存后取消均有独立红灯复现，修复后纳入完整回归。最终日志为 `work/wrapped-removal-full.log`；release 打包及严格签名核验通过，更新前版本已备份。

原生验收：已更新 `/Applications/TidyNest.app`，备份见 `work/wrapped-removal-install.json`。正式窗口先单独刷新「云·绝区零」，完整列表时间保持 11:42；新计划识别整个外层包装包，详情说明文稿、存档、偏好及共享容器保留。实际运行状态检查发现 QSpace Pro 持有外层目录、helpd 持有包内 `zh-Hans.lproj/InfoPlist.strings`，因此仍阻止本体，没有绕过保护、关闭这些进程或执行移除；释放占用后的真实可选状态尚未验收。独立真实包只读快照两次相符，477 个成员、记录 71,715 字节；脚本及日志为 `work/wrapped-native-snapshot-verification.swift`、`work/wrapped-native-snapshot.log`，临时测试已移出默认套件。本机容器元数据探查被系统以 EPERM 拒绝，不能把无读取结果当作没有容器；真实容器清理未测，未申请额外权限。


## 2026-09-08 占用提示与重新检查验收

默认实际 209 项全部通过（Swift Testing 158 项含 3 项 opt-in 跳过，另有 XCTest 54 项）；日志 `work/occupancy-full-verified.log`。首次完整回归中，原有包装刷新变化测试在并发运行时触发其 3 秒超时；未放宽断言或修改该用例，单独复核及完整重跑均通过。新增测试先复现原提示缺少占用者、只读误拦，再验证具体进程/PID/路径、后续写入记录、目录 openat 写成员、文件映射、锁、未知/缺字段、取消互斥与精确目标重检。中文及字面反斜杠/控制字符路径在未设置 locale、C、UTF-8 三种真实 lsof 输出下均验证只读通过、写入保留。规则复核指出的目录能力和路径转义问题已用失败测试复现并修正，限定复核通过。

引擎隔离执行使用真实 ps/lsof，只持有新建包装应用内普通文件的只读描述符；本体移动到 fixture Trash 后文件内容仍可读、文稿存档不变。系统 Trash 与真实应用移除未执行。

原生隔离程序复用生产 RootView/MaintenanceView 和真实 RuntimeInspectionService，用本任务新建的中文应用目录制造占用；窗口显示验收进程名、PID、路径与目录原因，勾选禁用。手动释放验收目录后点击「重新检查此应用」，同一目标变为可选，旧提示与选中状态清除。计划证据在 `work/occupancy-native-qa/plan-1.json`、`plan-2.json`；该程序禁用实际移除，不能作为完整引擎或系统 Trash 验收。

正式安装与只读验收：release 构建、安装前后严格签名和主程序/引擎摘要一致；已更新 `/Applications/TidyNest.app`，备份见 `work/occupancy-install.json`。正式窗口重开进入应用，恢复 72 项，未刷新即可检查「云·绝区零」。17:12 计划中的应用本体通过核验，必选框已选中、核对入口启用，不再出现占用原因；容器归属元数据仍不可读取，容器缓存/日志保留。没有进入确认或移除任何真实文件，未退出其他应用。应用列表缓存内容与修改时间均未改变；记录 `work/occupancy-native-result.json`。


## 2026-09-08 计划页点击与取消选择修复

原生旧窗口复现点击「1 项检查提示」文字无响应；DisclosureGroup 的箭头是实际触发区域。改为最小高度 36pt 的整行按钮，标题、箭头、留白均包含在点击区域内；显示展开/收起文字及辅助功能状态，新计划重置为折叠。

原界面仅允许 optional 项修改选择，导致默认选中的 required 本体无法撤回。界面现允许本体取消，并沿用依赖递归清除和确认失效逻辑；重新勾选只选本体，不恢复残留。canConfirm、桥接协议和引擎仍要求必选及依赖完整，本轮未修改引擎规则。对应旧断言调整并增加本体/缓存/日志/确认的回归，先失败后通过；忙碌和 blocked 仍不能切换。17 项维护状态测试和默认实际 210 项完整回归通过（另 3 项 opt-in 未启用），日志 `work/plan-interaction-red.log`、`work/plan-interaction-green.log`、`work/plan-interaction-full.log`；限定审查未发现实质问题。

原生验收与安装：release 与安装后严格签名通过，主程序摘要匹配构建，独立引擎摘要与上一版一致。已更新 `/Applications/TidyNest.app`，备份见 `work/plan-interaction-install.json`。正式窗口中，点击提示文字可展开、点击行内留白可收起，辅助功能状态同步变化；「云·绝区零」本体复选框实测 1→0→1，点击「取消当前选择」回到 0，底部显示 0 项并禁用核对入口。当前保留未勾选状态；没有打开确认或移除真实文件，缓存内容和修改时间未改变。记录见 `work/plan-interaction-native-result.json`。


## 2026-09-08 检查提示紧凑布局

展开后的 ScrollView 会占满 120 点上限，导致短提示下方留下空白。现使用 ViewThatFits 在完整内容与有界滚动容器间选择，外层按垂直理想高度布局，避免短内容仍被拉伸。路径/原因按每条提示分组，间距收紧；保留全文、文字选择和整行展开按钮。布局 API 的理想尺寸语义见 [Apple ViewThatFits 文档](https://developer.apple.com/documentation/SwiftUI/ViewThatFits)。

复用生产界面的独立原生程序 `work/issue-layout-qa/` 已验证：980 点宽窗口内，一条短提示自然撑高，无大块空白且没有多余滚动区；12 条长提示使用高度受限的滚动区，滚到底部可完整看到第 12 条。新计划自动折叠，从长提示返回短提示后高度再次收紧。验收程序不调用维护引擎或移动文件。本轮为纯显示改动，没有新增或重跑状态/引擎测试；原生程序编译及 release 打包、严格签名检查通过，日志 `work/issue-layout-qa/build-fit.log`、`work/issue-layout-build.log`。

正式安装后主程序摘要与构建匹配，引擎摘要与上一版一致。17:54 的真实「云·绝区零」只读计划展开后，路径与原因紧凑显示，无原来的空白滚动区；保持未勾选和确认禁用，没有打开确认或执行移除，应用列表缓存不变。验收记录 `work/issue-layout-native-result.json`，安装与备份信息 `work/issue-layout-install.json`。


## 2026-09-09 操作记录与分栏增量计划

用户已确认记录应用完整列表刷新、单应用刷新、磁盘读取、计划检查和实际移除的结果，并提供单条删除与清空当前页面记录。启动检测、恢复缓存、选择、搜索及展开详情不产生记录；新功能不追补过去未记录的查询。

1. 本地快照 → 验证：Core 的 `OperationRecord` 保存类型、目标、起止时间、结果和摘要，执行项沿用 `MaintenanceResult`；`OperationHistoryStore` 原子保存到 Application Support。测试往返、缺失、损坏不覆盖、非法类型/重复ID、权限/链接和大小边界。
2. 界面状态 → 验证：共享 `OperationHistoryModel` 合并历史执行记录并按runID去重；成功、失败和取消只记录一次。删除按确认时的精确ID集合，旧执行记录的runID加入排除集合以免刷新后重现；引擎审计及防重复执行凭据保留，不改变文件处理规则。测试刷新/重开/新到记录、写入失败及取消晚返回。
3. 页面与分栏 → 验证：时间线展示类型、目标和结果；删除/清空均可取消，提示只移除页面记录及恢复位置显示。磁盘和操作记录右栏使用稳定容器；原生验证选择前后及手动拖动后分隔位置不变，长路径可查看。
4. 统一验收 → 运行相关红绿回归、完整默认测试、release签名检查，复核确认弹窗的单项/多项/未知占用。仅对隔离样本验证删除，正式App只读核对；备份后统一更新本机App，不提交或推送。


## 2026-09-09 增量验收完成

- 操作记录扩展、分栏与确认弹窗完成。新增存储先红后绿；状态回归覆盖查询成功/失败/取消、检查不完整、执行结果立即记录、精确 ID 删除、晚到记录保留、损坏文件不覆盖、保存失败保留页面及重开去重。限定审查发现派发前取消仍会调用执行适配器，新增回归复现后在派发前显式检查取消；派发后缺少结果继续记录 unknown。
- 完整命令 rtk proxy swift test --no-parallel 通过，68 项 XCTest、177 项 Swift Testing（3 项 opt-in 跳过），实际执行 242 项。最初默认并发运行及相关套件并发复核触发既有 3 秒脚本超时；单项通过，完整显式串行通过，未修改旧断言/等待阈值。日志 work/history-expansion-full-verified.log，执行取消红灯 work/history-execution-cancel-red.log。
- 复用生产 UI 的隔离 App 验证六类操作共 13 条记录，成功/失败/取消可区分。单条删除取消不变、确认仅少一条；清空取消保留全部，确认后刷新及退出重开仍为空。所有删除只使用本次新建的隔离记录，虚拟 apply 不移动文件。记录空态/详情分隔位置 406.5 不变，手动拖至 464.5 后切换执行详情仍不变；磁盘对应 529 不变，手动拖至 620 后长名称与路径正常换行，文件夹下钻及返回可用。
- 上一轮确认弹窗一起验收：单项宽 680、高约 407，突出标题/名称/占用和明确操作；12 项清单可滚至最后一项，操作区不随内容滚动；未知占用单独说明。只用隔离样本，不确认真实个人数据移除。
- 已备份并更新 /Applications/TidyNest.app，release 与安装后严格签名通过，主程序和 Bridge 摘要匹配本轮构建。Bridge 因新增 Core 模型链接重建，本轮未修改引擎规则、审计或防重放逻辑。正式 App 启动恢复 72 项、不自动刷新，操作记录导入原有一条执行结果；选择原 /Users/yuqiqian/Downloads/2026-9月 返回 123.4 MB/85 文件，选中 2025年 前后分隔位置 531 不变，记录页面即时出现第二条磁盘读取，选中详情前后位置 408 不变。应用缓存内容/修改时间、引擎 History/Consumed/Journals 全部保持一致。未删除真实记录或移动真实应用/缓存。
- 原生证据与安装备份见 work/history-expansion-native-result.json、work/history-expansion-install.json；构建 work/history-expansion-build.log。正式目录选择完成后 CUA 旧面板目标一度超时，主线程采样及持久化结果确认查询已完成，重新绑定主窗口后验证正常，未为自动化异常修改产品代码。

## 2026-09-09 应用页分栏补充验收

- 复用磁盘页的稳定详情宿主，修复应用页空态切到详情时宽度重分配。原版本选中前后分隔位置为 509→626；隔离原生的首次选择、切换、搜索无结果及清空搜索均保持 507，手动拖至 584 后也保持。
- release 编译、签名和安装摘要核对通过，已备份后更新 /Applications/TidyNest.app。正式列表恢复 72 项，同样的选择及搜索路径保持 508.5；手动拖至 573.5 后切换不跳动，验收后恢复原宽度。Bridge 摘要、应用缓存内容与时间、页面记录及引擎审计/凭据均不变。纯界面布局改动，未新增或重跑状态/引擎测试；本次原生证据与备份见 work/application-split-native-result.json、work/application-split-install.json，构建 work/application-split-build.log。

## 2026-09-09 清理检查与磁盘并行验收

- 问题来自 Workspace 的全局 busy 同时禁用维护检查与磁盘查询。保留各自任务和取消身份，磁盘入口允许维护 scanning 状态，维护检查入口允许磁盘 loading 状态；不允许同类重入、取消收尾重入或退出后派发。实际执行、保护设置及应用刷新维持串行，计划检查不再等待已获准独立运行的磁盘收尾。
- 新增 10 项可观察状态回归，先确认 8 项失败和 2 项原有互斥通过，再实现修复。覆盖双向启动、应用检查、分别取消与迟到结果、扫描失败不丢磁盘结果、磁盘取消发生在检查派发前、执行等待磁盘及其取消收尾、退出先取消两项再等待。完整 rtk proxy swift test --no-parallel 实际执行 252 项通过，3 项 opt-in 跳过；日志 work/disk-concurrency-red.log、work/disk-concurrency-green.log、work/disk-concurrency-full.log。限定四文件和新增回归的只读审查无阻塞问题。
- 隔离原生 App 复用生产界面，以 90 秒检查和 12 秒磁盘样本验证真实入口：清理中可选择文件夹，查询完成可显示结果及进入子目录；取消磁盘不停止清理检查，取消检查保留磁盘结果。记录中起止时间确认两种启动顺序均存在重叠，页面分别展示 2 条取消检查、1 条取消读取和 2 条成功读取。仅查询适配层为隔离样本，未运行真实目录扫描或移除。
- release 编译、安装后严格签名和摘要核对通过，备份后更新 /Applications/TidyNest.app。正式启动恢复 72 项缓存，磁盘入口正常；应用缓存内容/时间、页面记录、引擎 History/Consumed/Journals 和 Bridge 二进制未变。证据及备份位置见 work/disk-concurrency-native-result.json、work/disk-concurrency-install.json；构建日志 work/disk-concurrency-build.log。未做真实 Mole 与 Bridge 并行时的耗时基准。

## 2026-09-09 应用与操作记录并发验收

- 应用刷新按查询自身状态启用，清理/移除检查可与列表或单项刷新双向并行。记录读取独立持有 Task、请求身份和 MaintenanceService；记录取消不会结束检查，退出先禁止新请求并取消各只读任务。实际执行仍与应用/磁盘查询及记录读取互斥，避免导入尚未完成的事务状态；同一时间只生成一个维护计划。
- 检查期间单条删除和清空可用，沿用确认时的精确 ID 集合及执行记录 tombstone；晚到的新操作结果保留，删除的执行结果不重新导入。没有修改页面记录存储格式或引擎规则。
- 新增 14 项状态回归，首次 10 项中 9 项复现原阻塞，1 项原有执行互斥通过。覆盖双向启动、应用显示与计划目标独立、分别取消/派发前取消/晚结果、重复历史请求、读取失败、精确删除、三项任务退出收尾和禁止退出后再派发。更新 SingleApplicationRefreshTests 与 WorkspaceModelTests 中由本次需求取代的串行断言；完整串行测试 266 项通过，3 项 opt-in 跳过。日志：work/app-history-concurrency-red.log、work/app-history-concurrency-green.log、work/app-history-concurrency-full-verified.log。限定只读审查无可行动问题。
- 复用生产界面的隔离 App 验证检查期间刷新列表与单项成功（12→24→36 MB，另一应用保持 48 MB，单项不改完整列表时间），记录与检查分别取消且对方继续，单条删除 3→2、清空确认的两条、晚到记录保留，删除隔离执行记录后刷新不重新出现；清理取消生成的新记录保留。所有查询及执行结果为隔离注入，未使用真实应用或记录作删除测试。
- release 构建、安装后严格签名和摘要核对通过，备份后更新 /Applications/TidyNest.app。正式重开进入应用，恢复 72 项缓存且未自动查询；原缓存内容/时间、页面记录、引擎 History/Consumed/Journals 及 Bridge 二进制均未改变。验收和备份：work/app-history-concurrency-native-result.json、work/app-history-concurrency-install.json；构建日志 work/app-history-concurrency-build.log。未测真实 Mole/Bridge 并发耗时。

## 2026-09-09 应用移动权限预检与错误诊断

- 「云·绝区零」原执行记录停在 moveIntent，未进入 staged 或 trashIntent，原应用仍在。应用包为 root:wheel 0755，当前账户可修改 /Applications，但不可写该包；用新建的 0555 应用目录及同一 renameatx_np(RENAME_EXCL) 复现 EACCES 13。原记录没有保存 errno，因此原失败的系统错误码无法直接还原。
- 普通/包装应用本体在计划阶段和移动前核验 DELETE + ADD_SUBDIRECTORY；通过无链接父目录 FD 对具体包名调用 faccessat，以有效账户执行系统授权检查，不自行解释 POSIX/ACL。不能把可读完整快照当作移动授权，权限不足时阻止本体及依赖文件，保留 Finder 入口；独立缓存清理不因应用本体不可移动而禁止。语义依据 [Apple access1](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/vfs/vfs_syscalls.c) 与 [目录 rename 授权](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/vfs/vfs_subr.c)，本地 SDK 提供对应扩展访问标志。
- 移动失败立即保存 errno，分别说明 EACCES、EPERM、EEXIST，并对其他失败保留系统错误码和说明。身份、快照、依赖、同卷、RENAME_EXCL、移后复验与恢复流程不变，不提权、不修改权限。权限检查只是当时状态，实际移动和保护复核仍是最终边界。
- 新增 8 个引擎回归函数，覆盖普通本体/父目录缺权限、包装本体、独立缓存、移动前权限变化、暂存冲突，以及 ACL 的允许移动与拒绝删除。审查发现普通 W_OK 比 rename 所需权限更严格，又未包含删除权限；两类 ACL 误判均先复现后修复，限定复核通过。正式复检时 helpd 又出现文件映射占用，补充权限不足与临时占用共存的提示回归（work/move-permission-priority-red.log），权限限制现先于占用提示，权限允许后仍照常检查运行状态。最终 92 项 XCTest 与 185 项 Swift Testing（其中 3 项 opt-in 跳过）通过，默认实际执行 274 项。日志：work/move-permission-red.log、work/move-permission-acl-red.log、work/move-permission-green.log、work/move-permission-full-verified.log。
- 原生验收与安装：release、安装后严格签名和主程序/Bridge 摘要匹配构建，已备份更新 /Applications/TidyNest.app，记录 work/move-permission-install.json（originalBackup 为本次修复前原版）。正式 16:59 只读计划显示权限不足与 Finder 指引，提示可完整展开，0 项已选且本体复选框/核对入口禁用；未确认或执行真实移除，也未关闭后台进程。原应用根身份与权限、应用缓存内容/时间及引擎 History/Consumed/Journals 全部保持一致，页面记录新增本次只读检查。原生记录 work/move-permission-native-result.json；真实路径的独立权限核验 work/move-permission-native/readonly-permission-result.json；构建 work/move-permission-build.log。Bridge 摘要变化使旧计划失效，需重新生成计划；实际移除此系统安装应用仍需用户通过 Finder 按系统提示处理。macOS 14 未实机验证。


## 2026-09-09 系统授权应用移除

用户已确认扩展系统授权范围。权限预检仅 EACCES 且其他保护、身份、完整快照均通过时，应用本体可勾选并显示“需要系统授权”。确认页说明 Finder 接管授权；不修改应用权限，不收集密码，不安装常驻 root 服务。

- [x] 协议与计划：可选字段标识系统授权；无授权适配器的测试/旧环境仍保留权限阻止。缓存、日志不得使用此通道；旧计划缺省为普通处理。
- [x] 系统适配：固定 Finder 废纸篓命令，目标以原始 CF 文件引用作为 Apple Event 参数传递；生成前由持有 FD 获取资源标识，生成后独立比较系统不透明身份与 inode。授权前后核验完整包身份。仅提交已确认的单个应用，不发送 shell 命令。NSWorkspace.recycle 的隔离对照返回 513，Finder 命令对同一 0555 fixture 成功且权限未变。
- [x] 执行与记录：系统通道独立记录交接意图，核验返回的是同卷用户废纸篓中的原对象；成功后才允许处理已选依赖。取消/拒绝授权且原对象完整保留时记取消；超时、返回缺失、身份变化记待核对，不自动重放。普通项继续私有暂存与排他移动。
- [x] 界面：计划和确认显示授权说明；执行等待时提示在系统窗口完成或取消。真正受保护的项目以锁定图标替代不可点击的复选框。
- [x] 验证：隔离用例覆盖计划可选、正常通道不变、授权取消/拒绝、失败、未知结果、依赖保留、包变化及记录重读；原生验证勾选/取消、确认文案与新建 fixture 的系统操作。真实“云·绝区零”仅生成计划，由用户自行确认移除。

系统授权期间，Finder 管理授权与移动，无法像普通私有暂存流程一样在系统对话框内部再插入核验；因此返回后完整复核，任何不确定结果保留依赖并要求核对。系统通道不强制终止 Finder，不永久删除、不跨卷复制，不自动再次发送。

- 自动化：新增 17 项引擎、1 项 Core 协议、1 项 UI 状态回归；默认全量 293 项通过（93 XCTest＋203 Swift Testing 中 3 项 opt-in 跳过），日志 `work/authorized-removal-full.log`。覆盖取消/拒绝、缺失回执、日志失败、依赖保留与成功顺序、同名替换、错引用拒绝、旧协议兼容。初始权限阻塞、两项审查问题均有红绿证据；限定复核未发现剩余可行动问题。
- 原生：复用生产 UI、Core、Bridge 和 Finder 适配器，以固定隔离 home/catalog 验证 0555 包装应用。勾选 1→0→1、返回确认不执行、仅确认本体后移入系统废纸篓；原 inode/权限/包装链接一致，未选缓存保留，操作记录显示完成。测试文件名含中文、空格和引号。证据 `work/authorized-removal-native-result.json`，辅助原生对照与只读文件引用试验见 `work/authorized-recycle-probe/`、`work/authorized-alias-probe/`。
- 兼容与限制：使用 macOS 13.3 已提供的公开 CF 文件 inode 键，符合最低 macOS 14；本机为 macOS 15.7.4。未使用系统私有 open-by-ID 权限，不依赖资源标识二进制格式；原生对照证明路径 alias 会错指替身，因此保持 CF 引用，且验证实际发送的引用身份。未证明 Foundation/Finder 内部原子性，系统授权对话框内无法插入维护引擎复核；此限制不影响返回后验证或依赖保留。测试中当前用户新建的只读 fixture 未触发管理员密码窗口，真实 root 属主应用的管理员授权移除留给用户确认，未以真实应用作删除测试。
- release 与安装后严格签名、主程序和 Bridge 摘要一致，已备份更新 `/Applications/TidyNest.app`；证据 `work/authorized-removal-build.log`、`work/authorized-removal-install.json`。旧计划因 Bridge 身份变化失效，需要重新检查。

- 正式只读复核：新版本启动恢复 72 项缓存且不自动查询；18:17「云·绝区零」本体显示 118.3 MB/需要系统授权，1→0→1→0 勾选与确认启用正常。最终未勾选，未打开真实移除确认。真实应用根身份/权限、列表缓存内容/时间及引擎 History/Consumed/Journals 均与安装前基线一致；只新增本次计划检查的页面记录。证据已并入 work/authorized-removal-native-result.json。
