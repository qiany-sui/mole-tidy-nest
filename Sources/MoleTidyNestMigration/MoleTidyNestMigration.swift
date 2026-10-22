import Darwin
import Foundation
import MoleTidyNestCore

@main
struct MoleTidyNestMigration {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments == ["--check"] || arguments == ["--apply"] else {
            print("用法：MoleTidyNestMigration --check | --apply")
            print("先退出新旧 App；--check 只检查，--apply 原位改名旧数据目录，不备份、不合并。迁移后请仅使用新版，旧计划须重新检查。")
            exit(arguments == ["--help"] ? 0 : 2)
        }
        do {
            let applying = arguments == ["--apply"]
            let messages = try await LegacyDataMigration().run(apply: applying)
            messages.forEach { print($0) }
            print(applying ? "迁移完成；未建立备份。请仅使用新版 App，旧计划须重新检查。" : "检查完成；未改动数据。使用 --apply 执行上述迁移，期间请保持新旧 App 退出。")
        } catch {
            try? FileHandle.standardError.write(contentsOf: Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
