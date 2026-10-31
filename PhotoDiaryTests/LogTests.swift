import Testing
import Foundation
import OSLog
@testable import PhotoDiary

struct LogTests {
    @Test func exportContainsThisRunsLogs() async throws {
        let marker = UUID().uuidString
        Log.sync.notice("导出测试 \(marker, privacy: .public)")

        let text = try await Log.export()
        #expect(text.hasPrefix("PhotoDiary "))
        #expect(text.contains("[sync] NOTICE 导出测试 \(marker)"))
    }
}
