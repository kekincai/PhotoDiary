import Foundation
import OSLog

/// 统一日志，基于系统的 os.Logger。
///
/// - 看日志：Xcode 控制台，或 Console.app 里按 subsystem `com.kejincai.photodiary` 过滤；
///   模拟器用 `xcrun simctl spawn booted log stream --level debug --predicate 'subsystem == "com.kejincai.photodiary"'`。
/// - 级别：debug 只在内存里、info 是常规流程、notice 是值得留意的状态变化、error 是失败、fault 是不该发生的情况。
/// - 隐私：说明正文一律不记，这是唯一可靠的保证。字符串插值默认是 private，真机上不连调试器时显示为 <private>，
///   但模拟器和调试时照常可见，所以不能靠它藏内容。只有计数、状态、错误这类不含个人内容的值才标 `.public`。
/// - 耗时：`Log.signposter` 打的区间在 Instruments 的 Points of Interest 里能看到。
nonisolated enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.kejincai.photodiary"

    /// 启动、授权、前后台切换。
    static let app = Logger(subsystem: subsystem, category: "app")
    /// 全量扫描、增量同步、change token。
    static let sync = Logger(subsystem: subsystem, category: "sync")
    /// 索引文件读写。
    static let index = Logger(subsystem: subsystem, category: "index")
    /// 写说明、关键词、删除照片。
    static let library = Logger(subsystem: subsystem, category: "library")
    /// 反向地理编码。
    static let places = Logger(subsystem: subsystem, category: "places")
    /// 缩略图、大图、实况照片、视频请求。
    static let images = Logger(subsystem: subsystem, category: "images")
    /// 和 Apple Watch 之间的快照、口述的段落。
    static let watch = Logger(subsystem: subsystem, category: "watch")

    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)

    // MARK: 导出

    /// 本次运行以来本 App 的日志，纯文本。设置里“导出诊断日志”用，方便在没连 Xcode 的设备上复现问题。
    @concurrent
    static func export() async throws -> String {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", subsystem))
        let time = Date.ISO8601FormatStyle(includingFractionalSeconds: true).dateSeparator(.dash).timeZone(separator: .omitted)
        let info = Bundle.main.infoDictionary
        var out = """
        PhotoDiary \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))
        \(ProcessInfo.processInfo.operatingSystemVersionString)
        导出于 \(Date.now.formatted(time))

        """
        for case let entry as OSLogEntryLog in entries {
            out += "\(entry.date.formatted(time)) [\(entry.category)] \(label(entry.level)) \(entry.composedMessage)\n"
        }
        return out
    }

    private static func label(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .notice: "NOTICE"
        case .error: "ERROR"
        case .fault: "FAULT"
        default: "-"
        }
    }
}
