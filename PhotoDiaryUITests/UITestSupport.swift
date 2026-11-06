import XCTest

/// 界面测试的公共部分：用中文界面启动、处理系统弹窗、确认 App 没有闪退。
///
/// 照片来自 `Tools/TestPhotos/seed.sh`：三张带日记（#散步#、#旅行# #京都#、#咖啡#），三张空白。
/// 测试会改照片说明，所以每次写进去的字都带一个随机记号，断言只认这个记号。
class DiaryUITestCase: XCTestCase {
    nonisolated(unsafe) var app: XCUIApplication!
    @MainActor var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }

    override func setUpWithError() throws {
        continueAfterFailure = false
        // XCTest 在主线程上调 setUp / tearDown。
        nonisolated(unsafe) let test = self
        MainActor.assumeIsolated { test.launchApp() }
    }

    override func tearDownWithError() throws {
        nonisolated(unsafe) let test = self
        MainActor.assumeIsolated { test.assertStillRunning() }
    }

    /// 子类加自己的启动参数（例如 -fakeIntelligence、-openURL photodiary://…）。
    var extraLaunchArguments: [String] { [] }
    /// 启动后要不要等日记页出现。带链接启动时可能直接盖上编辑器，由测试自己断言。
    var expectsJournalOnLaunch: Bool { true }

    @MainActor private func launchApp(extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + extraLaunchArguments + extra
        app.launch()
        allowPhotoAccessIfAsked()
        guard expectsJournalOnLaunch else { return }
        XCTAssertTrue(tab("日记").waitForExistence(timeout: 20), "启动后没有进入日记页")
    }

    /// 带额外的启动参数重开一次 App（例如模拟点开了通知）。
    @MainActor func relaunch(with extra: [String]) {
        app.terminate()
        launchApp(extra: extra)
    }

    @MainActor private func assertStillRunning() {
        if let app, app.state != .runningForeground {
            XCTFail("App 已经不在前台（可能闪退了），状态：\(app.state.rawValue)")
        }
    }

    // MARK: 查找

    /// 底部浮动标签栏里的标签。
    @MainActor func tab(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// label 里含有这段文字的按钮（卡片、行、格子都是按钮）。
    @MainActor func button(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor func text(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// 同名的按钮有好几个（例如编辑器盖在详情页上，两边都有同一个标签）时，取看得见、点得到的那个。
    @MainActor func hittable(_ query: XCUIElementQuery, timeout: TimeInterval = 5) -> XCUIElement {
        let deadline = Date.now.addingTimeInterval(timeout)
        repeat {
            if let element = query.allElementsBoundByIndex.first(where: { $0.isHittable }) { return element }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date.now < deadline
        return query.firstMatch
    }

    @MainActor var editorText: XCUIElement { app.textViews.firstMatch }

    // MARK: 操作

    /// 每次写入用的记号，避免和之前跑过的测试混在一起。
    func marker(_ prefix: String) -> String {
        "\(prefix)\(UUID().uuidString.prefix(6))"
    }

    @MainActor func tap(_ element: XCUIElement, timeout: TimeInterval = 10, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "找不到：\(message.isEmpty ? element.description : message)", file: file, line: line)
        element.tap()
    }

    /// 写进编辑器（光标放到最后）。
    @MainActor func type(_ string: String) {
        let field = editorText
        focus(field)
        field.typeText(string)
    }

    /// 点“完成”保存，处理系统的“允许修改照片”确认，等编辑器关掉，确认 App 还活着。
    @MainActor func saveEditor(file: StaticString = #filePath, line: UInt = #line) {
        tap(app.buttons["完成"], "编辑器的完成按钮", file: file, line: line)
        allowPhotoChangeIfAsked()
        XCTAssertTrue(editorText.waitForNonExistence(timeout: 15), "保存后编辑器没有关闭", file: file, line: line)
        assertAlive(file: file, line: line)
    }

    @MainActor func assertAlive(file: StaticString = #filePath, line: UInt = #line) {
        // 闪退往往在保存后的照片库通知里，稍等一下再看。
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(app.state, .runningForeground, "App 不在前台了（闪退？）", file: file, line: line)
    }

    /// 回到日记标签的根页面（详情页上标签栏是收起的，先一路返回）。
    @MainActor func goToJournalRoot() {
        let back = app.buttons["BackButton"]
        for _ in 0..<5 {
            guard back.waitForExistence(timeout: 1), back.isHittable else { break }
            back.tap()
        }
        tap(tab("日记"))
    }

    /// 从日记列表打开含这段文字的日记（点的时候系统会自动滚到它）。
    @MainActor func openEntry(_ text: String) {
        goToJournalRoot()
        // 列表是懒加载的：在屏幕下面的卡片还没生成，要往下滑到它出现。
        let card = button(containing: text)
        for _ in 0..<10 where !card.waitForExistence(timeout: 1) { app.swipeUp() }
        tap(card, timeout: 5, "日记卡片“\(text)”")
        XCTAssertTrue(app.buttons["追加感想"].waitForExistence(timeout: 10), "没有进入详情页")
    }

    /// 点一下输入框，等它真的拿到键盘焦点再打字。
    @MainActor func focus(_ field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), "找不到输入框")
        for _ in 0..<3 {
            field.tap()
            if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertEqual(field.value(forKey: "hasKeyboardFocus") as? Bool, true, "输入框没有拿到焦点")
    }

    /// 收尾：把测试写在空白照片上的日记清掉（编辑成空、清除说明），照片回到空白，下次还能用。
    @MainActor func clearDiary(containing mark: String, file: StaticString = #filePath, line: UInt = #line) {
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
        assertAlive(file: file, line: line)
        goToJournalRoot()
        XCTAssertTrue(button(containing: mark).waitForNonExistence(timeout: 10), "清除后日记还在列表里", file: file, line: line)
    }

    /// 从“+”打开照片列表，选第一张还没写日记的照片，进入编辑器。
    @MainActor func startNewDiaryOnBlankPhoto() {
        tap(button(containing: "从照片写日记"), "“+”按钮")
        let blank = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "还没写日记的照片")).firstMatch
        tap(blank, timeout: 15, "还没写日记的照片")
        XCTAssertTrue(editorText.waitForExistence(timeout: 10), "编辑器没有出现")
    }

    // MARK: 系统弹窗

    @MainActor func allowPhotoAccessIfAsked() {
        tapSystemAlert(["允许完全访问", "Allow Full Access", "允许访问所有照片", "Allow Access to All Photos"], timeout: 3)
    }

    /// 修改不是本 App 建的照片时，系统会问一次。
    @MainActor func allowPhotoChangeIfAsked() {
        tapSystemAlert(["修改", "Modify", "允许", "Allow"], timeout: 3)
    }

    /// 第一次打开晚间提醒时系统问通知权限。
    @MainActor func allowNotificationsIfAsked() {
        tapSystemAlert(["允许", "Allow"], timeout: 5)
    }

    @MainActor func confirmPhotoDeletion() {
        XCTAssertTrue(tapSystemAlert(["删除", "Delete"], timeout: 10), "没有出现系统的删除确认")
    }

    @discardableResult
    @MainActor func tapSystemAlert(_ titles: [String], timeout: TimeInterval) -> Bool {
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout) else { return false }
        for title in titles {
            let button = alert.buttons[title]
            if button.exists { button.tap(); return true }
        }
        XCTFail("没认出来的系统弹窗：\(alert.label)，按钮：\(alert.buttons.allElementsBoundByIndex.map(\.label))")
        return false
    }
}
