import XCTest

/// 设置里的每一项：外观、主题色、语言、一周起始日、隐藏的说明、导出、重建索引。改完都还原。
final class SettingsTests: DiaryUITestCase {
    @MainActor private func openSettings() {
        tap(button(containing: "更多选项"))
        tap(app.buttons["设置"])
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 10), "设置没有打开")
    }

    @MainActor private func closeSettings() {
        tap(app.buttons["完成"], "设置的完成按钮")
        XCTAssertTrue(app.navigationBars["设置"].waitForNonExistence(timeout: 5))
    }

    @MainActor func testAppearanceAndThemeColor() {
        openSettings()
        tap(app.buttons["深色"], "外观里的深色")
        tap(app.buttons["胭脂"], "主题色胭脂")
        XCTAssertTrue(app.buttons["胭脂"].isSelected)
        assertAlive()
        tap(app.buttons["自动"], "外观里的自动")
        tap(app.buttons["湖蓝"])
        XCTAssertTrue(app.buttons["湖蓝"].isSelected)
        closeSettings()
    }

    /// App 内切换语言：整个界面立刻换成新语言，切回来也一样。
    @MainActor func testSwitchLanguageAndBack() {
        openSettings()
        tap(button(containing: "界面语言"))
        tap(app.buttons["English"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "切到英文后设置标题没变")
        tap(app.buttons["Done"], "英文设置的 Done")
        XCTAssertTrue(tab("Diary").waitForExistence(timeout: 10), "切到英文后标签栏没变")

        tap(button(containing: "More"))
        tap(app.buttons["Settings"])
        tap(button(containing: "Language"))
        tap(app.buttons["简体中文"])
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 10), "切回中文失败")
        closeSettings()
        XCTAssertTrue(tab("日记").exists)
    }

    @MainActor func testWeekStartChangesCalendar() {
        openSettings()
        tap(button(containing: "一周从"))
        tap(app.buttons["周日"])
        closeSettings()
        tap(button(containing: "视图："))
        tap(app.buttons["日历"])
        assertAlive()
        openSettings()
        tap(button(containing: "一周从"))
        tap(app.buttons["周一"])
        closeSettings()
        tap(button(containing: "视图："))
        tap(app.buttons["列表"])
    }

    /// 隐藏一段说明后它不再算日记，取消隐藏后回来。
    @MainActor func testHideCaptionAndShowAgain() {
        openSettings()
        tap(button(containing: "隐藏的说明"))
        tap(app.buttons["添加…"])
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("界面测试隐藏")
        app.alerts.buttons["隐藏"].tap()
        let row = button(containing: "界面测试隐藏")
        XCTAssertTrue(row.waitForExistence(timeout: 5) || text(containing: "界面测试隐藏").exists, "隐藏的说明没有出现在列表里")
        // 取消隐藏。
        let show = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "取消隐藏“界面测试隐藏”")).firstMatch
        if show.exists { show.tap() } else {
            text(containing: "界面测试隐藏").swipeLeft()
            tap(app.buttons["取消隐藏"])
        }
        assertAlive()
    }

    @MainActor func testExportOpensShareSheet() {
        openSettings()
        tap(button(containing: "导出全部日记"))
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 15)
                      || app.navigationBars["UIActivityContentView"].waitForExistence(timeout: 5), "导出没有打开分享面板")
        assertAlive()
    }

    /// 重建索引：重新读整个照片库，日记都还在。
    @MainActor func testRebuildIndex() {
        openSettings()
        let rebuild = button(containing: "重建索引")
        for _ in 0..<5 where !rebuild.isHittable { app.swipeUp() }
        tap(rebuild)
        tap(app.buttons["重新读取整个照片库"])
        XCTAssertTrue(button(containing: "银杏开始黄了").waitForExistence(timeout: 30), "重建索引后日记不见了")
        assertAlive()
    }
}
