import XCTest

/// Apple Intelligence 的入口：搜索框里的句子、编辑器和详情页里的建议标签、回顾页的本周回顾、设置里的开关。
/// 用 -fakeIntelligence 启动，模型换成固定规则的假的（见 FakeIntelligenceEngine）。
final class IntelligenceTests: DiaryUITestCase {
    override var extraLaunchArguments: [String] { ["-fakeIntelligence"] }

    /// 输入“去年 散步”：模型拆成“去年”的日期和“散步”标签，浅色胶囊显示出来；点标签胶囊变成正式筛选。
    @MainActor func testNaturalLanguageSearch() {
        tap(tab("搜索"))
        let field = app.textFields.firstMatch
        focus(field)
        field.typeText("去年 散步")
        let tagToken = app.buttons.matching(NSPredicate(format: "label == %@", "标签“散步”")).firstMatch
        XCTAssertTrue(tagToken.waitForExistence(timeout: 10), "没有出现模型理解的标签胶囊")
        XCTAssertTrue(text(containing: String(lastYear)).waitForExistence(timeout: 5), "没有出现“去年”的日期胶囊")
        tap(tagToken)
        XCTAssertTrue(app.buttons["去掉“标签“散步””"].waitForExistence(timeout: 5), "点了建议没有变成正式筛选")
        XCTAssertEqual(field.value as? String, "去年 散步", "采纳标签后输入的文字不该变")
        tap(app.buttons["回到日记"])
    }

    /// 写“下午去散步”：键盘上方出现 #散步# 的建议，点一下写进正文末尾，保存后详情页有这个标签。
    @MainActor func testSuggestedTagInEditor() {
        let mark = marker("建议")
        startNewDiaryOnBlankPhoto()
        type("\(mark) 下午去散步")
        let chip = hittable(app.buttons.matching(NSPredicate(format: "label == %@", "标签“散步”")), timeout: 10)
        tap(chip, "建议的标签")
        XCTAssertTrue((editorText.value as? String)?.hasSuffix("#散步# ") == true, "点建议没有把标签写到正文末尾")
        // 采纳后胶囊从工具栏里淡出。
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "标签“散步”")).firstMatch.waitForNonExistence(timeout: 5),
                      "采纳后建议的胶囊还在")
        saveEditor()
        XCTAssertTrue(app.buttons["标签“散步”"].waitForExistence(timeout: 10), "保存后详情页没有标签")
        clearDiary(containing: mark)
    }

    /// 没有标签的日记：详情页出现建议，点一下写进说明，变成真正的标签。
    @MainActor func testSuggestedTagOnDetail() {
        let mark = marker("详情")
        startNewDiaryOnBlankPhoto()
        type("\(mark) 一杯咖啡")
        // 编辑器里也会有建议，先忽略，直接保存。
        saveEditor()
        let chip = app.buttons.matching(NSPredicate(format: "label == %@", "标签“咖啡”")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "详情页没有出现建议的标签")
        tap(chip)
        allowPhotoChangeIfAsked()
        assertAlive()
        // 真正的标签点了会跳到标签页；建议的标签只是写进去。等它变成真标签。
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "标签“咖啡”")).firstMatch.waitForExistence(timeout: 10))
        tap(app.buttons["编辑"])
        XCTAssertTrue((editorText.value as? String)?.contains("#咖啡#") == true, "标签没有写进说明")
        tap(app.buttons["取消"])
        XCTAssertTrue(editorText.waitForNonExistence(timeout: 5))
        clearDiary(containing: mark)
    }

    /// 回顾页：这周写过日记就有一段本周回顾。
    @MainActor func testWeeklyReviewShown() {
        let mark = marker("本周")
        startNewDiaryOnBlankPhoto()
        type("\(mark) 这周的一天")
        saveEditor()
        goToJournalRoot()
        tap(tab("回顾"))
        XCTAssertTrue(text(containing: "这一周写了").waitForExistence(timeout: 15), "回顾页没有出现本周回顾")
        clearDiary(containing: mark)
    }

    /// 设置里关掉 Apple Intelligence：编辑器不再出现建议。
    @MainActor func testSwitchOffHidesSuggestions() {
        tap(button(containing: "更多选项"))
        tap(app.buttons["设置"])
        let toggle = app.switches["Apple Intelligence"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "设置里没有 Apple Intelligence 开关")
        toggle.tap()
        tap(app.buttons["完成"], "设置的完成按钮")
        openEntry("寺里的苔藓")
        tap(app.buttons["追加感想"])
        type("下午去散步")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(app.buttons["标签“散步”"].exists, "关掉开关后还有建议")
        tap(app.buttons["取消"])
        tap(app.buttons["放弃"])
        XCTAssertTrue(editorText.waitForNonExistence(timeout: 10))
        // 开关打回去，别的测试还要用。
        goToJournalRoot()
        tap(button(containing: "更多选项"))
        tap(app.buttons["设置"])
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()
        tap(app.buttons["完成"], "设置的完成按钮")
    }
}
