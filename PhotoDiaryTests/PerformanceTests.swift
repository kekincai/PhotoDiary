import Testing
import Foundation
import SwiftData
@testable import PhotoDiary

/// 1 万篇日记下各步的耗时，只打印不断言，用来比较存储方式。默认不跑：
///
///     TEST_RUNNER_PERF=1 xcodebuild test -configuration Release ENABLE_TESTABILITY=YES \
///       -only-testing:PhotoDiaryTests/PerformanceTests ...
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PERF"] == "1"))
nonisolated struct PerformanceTests {
    static func entries(_ n: Int) -> [DiaryEntry] {
        (0..<n).map { i in
            DiaryEntry(id: "asset-\(i)/L0/001",
                       caption: "第 \(i) 天，风很舒服，第一次用新镜头拍日落 #旅行# #镜头\(i % 30)#\n— 2026.10.\(i % 28 + 1)\n\n三年后再看，还是喜欢这张\n— 2029.11.02",
                       keywords: ["旅行", "镜头\(i % 30)"], creationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 3600),
                       latitude: 35 + Double(i % 100) / 100, longitude: 139, mediaKind: .photo, isCloudShared: false,
                       pixelWidth: 6000, pixelHeight: 4000, placeName: "横滨")
        }
    }

    static func measure(_ label: String, _ body: () throws -> Void) rethrows {
        let start = ContinuousClock.now
        try body()
        print("⏱ \(label)：\(ContinuousClock.now - start)")
    }

    static func measure(_ label: String, _ body: () async throws -> Void) async rethrows {
        let start = ContinuousClock.now
        try await body()
        print("⏱ \(label)：\(ContinuousClock.now - start)")
    }

    @Test func jsonIndexAt10k() async throws {
        let entries = Self.entries(10_000)
        let snapshot = IndexSnapshot(entries: entries, changeToken: Data("1".utf8))
        var data = Data()
        try Self.measure("JSON 编码 1 万条") { data = try JSONEncoder().encode(snapshot) }
        print("⏱ JSON 大小：\(data.count / 1024) KB")
        try Self.measure("JSON 解码 + 重新解析 1 万条") { _ = try JSONDecoder().decode(IndexSnapshot.self, from: data) }
        Self.measure("只解析 1 万条说明") { for e in entries { _ = CaptionFormat.parse(e.caption) } }
    }

    @Test func databaseIndexAt10k() async throws {
        let entries = Self.entries(10_000)
        let dir = temporaryDirectory()
        let db = await IndexDatabase.open(directory: dir)
        try await Self.measure("数据库首次写入 1 万条") { try await db.apply(.init(upserts: entries, changeToken: Data("1".utf8))) }
        let fresh = await IndexDatabase.open(directory: dir)
        var loaded = IndexDatabase.Loaded()
        await Self.measure("数据库读入 1 万条（用存着的解析结果）") { loaded = await fresh.load() }
        #expect(loaded.entries.count == 10_000)
        var changed = entries[42]
        changed.caption += "\n\n补一句\n— 2026.11.01"
        try await Self.measure("数据库保存 1 条修改") { try await fresh.apply(.init(upserts: [changed], changeToken: Data("2".utf8))) }
        try await Self.measure("数据库删除 1 条") { try await fresh.apply(.init(deletions: [entries[7].id], changeToken: Data("3".utf8))) }
    }
}

