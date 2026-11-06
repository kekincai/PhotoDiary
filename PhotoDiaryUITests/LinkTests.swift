import XCTest

/// 小组件、控制中心、快捷指令打开 App 用的 photodiary:// 链接。
/// XCUITest 点不到小组件，用 -openURL 启动，App 当作系统送来的链接处理（和 onOpenURL 走同一条路）。

/// 控制中心“写日记”、锁屏“写今天”、快捷指令“给最新一张照片写日记”：直接打开编辑器。
final class OpenWriteLatestLinkTests: DiaryUITestCase {
    override var extraLaunchArguments: [String] { ["-openURL", "photodiary://write/latest"] }
    override var expectsJournalOnLaunch: Bool { false }

    @MainActor func testWriteLatestLinkOpensEditor() {
        XCTAssertTrue(editorText.waitForExistence(timeout: 20), "打开 photodiary://write/latest 后编辑器没有出现")
        // 什么都没写，取消直接关掉。
        tap(app.buttons["取消"], "编辑器的取消按钮")
        XCTAssertTrue(editorText.waitForNonExistence(timeout: 10), "取消后编辑器没有关闭")
        XCTAssertTrue(tab("日记").waitForExistence(timeout: 10), "关掉编辑器后不在日记页")
        assertAlive()
    }
}

/// 快捷指令“那年今日”、小组件：打开回顾。
final class OpenOnThisDayLinkTests: DiaryUITestCase {
    override var extraLaunchArguments: [String] { ["-openURL", "photodiary://onthisday"] }

    @MainActor func testOnThisDayLinkOpensReview() {
        XCTAssertTrue(app.staticTexts["回顾"].waitForExistence(timeout: 20), "打开 photodiary://onthisday 后不在回顾页")
        // 测试照片里有一篇“去年今天的咖啡”。
        XCTAssertTrue(text(containing: "1 年前的今天").waitForExistence(timeout: 10), "回顾里没有那年今日")
        assertAlive()
    }
}
