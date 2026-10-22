import Darwin
import Foundation

/// 显式迁移旧版目录；不改记录内容、不合并目标，也不建立备份或兼容链接。
public struct LegacyDataMigration: Sendable {
    private let home: URL
    private let processes: @Sendable () async throws -> [String]

    public init() {
        home = FileManager.default.homeDirectoryForCurrentUser
        processes = {
            let output = try await ProcessRunner().run(executableURL: URL(fileURLWithPath: "/bin/ps"), arguments: ["-axo", "comm="], timeout: 5)
            guard let text = String(data: output.stdout, encoding: .utf8), !text.isEmpty else {
                throw MigrationFailure("无法完整核对运行进程，未迁移数据。")
            }
            return text.split(separator: "\n").map(String.init)
        }
    }

    internal init(home: URL, processes: @escaping @Sendable () async throws -> [String]) {
        self.home = home
        self.processes = processes
    }

    public func run(apply: Bool) async throws -> [String] {
        try await requireApplicationsClosed()
        var moves: [MigrationMove] = []
        var messages: [String] = []
        var locks: [Int32] = []
        defer { locks.forEach { close($0) } }
        for folder in ["Library/Application Support", "Library/Caches"] {
            let path = home.appendingPathComponent(folder).path
            guard let parent = try MigrationDirectory.open(path) else { continue }
            let source = try migrationIdentity(parent.fd, "TidyNest")
            let target = try migrationIdentity(parent.fd, "MoleTidyNest")
            if let target { try validateMigrationDirectory(target) }
            guard let source else {
                if target != nil { messages.append("已使用新目录：" + path + "/MoleTidyNest") }
                continue
            }
            try validateMigrationDirectory(source)
            guard target == nil else { throw MigrationFailure("新旧目录同时存在，未覆盖或合并：" + path) }
            let move = MigrationMove(parent: parent, identity: source)
            if folder == "Library/Application Support" {
                for relative in ["Engine/execution.lock", "Mole/.install.lock"] {
                    if let descriptor = try acquireMigrationLock(path + "/TidyNest/" + relative) { locks.append(descriptor) }
                }
                if let transactions = try MigrationDirectory.open(path + "/TidyNest/Engine/Transactions") {
                    try requireEmptyTransactions(transactions.fd)
                }
            }
            moves.append(move)
            messages.append(path + "/TidyNest → " + path + "/MoleTidyNest")
        }
        // 先检查全部目录，再开始移动，避免第二个目录冲突时已改动第一个。
        try await requireApplicationsClosed()
        try Task.checkCancellation()
        for move in moves { try move.verify() }
        guard apply else { return messages }
        var moved: [MigrationMove] = []
        do {
            for move in moves {
                try Task.checkCancellation()
                try move.verify()
                guard renameatx_np(move.parent.fd, "TidyNest", move.parent.fd, "MoleTidyNest", UInt32(RENAME_EXCL)) == 0 else {
                    throw MigrationFailure("目录未能排他重命名，请核对路径后重试：" + move.parent.path)
                }
                moved.append(move)
                guard let current = try migrationIdentity(move.parent.fd, "MoleTidyNest"), sameMigrationObject(move.identity, current), fsync(move.parent.fd) == 0 else {
                    throw MigrationFailure("迁移后身份或目录同步核对失败：" + move.parent.path)
                }
            }
        } catch {
            // 只回退本次确实移动且身份仍一致的目录，不覆盖后来出现的旧目录。
            var incomplete = false
            for move in moved.reversed() {
                do {
                    try move.parent.verify()
                    guard let current = try migrationIdentity(move.parent.fd, "MoleTidyNest"), sameMigrationObject(move.identity, current),
                          try migrationIdentity(move.parent.fd, "TidyNest") == nil,
                          renameatx_np(move.parent.fd, "MoleTidyNest", move.parent.fd, "TidyNest", UInt32(RENAME_EXCL)) == 0,
                          fsync(move.parent.fd) == 0 else { incomplete = true; continue }
                } catch { incomplete = true }
            }
            if incomplete { throw MigrationFailure("部分目录已改名，自动回退未完成；数据保留在当前目录，请核对后重新运行检查。原错误：" + error.localizedDescription) }
            throw error
        }
        return messages
    }

    private func requireApplicationsClosed() async throws {
        let names: Set<String> = ["TidyNest", "TidyNestBridge", "MoleTidyNest", "MoleTidyNestBridge"]
        for process in try await processes() {
            let name = URL(fileURLWithPath: process.trimmingCharacters(in: .whitespaces)).lastPathComponent
            guard !names.contains(name) else { throw MigrationFailure("请退出新旧版本 App 并等待 Bridge 收尾，再运行迁移：" + name) }
        }
    }
}

private struct MigrationFailure: Error, LocalizedError {
    let reason: String
    init(_ reason: String) { self.reason = reason }
    var errorDescription: String? { reason }
}

private final class MigrationDirectory {
    let path: String
    let fd: Int32
    private init(path: String, fd: Int32) { self.path = path; self.fd = fd }
    deinit { close(fd) }

    static func open(_ path: String) throws -> MigrationDirectory? {
        guard path.hasPrefix("/"), !path.contains("\0"), !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw MigrationFailure("迁移目录路径无效。")
        }
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw MigrationFailure("无法读取路径根目录。") }
        for component in path.split(separator: "/") {
            let next = openat(descriptor, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let failure = errno
            close(descriptor)
            guard next >= 0 else {
                if failure == ENOENT { return nil }
                throw MigrationFailure("路径包含链接、非目录或无法安全读取：" + path)
            }
            descriptor = next
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_uid == getuid() || info.st_uid == 0,
                  info.st_mode & 0o022 == 0 else {
                close(descriptor)
                throw MigrationFailure("迁移父目录属主或权限不安全，未修改权限：" + path)
            }
        }
        return MigrationDirectory(path: path, fd: descriptor)
    }

    func verify() throws {
        guard let current = try Self.open(path) else { throw MigrationFailure("迁移期间父目录消失。") }
        var original = stat(), latest = stat()
        guard fstat(fd, &original) == 0, fstat(current.fd, &latest) == 0, sameMigrationObject(original, latest) else {
            throw MigrationFailure("迁移期间父目录发生变化。")
        }
    }
}

private struct MigrationMove {
    let parent: MigrationDirectory
    let identity: stat
    func verify() throws {
        try parent.verify()
        guard let current = try migrationIdentity(parent.fd, "TidyNest"), sameMigrationObject(identity, current),
              identity.st_mode == current.st_mode, identity.st_uid == current.st_uid,
              try migrationIdentity(parent.fd, "MoleTidyNest") == nil else {
            throw MigrationFailure("迁移期间源目录或目标目录发生变化：" + parent.path)
        }
    }
}

private func migrationIdentity(_ parent: Int32, _ name: String) throws -> stat? {
    var info = stat()
    if fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 { return info }
    if errno == ENOENT { return nil }
    throw MigrationFailure("无法核对迁移对象：" + name)
}

private func validateMigrationDirectory(_ info: stat) throws {
    guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o022 == 0 else {
        throw MigrationFailure("迁移目录不是当前用户拥有的普通目录，或允许其他用户写入；未修改权限。")
    }
}

private func sameMigrationObject(_ first: stat, _ second: stat) -> Bool {
    first.st_dev == second.st_dev && first.st_ino == second.st_ino && first.st_mode & S_IFMT == second.st_mode & S_IFMT
}

private func acquireMigrationLock(_ path: String) throws -> Int32? {
    let url = URL(fileURLWithPath: path)
    guard let parent = try MigrationDirectory.open(url.deletingLastPathComponent().path) else { return nil }
    guard let expected = try migrationIdentity(parent.fd, url.lastPathComponent) else { return nil }
    let fd = openat(parent.fd, url.lastPathComponent, O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard fd >= 0 else { throw MigrationFailure("无法安全读取旧版锁：" + path) }
    var info = stat()
    guard fstat(fd, &info) == 0, sameMigrationObject(expected, info), info.st_mode & S_IFMT == S_IFREG,
          info.st_uid == getuid(), info.st_mode & 0o077 == 0, info.st_nlink == 1, flock(fd, LOCK_EX | LOCK_NB) == 0 else {
        close(fd)
        throw MigrationFailure("旧版任务尚未收尾或锁文件不安全：" + path)
    }
    return fd
}

private func requireEmptyTransactions(_ fd: Int32, depth: Int = 0) throws {
    let copied = dup(fd)
    guard copied >= 0 else { throw MigrationFailure("无法检查旧版事务目录。") }
    guard let directory = fdopendir(copied) else { close(copied); throw MigrationFailure("无法检查旧版事务目录。") }
    defer { closedir(directory) }
    errno = 0
    while let entry = readdir(directory) {
        let name = withUnsafePointer(to: &entry.pointee.d_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
        }
        if name != "." && name != ".." {
            // 引擎只留下 run/item 两层空骨架，item 下即使是空目录也属于保留对象。
            guard depth < 2, let info = try migrationIdentity(fd, name), info.st_mode & S_IFMT == S_IFDIR else {
                throw MigrationFailure("旧版 Transactions 中仍有保留对象或链接，请先按操作记录核对恢复，未迁移数据。")
            }
            try validateMigrationDirectory(info)
            let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard child >= 0 else { throw MigrationFailure("旧版事务目录无法完整检查。") }
            defer { close(child) }
            var opened = stat()
            guard fstat(child, &opened) == 0, sameMigrationObject(info, opened) else {
                throw MigrationFailure("旧版事务目录在检查期间发生变化。")
            }
            try requireEmptyTransactions(child, depth: depth + 1)
        }
        errno = 0
    }
    guard errno == 0 else { throw MigrationFailure("旧版事务目录枚举未完成。") }
}
