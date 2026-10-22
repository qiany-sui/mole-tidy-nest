import Darwin
import Foundation
import Testing
@testable import MoleTidyNestCore

struct LegacyDataMigrationTests {
    @Test func missingLegacyDataDoesNotCreateDirectories() async throws {
        let f = try MigrationFixture()
        _ = try await f.migration.run(apply: true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.home.path).isEmpty)
    }

    @Test func checkLeavesDataAndDirectoryIdentityUnchanged() async throws {
        let f = try MigrationFixture()
        let old = try f.file("Library/Application Support/TidyNest/operation-history.json", "history")
        let identity = try f.inode(old)
        _ = try await f.migration.run(apply: false)
        #expect(try f.inode(old) == identity)
        #expect(!f.exists("Library/Application Support/MoleTidyNest"))
    }

    @Test func migrationPreservesBytesInodesAndHistoryPathsWithoutBackup() async throws {
        let f = try MigrationFixture()
        let records = [
            "Library/Application Support/TidyNest/operation-history.json": "{\"deletedExecutionRunIDs\":[\"old-run\"]}",
            "Library/Application Support/TidyNest/Engine/protections.json": "[\"/保留/目录\"]",
            "Library/Application Support/TidyNest/Engine/Consumed/plan.json": "consumed",
            "Library/Application Support/TidyNest/Engine/Journals/run.json": "/old/TidyNest/Transactions/original",
            "Library/Caches/TidyNest/applications.json": "application snapshot"
        ]
        var inodes: [String: UInt64] = [:]
        for (path, bytes) in records { inodes[path] = try f.inode(f.file(path, bytes)) }
        try f.directory("Library/Application Support/TidyNest/Engine/Transactions/empty-run/empty-item")
        _ = try await f.migration.run(apply: true)
        for (path, bytes) in records {
            let target = f.home.appendingPathComponent(path.replacingOccurrences(of: "/TidyNest/", with: "/MoleTidyNest/"))
            #expect(try String(contentsOf: target, encoding: .utf8) == bytes)
            #expect(try f.inode(target) == inodes[path])
        }
        #expect(!f.exists("Library/Application Support/TidyNest"))
        #expect(!f.exists("Library/Caches/TidyNest"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.home.appendingPathComponent("Library/Application Support").path) == ["MoleTidyNest"])
        _ = try await f.migration.run(apply: true)
    }

    @Test func conflictInSecondDirectoryStopsBeforeMovingEitherDirectory() async throws {
        let f = try MigrationFixture()
        try f.file("Library/Application Support/TidyNest/operation-history.json", "old")
        try f.file("Library/Caches/TidyNest/applications.json", "old cache")
        try f.file("Library/Caches/MoleTidyNest/applications.json", "new cache")
        await #expect(throws: (any Error).self) { _ = try await f.migration.run(apply: true) }
        #expect(f.exists("Library/Application Support/TidyNest/operation-history.json"))
        #expect(!f.exists("Library/Application Support/MoleTidyNest"))
        #expect(try f.text("Library/Caches/MoleTidyNest/applications.json") == "new cache")
    }

    @Test(arguments: ["Library/Application Support", "Library/Caches"])
    func linkedSourceIsRejected(parent: String) async throws {
        let f = try MigrationFixture()
        try f.directory(parent)
        try f.file("outside/keep", "unchanged")
        try FileManager.default.createSymbolicLink(at: f.home.appendingPathComponent(parent + "/TidyNest"), withDestinationURL: f.home.appendingPathComponent("outside"))
        await #expect(throws: (any Error).self) { _ = try await f.migration.run(apply: true) }
        #expect(try f.text("outside/keep") == "unchanged")
        #expect(!f.exists(parent + "/MoleTidyNest"))
    }

    @Test func linkedAncestorIsRejected() async throws {
        let f = try MigrationFixture()
        try f.file("outside/Application Support/TidyNest/keep", "unchanged")
        try FileManager.default.createSymbolicLink(at: f.home.appendingPathComponent("Library"), withDestinationURL: f.home.appendingPathComponent("outside"))
        await #expect(throws: (any Error).self) { _ = try await f.migration.run(apply: true) }
        #expect(f.exists("outside/Application Support/TidyNest/keep"))
    }

    @Test func retainedTransactionPayloadStopsMigration() async throws {
        let f = try MigrationFixture()
        let payload = "Library/Application Support/TidyNest/Engine/Transactions/run/item/App.app/file"
        try f.file(payload, "retained data")
        await #expect(throws: (any Error).self) { _ = try await f.migration.run(apply: true) }
        #expect(try f.text(payload) == "retained data")
    }

    @Test func emptyRetainedTransactionDirectoryStopsMigration() async throws {
        let f = try MigrationFixture()
        let payload = "Library/Application Support/TidyNest/Engine/Transactions/run/item/Empty.app"
        try f.directory(payload)
        await #expect(throws: (any Error).self) { _ = try await f.migration.run(apply: true) }
        #expect(f.exists(payload))
        #expect(!f.exists("Library/Application Support/MoleTidyNest"))
    }

    @Test(arguments: ["Library", "Library/Application Support", "Library/Caches"])
    func writableAncestorStopsMigration(parent: String) async throws {
        let f = try MigrationFixture()
        try f.file("Library/Application Support/TidyNest/operation-history.json", "history")
        try f.file("Library/Caches/TidyNest/applications.json", "cache")
        let path = f.home.appendingPathComponent(parent).path
        #expect(chmod(path, 0o777) == 0)
        await #expect(throws: (any Error).self) { _ = try await f.migration.run(apply: true) }
        #expect(f.exists("Library/Application Support/TidyNest/operation-history.json"))
        #expect(f.exists("Library/Caches/TidyNest/applications.json"))
        var info = stat()
        #expect(lstat(path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o777)
    }

    @Test(arguments: ["Engine/execution.lock", "Mole/.install.lock"])
    func heldLegacyLockStopsMigration(lock: String) async throws {
        let f = try MigrationFixture()
        let url = try f.file("Library/Application Support/TidyNest/" + lock, "")
        let fd = open(url.path, O_RDWR | O_CLOEXEC)
        defer { close(fd) }
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        await #expect(throws: (any Error).self) { _ = try await f.migration.run(apply: true) }
        #expect(f.exists("Library/Application Support/TidyNest/" + lock))
    }

    @Test(arguments: ["TidyNest", "TidyNestBridge", "MoleTidyNest", "MoleTidyNestBridge"])
    func runningApplicationStopsMigration(name: String) async throws {
        let f = try MigrationFixture()
        try f.file("Library/Caches/TidyNest/applications.json", "cache")
        let migration = LegacyDataMigration(home: f.home, processes: { ["/Applications/Example.app/Contents/MacOS/" + name] })
        await #expect(throws: (any Error).self) { _ = try await migration.run(apply: true) }
        #expect(f.exists("Library/Caches/TidyNest/applications.json"))
    }

    @Test func writableByOthersSourceIsRejectedWithoutChangingPermissions() async throws {
        let f = try MigrationFixture()
        try f.directory("Library/Caches/TidyNest")
        let path = f.home.appendingPathComponent("Library/Caches/TidyNest").path
        #expect(chmod(path, 0o777) == 0)
        await #expect(throws: (any Error).self) { _ = try await f.migration.run(apply: true) }
        var info = stat()
        #expect(lstat(path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o777)
    }

    @Test func previouslyMovedSupportDoesNotPreventRemainingCacheMigration() async throws {
        let f = try MigrationFixture()
        try f.file("Library/Application Support/MoleTidyNest/operation-history.json", "existing history")
        try f.file("Library/Caches/TidyNest/applications.json", "legacy cache")
        _ = try await f.migration.run(apply: true)
        #expect(try f.text("Library/Application Support/MoleTidyNest/operation-history.json") == "existing history")
        #expect(try f.text("Library/Caches/MoleTidyNest/applications.json") == "legacy cache")
    }
}

private final class MigrationFixture {
    let home: URL
    var migration: LegacyDataMigration { LegacyDataMigration(home: home, processes: { [] }) }
    init() throws {
        home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("work/mole-rename-fixtures/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    deinit { try? FileManager.default.removeItem(at: home) }
    func directory(_ path: String) throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(path), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    @discardableResult func file(_ path: String, _ text: String) throws -> URL {
        let url = home.appendingPathComponent(path)
        try directory((path as NSString).deletingLastPathComponent)
        try Data(text.utf8).write(to: url)
        guard chmod(url.path, 0o600) == 0 else { throw CocoaError(.fileWriteUnknown) }
        return url
    }
    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(path).path) }
    func text(_ path: String) throws -> String { try String(contentsOf: home.appendingPathComponent(path), encoding: .utf8) }
    func inode(_ url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.systemFileNumber] as! NSNumber).uint64Value
    }
}
