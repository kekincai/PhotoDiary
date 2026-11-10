import XCTest

/// 前面几组没走到的用户操作：合并标签、按时间和日期搜索、长按菜单的编辑和分享、
/// 从照片和地图视图打开一篇、回顾页“还没写的照片”、设置里的说明格式和诊断日志。
final class MoreFlowsTests: DiaryUITestCase {
    /// 标签页“选择”两个标签，合并成一个：说明里的两个标签都换成新的。只动测试自己写的日记，种子的标签不碰。
    @MainActor func testSelectAndMergeTags() {
        let mark = marker("合并")
        let (a, b, merged) = ("甲\(mark.suffix(6))", "乙\(mark.suffix(6))", "丙\(mark.suffix(6))")
        startNewDiaryOnBlankPhoto()
        type("\(mark) #\(a)# #\(b)#")
        saveEditor()

        goToJournalRoot()
        tap(button(containing: "更多选项"))
        tap(app.buttons["标签"])
        tap(app.buttons["选择"], "标签页的选择")
        tap(button(containing: "标签“\(a)”"), "要合并的第一个标签")
        tap(button(containing: "标签“\(b)”"), "要合并的第二个标签")
        tap(app.buttons["合并 2 个标签"], "合并按钮")
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "没有弹出合并的输入框")
        field.tap()
        if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
        field.typeText(merged)
        app.alerts.buttons["确定"].tap()
        allowPhotoChangeIfAsked()
        XCTAssertTrue(button(containing: "标签“\(merged)”").waitForExistence(timeout: 15), "合并后没有新标签")
        XCTAssertFalse(button(containing: "标签“\(a)”").exists, "合并后旧标签还在")
        XCTAssertFalse(button(containing: "标签“\(b)”").exists, "合并后旧标签还在")
        XCTAssertTrue(app.buttons["选择"].waitForExistence(timeout: 5), "合并后没有退出选择")

        clearDiary(containing: mark)
    }

    /// 搜索页点“最近 30 天”：只剩这段时间里的日记；去掉条件后回到浏览。再用日历只选今天。
    @MainActor func testSearchByTimeCardAndDateRange() {
        tap(tab("搜索"))
        let month = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "最近 30 天")).firstMatch
        tap(month, "时间卡片：最近 30 天")
        XCTAssertTrue(button(containing: "银杏开始黄了").waitForExistence(timeout: 10), "最近 30 天里没有今天的日记")
        XCTAssertTrue(button(containing: "寺里的苔藓").exists, "最近 30 天里没有 12 天前的日记")
        XCTAssertFalse(button(containing: "去年今天的咖啡").exists, "最近 30 天里混进了一年前的日记")

        tap(app.buttons["去掉“最近 30 天”"], "去掉时间条件")
        XCTAssertTrue(month.waitForExistence(timeout: 5), "去掉条件后没有回到浏览")

        let custom = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "选择日期")).firstMatch
        tap(custom, "时间卡片：选择日期")
        let today = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "今天，")).firstMatch
        tap(today, timeout: 10, "日历里的今天")
        tap(app.buttons["完成"], "选日期的完成")
        XCTAssertTrue(button(containing: "银杏开始黄了").waitForExistence(timeout: 10), "只选今天时没有今天的日记")
        XCTAssertFalse(button(containing: "寺里的苔藓").exists, "只选今天时混进了别的日子")
        tap(app.buttons["回到日记"])
    }

    /// 长按日记卡片：“编辑”打开整条说明的编辑器；“分享”打开分享面板。
    @MainActor func testContextMenuEditAndShare() {
        goToJournalRoot()
        let card = button(containing: "银杏开始黄了")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.press(forDuration: 1.2)
        tap(app.buttons["编辑"], "长按菜单里的编辑")
        XCTAssertTrue(editorText.waitForExistence(timeout: 10), "编辑器没有打开")
        XCTAssertTrue((editorText.value as? String)?.contains("银杏开始黄了") == true, "编辑器里不是整条说明")
        tap(app.buttons["取消"])
        XCTAssertTrue(editorText.waitForNonExistence(timeout: 10))

        card.press(forDuration: 1.2)
        if !app.buttons["分享"].waitForExistence(timeout: 3) { card.press(forDuration: 1.2) }
        tap(app.buttons["分享"], "长按菜单里的分享")
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 15)
                      || app.navigationBars["UIActivityContentView"].waitForExistence(timeout: 5), "分享面板没有打开")
        let closeShare = app.buttons.matching(NSPredicate(format: "label IN %@", ["关闭", "Close"])).firstMatch
        if closeShare.exists { closeShare.tap() } else { app.swipeDown(velocity: .fast) }
        assertAlive()
    }

    /// 照片视图里点一张、地图视图里点一个点，都进到那一篇。
    @MainActor func testOpenEntryFromPhotoGridAndMap() {
        for mode in ["照片", "地图"] {
            goToJournalRoot()
            tap(button(containing: "视图："))
            tap(app.buttons[mode], "视图菜单里的\(mode)")
            let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "银杏开始黄了")).firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 15), "\(mode)视图里没有今天的日记")
            // 照片视图第一排在导航栏下面：点格子的下半部分，别点到导航栏上。
            entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
            XCTAssertTrue(app.buttons["追加感想"].waitForExistence(timeout: 10), "从\(mode)视图没有进入详情")
        }
        goToJournalRoot()
        tap(button(containing: "视图："))
        tap(app.buttons["列表"])
    }

    /// 回顾页“还没写的照片”：标题打开“从照片添加”；点一张写一篇，保存后回到日记、打开这一篇。
    @MainActor func testWriteFromReviewUnwrittenPhotos() {
        tap(tab("回顾"))
        let header = button(containing: "还没写的照片")
        for _ in 0..<6 where !(header.exists && header.isHittable) { app.swipeUp() }
        tap(header, "还没写的照片的标题")
        XCTAssertTrue(app.navigationBars["从照片添加"].waitForExistence(timeout: 10), "没有打开从照片添加")
        tap(app.buttons["关闭"])

        let mark = marker("回顾写")
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "给")).matching(NSPredicate(format: "label ENDSWITH %@", "写日记")).firstMatch
        tap(tile, timeout: 10, "还没写的照片里的一张")
        XCTAssertTrue(editorText.waitForExistence(timeout: 10), "编辑器没有打开")
        XCTAssertTrue(text(containing: "写日记").exists, "打开的不是写新日记")
        type(mark)
        saveEditor()
        XCTAssertTrue(text(containing: mark).waitForExistence(timeout: 10), "保存后没有打开新写的这一篇")
        clearDiary(containing: mark)
    }

    /// 设置里的说明格式页和导出诊断日志。
    @MainActor func testCaptionFormatPageAndDiagnosticLog() {
        tap(button(containing: "更多选项"))
        tap(app.buttons["设置"])
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 10))
        let format = button(containing: "说明格式")
        for _ in 0..<4 where !(format.exists && format.isHittable) { app.swipeUp() }
        tap(format)
        XCTAssertTrue(app.navigationBars["说明格式"].waitForExistence(timeout: 5), "说明格式页没有打开")
        XCTAssertTrue(text(containing: "— 2026.10.31").exists, "说明格式页没有示例")
        tap(app.buttons["BackButton"])

        let log = button(containing: "导出诊断日志")
        for _ in 0..<5 where !(log.exists && log.isHittable) { app.swipeUp() }
        tap(log)
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 15)
                      || app.navigationBars["UIActivityContentView"].waitForExistence(timeout: 5), "诊断日志没有打开分享面板")
        let closeShare = app.buttons.matching(NSPredicate(format: "label IN %@", ["关闭", "Close"])).firstMatch
        if closeShare.exists { closeShare.tap() } else { app.swipeDown(velocity: .fast) }
        assertAlive()
    }
}
