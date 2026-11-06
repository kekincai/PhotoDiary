import WidgetKit
import SwiftUI
import AppIntents

// MARK: 控制中心、锁屏底部、操作按钮：写日记
//
// 按下去打开 App，直接是最新一张照片的编辑器（写过就追加感想）。
// WriteLatestPhotoIntent 在 App 和扩展里都编译，supportedModes 是 .foreground，系统在 App 里执行它。

struct WriteDiaryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.kejincai.photodiary.write") {
            ControlWidgetButton(action: WriteLatestPhotoIntent()) {
                Label("写日记", systemImage: "square.and.pencil")
            }
        }
        .displayName("写日记")
    }
}
