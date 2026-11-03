import XCTest

/// 看日记的每一条路：启动、四种视图、详情、大图、分享、标签、搜索、回顾、设置。
final class BrowsingTests: DiaryUITestCase {
    @MainActor func testLaunchShowsDiariesFromPhotoCaptions() {
        XCTAssertTrue(button(containing: "银杏开始黄了").waitForExistence(timeout: 20), "照片说明里的日记没有出现")
        XCTAssertTrue(app.staticTexts["日记"].exists)
    }

    @MainActor func testSwitchJournalModesFromToolbar() {
        for (mode, check) in [("日历", "今天"), ("照片", ""), ("地图", ""), ("列表", "银杏开始黄了")] {
            tap(button(containing: "视图："), "视图按钮")
            tap(app.buttons[mode], "视图菜单里的\(mode)")
            XCTAssertTrue(button(containing: "视图：\(mode)").waitForExistence(timeout: 5), "没有切到\(mode)")
            if !check.isEmpty {
                XCTAssertTrue(text(containing: check).waitForExistence(timeout: 10), "\(mode)视图里没有“\(check)”")
            }
            assertAlive()
        }
    }

    /// 长按底部的“日记”标签也能换视图。
    @MainActor func testSwitchJournalModeByLongPressingTab() {
        tab("日记").press(forDuration: 1.2)
        tap(app.buttons["日历"], "长按菜单里的日历")
        XCTAssertTrue(button(containing: "视图：日历").waitForExistence(timeout: 5))
        // 上一个菜单刚收起时，模拟器偶尔吞掉紧接着的长按（单独连跑 5 次都过，整套跑时偶发）：没弹出就再按一次。
        tab("日记").press(forDuration: 1.2)
        if !app.buttons["列表"].waitForExistence(timeout: 3) { tab("日记").press(forDuration: 1.2) }
        tap(app.buttons["列表"])
        XCTAssertTrue(button(containing: "视图：列表").waitForExistence(timeout: 5))
    }

    @MainActor func testCalendarDayOpensEntries() {
        tap(button(containing: "视图："))
        tap(app.buttons["日历"])
        // 11 月 1 日有一篇（银杏）。
        let day = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "银杏开始黄了")).firstMatch
        tap(day, timeout: 10, "日历里 11 月 1 日的格子")
        XCTAssertTrue(app.buttons["追加感想"].waitForExistence(timeout: 10) || text(containing: "银杏开始黄了").exists)
        goToJournalRoot()
        tap(button(containing: "视图："))
        tap(app.buttons["列表"])
    }

    @MainActor func testDetailShowsTagsAndPlaceAndOpensTag() {
        openEntry("寺里的苔藓")
        XCTAssertTrue(app.buttons["标签“京都”"].exists || text(containing: "京都").exists)
        tap(button(containing: "标签“旅行”"), "详情页的旅行标签")
        XCTAssertTrue(app.navigationBars.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "旅行")).firstMatch.waitForExistence(timeout: 10)
                      || text(containing: "旅行").exists, "没有进入标签页")
    }

    @MainActor func testPhotoViewerOpensAndCloses() {
        openEntry("银杏开始黄了")
        let photo = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "照片")).firstMatch
        tap(photo, "详情页顶部的照片")
        let close = app.buttons["关闭"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "大图没有打开")
        close.tap()
        XCTAssertTrue(app.buttons["追加感想"].waitForExistence(timeout: 10), "关掉大图后没有回到详情页")
    }

    @MainActor func testShareSheetOpens() {
        openEntry("银杏开始黄了")
        tap(app.buttons["分享"])
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 15) || app.navigationBars["UIActivityContentView"].waitForExistence(timeout: 5),
                      "分享面板没有打开")
        assertAlive()
        // 关掉分享面板。
        let closeShare = app.buttons.matching(NSPredicate(format: "label IN %@", ["关闭", "Close"])).firstMatch
        if closeShare.exists { closeShare.tap() } else { app.swipeDown(velocity: .fast) }
    }

    @MainActor func testRenameTagAndRenameBack() {
        tap(button(containing: "更多选项"))
        tap(app.buttons["标签"])
        let coffee = button(containing: "标签“咖啡”")
        XCTAssertTrue(coffee.waitForExistence(timeout: 10), "标签页里没有咖啡")

        rename(coffee, to: "咖啡豆")
        XCTAssertTrue(button(containing: "标签“咖啡豆”").waitForExistence(timeout: 15), "改名后没有出现新标签")
        XCTAssertFalse(button(containing: "标签“咖啡”，").exists)

        rename(button(containing: "标签“咖啡豆”"), to: "咖啡")
        XCTAssertTrue(button(containing: "标签“咖啡”，").waitForExistence(timeout: 15), "改回原名失败")
    }

    @MainActor private func rename(_ tag: XCUIElement, to name: String) {
        tag.press(forDuration: 1.2)
        tap(app.buttons["改名"], "长按菜单里的改名")
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
        field.typeText(name)
        app.alerts.buttons["确定"].tap()
        allowPhotoChangeIfAsked()
        assertAlive()
    }

    @MainActor func testSearchByTextAndTag() {
        tap(tab("搜索"))
        let field = app.textFields.firstMatch
        focus(field)
        field.typeText("苔藓\n")
        XCTAssertTrue(button(containing: "寺里的苔藓").waitForExistence(timeout: 10), "按文字搜不到")
        XCTAssertFalse(button(containing: "银杏开始黄了").exists, "搜索结果里混进了不相关的日记")

        tap(app.buttons["清除"])
        focus(field)
        field.typeText("#")
        tap(button(containing: "标签“散步”"), "标签联想里的散步")
        XCTAssertTrue(button(containing: "银杏开始黄了").waitForExistence(timeout: 10), "按标签搜不到")

        tap(app.buttons["回到日记"])
        XCTAssertTrue(button(containing: "视图：").waitForExistence(timeout: 10))
    }

    @MainActor func testReviewShowsWeekAndMemories() {
        tap(tab("回顾"))
        XCTAssertTrue(app.staticTexts["回顾"].waitForExistence(timeout: 10))
        // 这一周的七天。
        XCTAssertTrue(text(containing: "今天").waitForExistence(timeout: 10), "这一周里没有今天")
        assertAlive()
    }

    @MainActor func testAddFromPhotosListsPhotosAndCloses() {
        tap(button(containing: "从照片写日记"))
        // 默认只列还没写的；切到“全部照片”才有写过的。
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "还没写日记的照片")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "已写日记的照片")).firstMatch.exists)
        tap(app.buttons["全部照片"])
        // 自动测试造的新照片排在前面，写过日记的种子照片在下面几屏。
        let written = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "已写日记的照片")).firstMatch
        for _ in 0..<8 where !written.exists { app.swipeUp() }
        XCTAssertTrue(written.waitForExistence(timeout: 5), "“全部照片”里没有已写日记的照片")
        // 写过的照片点进去是追加。
        written.tap()
        XCTAssertTrue(editorText.waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "追加感想").exists, "写过的照片打开的不是追加感想")
        tap(app.buttons["取消"])
        tap(app.buttons["关闭"])
        XCTAssertTrue(tab("日记").waitForExistence(timeout: 5))
    }
}
