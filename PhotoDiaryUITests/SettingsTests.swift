import XCTest

/// 设置里的每一项：外观、主题色、语言、一周起始日、晚间提醒、隐藏的说明、导出、重建索引。改完都还原。
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

    /// App 内切换语言：设置留在原处，整个界面（包括设置自己）立刻换成新语言，切回来也一样。
    @MainActor func testSwitchLanguageAndBack() {
        openSettings()
        tap(button(containing: "界面语言"))
        tap(app.buttons["English"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "切到英文后设置标题没变")
        XCTAssertTrue(app.buttons["Automatic"].exists, "切到英文后外观选项还是旧语言")
        tap(app.buttons["Done"], "英文设置的 Done")
        XCTAssertTrue(tab("Diary").waitForExistence(timeout: 10), "切到英文后标签栏没变")

        tap(button(containing: "More"))
        tap(app.buttons["Settings"])
        tap(button(containing: "Language"))
        tap(app.buttons["简体中文"])
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 10), "切回中文后设置被收起或标题没变")
        XCTAssertTrue(app.buttons["自动"].exists, "切回中文后外观选项还是旧语言")
        closeSettings()
        XCTAssertTrue(tab("日记").exists)
    }

    /// 一周从周日开始：回顾里的本周换成从周日起的七天；改回周一再换回来。
    @MainActor func testWeekStartChangesCalendar() {
        // 只在“从周日起”的这一周里的一天：今天是周日就取明天，否则取上一个周日。
        var sundayFirst = Calendar(identifier: .gregorian)
        sundayFirst.firstWeekday = 1
        let today = Calendar.current.startOfDay(for: .now)
        let isSunday = sundayFirst.component(.weekday, from: today) == 1
        let probe = isSunday ? sundayFirst.date(byAdding: .day, value: 1, to: today)!
                             : sundayFirst.dateInterval(of: .weekOfYear, for: today)!.start
        let probeDay = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", shortDate(probe))).firstMatch

        tap(tab("回顾"))
        XCTAssertTrue(app.staticTexts["回顾"].waitForExistence(timeout: 10))
        XCTAssertFalse(probeDay.exists, "一周从周一开始时不该有这一天")

        // 设置在日记页的 ⋯ 菜单里。
        tap(tab("日记"))
        openSettings()
        tap(button(containing: "一周从"))
        tap(app.buttons["周日"])
        closeSettings()
        tap(tab("回顾"))
        XCTAssertTrue(probeDay.waitForExistence(timeout: 10), "改成周日开始后，本周没有换成从周日起的七天")
        tap(tab("日记"))
        tap(button(containing: "视图："))
        tap(app.buttons["日历"])
        assertAlive()

        openSettings()
        tap(button(containing: "一周从"))
        tap(app.buttons["周一"])
        closeSettings()
        tap(button(containing: "视图："))
        tap(app.buttons["列表"])
        tap(tab("回顾"))
        XCTAssertTrue(probeDay.waitForNonExistence(timeout: 10), "改回周一后本周没有换回来")
    }

    /// 晚间提醒：打开时问通知权限，允许后出现时间；再关掉，不影响别的测试。
    @MainActor func testEveningReminderToggle() {
        openSettings()
        let toggle = app.switches["晚间提醒"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "找不到晚间提醒")
        for _ in 0..<3 where !toggle.isHittable { app.swipeUp() }
        flip(toggle)
        allowNotificationsIfAsked()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 10), "打开提醒后没有出现时间")
        XCTAssertEqual(toggle.value as? String, "1", "允许通知后开关没有打开")
        assertAlive()

        flip(toggle)
        XCTAssertTrue(app.datePickers.firstMatch.waitForNonExistence(timeout: 5), "关掉提醒后时间还在")
        XCTAssertEqual(toggle.value as? String, "0")
        closeSettings()
    }

    /// 点开关本身（点整行的标签部分不会切换）。
    @MainActor private func flip(_ toggle: XCUIElement) {
        let knob = toggle.switches.firstMatch
        (knob.exists ? knob : toggle).tap()
    }

    /// 隐藏一段说明后它不再算日记，取消隐藏后回来。
    /// 种子照片里有两张说明只有“0”的（导入工具留下的那种）：它们在“常见的短说明”里；隐藏后从建议里消失，取消隐藏后回来。
    @MainActor func testHideCaptionAndShowAgain() {
        openSettings()
        tap(button(containing: "隐藏的说明"))
        let suggestion = app.buttons["隐藏“0”，2 张照片"]
        tap(suggestion, timeout: 10, "常见短说明里的 0")
        let hidden = app.buttons["取消隐藏“0”"]
        XCTAssertTrue(hidden.waitForExistence(timeout: 5), "隐藏后没有出现在已隐藏里")
        XCTAssertTrue(suggestion.waitForNonExistence(timeout: 5), "隐藏后它们还算日记（还在常见的短说明里）")

        tap(hidden)
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), "取消隐藏后它们没有回到日记里")
        XCTAssertFalse(hidden.exists)
        assertAlive()
    }

    @MainActor func testExportOpensShareSheet() {
        openSettings()
        // “日记”组行数多，小屏上导出在屏幕外，先滚到它。
        let export = button(containing: "导出全部日记")
        for _ in 0..<4 where !(export.exists && export.isHittable) { app.swipeUp() }
        tap(export)
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
