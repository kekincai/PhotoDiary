import XCTest

/// 写日记的每一条路：新写、追加、编辑、清除、取消、删除。每次保存后都确认 App 没有闪退。
final class WritingTests: DiaryUITestCase {
    /// 回归：11 月 2 日保存说明就闪退（照片库通知在后台线程，观察者被当成主线程的）。
    @MainActor func testWriteNewDiaryFromPlusButton() {
        let mark = marker("新写")
        startNewDiaryOnBlankPhoto()
        type("\(mark) 今天的晚霞 #界面测试#")
        saveEditor()

        // 保存后直接打开刚写的这篇。
        XCTAssertTrue(app.buttons["追加感想"].waitForExistence(timeout: 10), "保存后没有打开刚写的日记")
        XCTAssertTrue(text(containing: mark).exists, "详情页里没有刚写的字")

        // 回到日记列表也能看到。
        goToJournalRoot()
        XCTAssertTrue(button(containing: mark).waitForExistence(timeout: 10), "新写的日记没有出现在列表里")

        // 收尾：编辑成空，清除说明，照片回到空白，下次还能用。
        openEntry(mark)
        tap(app.buttons["编辑"])
        let field = editorText
        focus(field)
        field.press(forDuration: 1.2)
        if app.menuItems["全选"].waitForExistence(timeout: 3) { app.menuItems["全选"].tap() }
        else if app.menuItems["Select All"].exists { app.menuItems["Select All"].tap() }
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        tap(app.buttons["完成"])
        tap(app.buttons["清除说明"], "清除说明的确认")
        allowPhotoChangeIfAsked()
        assertAlive()
        goToJournalRoot()
        XCTAssertTrue(button(containing: mark).waitForNonExistence(timeout: 10), "清除后日记还在列表里")
    }

    @MainActor func testAppendThoughtFromDetail() {
        let mark = marker("追加")
        openEntry("寺里的苔藓")
        tap(app.buttons["追加感想"])
        XCTAssertTrue(text(containing: "寺里的苔藓").waitForExistence(timeout: 5), "追加时纸上没有显示之前写的字")
        type("\(mark) 过了几天再看")
        saveEditor()
        XCTAssertTrue(text(containing: mark).waitForExistence(timeout: 10), "追加的感想没有出现在详情页")
    }

    @MainActor func testEditDiaryFromDetail() {
        let mark = marker("编辑")
        openEntry("银杏开始黄了")
        tap(app.buttons["编辑"])
        let field = editorText
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue((field.value as? String)?.contains("银杏开始黄了") == true, "编辑时没有带出原来的说明")
        focus(field)
        field.typeText(" \(mark)")
        saveEditor()
        XCTAssertTrue(text(containing: mark).waitForExistence(timeout: 10), "改过的说明没有出现在详情页")
    }

    @MainActor func testAppendFromListContextMenu() {
        let mark = marker("长按")
        goToJournalRoot()
        // 列表最上面“1 年前的今天”也含这段字，要长按的是下面的日记卡片（读法以日期开头）。
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND NOT (label BEGINSWITH %@)", "去年今天的咖啡", "1 年前")).firstMatch
        for _ in 0..<10 where !card.waitForExistence(timeout: 1) { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.press(forDuration: 1.2)
        tap(app.buttons["追加感想"], "长按菜单里的追加感想")
        type(mark)
        saveEditor()
        openEntry("去年今天的咖啡")
        XCTAssertTrue(text(containing: mark).waitForExistence(timeout: 10))
    }

    /// 写了字再取消：先问要不要放弃，放弃后什么都不写进照片。
    @MainActor func testCancelAsksBeforeDiscarding() {
        let mark = marker("放弃")
        openEntry("寺里的苔藓")
        tap(app.buttons["追加感想"])
        type(mark)
        tap(app.buttons["取消"], "编辑器的取消按钮")
        tap(app.buttons["放弃"], "放弃修改的确认")
        XCTAssertTrue(editorText.waitForNonExistence(timeout: 10))
        XCTAssertFalse(text(containing: mark).exists, "放弃的文字被写进去了")

        // 没写字时直接关掉，不问。
        tap(app.buttons["追加感想"])
        XCTAssertTrue(editorText.waitForExistence(timeout: 10))
        tap(app.buttons["取消"])
        XCTAssertTrue(editorText.waitForNonExistence(timeout: 5), "没改过也弹了确认")
    }

    /// 完成按钮在没写字时不能点。
    @MainActor func testDoneIsDisabledUntilSomethingIsWritten() {
        openEntry("寺里的苔藓")
        tap(app.buttons["追加感想"])
        XCTAssertTrue(editorText.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["完成"].isEnabled)
        type("字")
        XCTAssertTrue(app.buttons["完成"].isEnabled)
        tap(app.buttons["取消"])
        tap(app.buttons["放弃"])
    }

    /// 输入 # 后出现用过的标签，点一下补全。
    @MainActor func testTagSuggestionCompletesTag() {
        let mark = marker("补全")
        openEntry("寺里的苔藓")
        tap(app.buttons["追加感想"])
        type("\(mark) #京")
        tap(hittable(app.buttons.matching(NSPredicate(format: "label == %@", "标签“京都”"))), "标签联想里的京都")
        XCTAssertTrue((editorText.value as? String)?.contains("#京都#") == true, "点联想没有补全成 #京都#")
        saveEditor()
    }

    /// 删除照片：先在 App 里确认，再由系统确认，日记一起消失。
    @MainActor func testDeletePhotoWithDiary() {
        let mark = marker("删除")
        startNewDiaryOnBlankPhoto()
        type(mark)
        saveEditor()

        openEntry(mark)
        tap(app.buttons["更多"])
        tap(app.buttons["删除照片…"])
        tap(app.buttons["删除照片和日记"], "删除的确认")
        confirmPhotoDeletion()
        assertAlive()
        XCTAssertTrue(app.buttons["追加感想"].waitForNonExistence(timeout: 10), "删除后还停在详情页")
        goToJournalRoot()
        XCTAssertFalse(button(containing: mark).exists, "删除后日记还在列表里")
    }
}
