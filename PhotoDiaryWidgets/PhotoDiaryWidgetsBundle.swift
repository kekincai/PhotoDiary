import WidgetKit
import SwiftUI

@main
struct PhotoDiaryWidgetsBundle: WidgetBundle {
    var body: some Widget {
        OnThisDayWidget()
        WriteTodayWidget()
    }
}

/// 小组件按 App 里选的界面语言显示（快照里带着）；没有快照时跟系统。
enum WidgetLanguage {
    static func apply(_ code: String?) {
        guard let code, let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return }
        Bundle.app = bundle
        let locale: Locale
        if let region = Locale.current.region?.identifier {
            locale = Locale(identifier: "\(code)_\(region)")
        } else {
            locale = Locale(identifier: code)
        }
        Locale.app = locale
        DiaryDates.locale = locale
    }
}
