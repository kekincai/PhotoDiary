import SwiftUI

// MARK: 无障碍：读给 VoiceOver 听的文字
//
// 屏幕上的写法是给眼睛看的（“#旅行#”、“周五 · 10月30日 · 杉并区”），直接读出来是“井号旅行井号”“点”。
// 这里把同样的信息按句子组织好，卡片、行、网格、地图都用同一份。

enum Spoken {
    /// 标签“旅行”
    static func tag(_ name: String) -> String {
        String(localized: "标签“\(name)”", bundle: .app, locale: .app)
    }

    /// 地点：杉并区
    static func place(_ name: String) -> String {
        String(localized: "地点：\(name)", bundle: .app, locale: .app)
    }

    /// 标签：旅行、登山
    static func tags(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let list = names.formatted(.list(type: .and).locale(.app))
        return String(localized: "标签：\(list)", bundle: .app, locale: .app)
    }
}

extension DiaryEntry {
    /// 一篇日记读出来的样子：日期和地点、标题、预览、标签、段数、媒体类型，用句号隔开。
    /// 例如“10月30日 周五，杉并区。买到了熟透的无花果。切开的时候汁水流到桌布上。标签：美食”。
    var spokenSummary: String {
        var when = DiaryDates.dayTitle(displayDate)
        if day.year != DayStamp.today.year { when = DiaryDates.fullWithWeekday(displayDate) }
        var parts = [placeName.map { "\(when)，\($0)" } ?? when]
        if !title.isEmpty { parts.append(title) }
        if !preview.isEmpty { parts.append(preview) }
        if let tags = Spoken.tags(tags) { parts.append(tags) }
        if segments.count > 1 { parts.append(String(localized: "\(segments.count) 段", bundle: .app, locale: .app)) }
        switch mediaKind {
        case .photo: break
        case .video: parts.append(String(localized: "视频", bundle: .app, locale: .app))
        case .livePhoto: parts.append(String(localized: "实况照片", bundle: .app, locale: .app))
        }
        return parts.joined(separator: "。")
    }
}

extension View {
    /// 浮动的玻璃按钮只有图标、字号固定：开了大字时长按显示大号的图标和名字（系统标签栏的做法）。
    func largeContent(_ title: String, systemImage: String) -> some View {
        accessibilityShowsLargeContentViewer {
            Label(title, systemImage: systemImage)
        }
    }
}

/// 有些手势在 VoiceOver、切换控制下做不了（下拉清除、点照片放大），要换成看得见的按钮。
struct AssistiveTechnology {
    let voiceOver: Bool
    let switchControl: Bool
    var isRunning: Bool { voiceOver || switchControl }
}

extension EnvironmentValues {
    var assistiveTechnology: AssistiveTechnology {
        AssistiveTechnology(voiceOver: accessibilityVoiceOverEnabled, switchControl: accessibilitySwitchControlEnabled)
    }
}
