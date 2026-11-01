import SwiftUI
import CoreText

// MARK: 字体：日记正文用衬线体，界面用系统字体

/// 宋体（Songti SC）是系统按需下载的字体；下载完成前先用系统衬线体。
@Observable
final class DiaryFonts {
    static let shared = DiaryFonts()

    static let regularName = "STSongti-SC-Regular"
    static let boldName = "STSongti-SC-Bold"

    private(set) var songtiReady: Bool = DiaryFonts.isInstalled(DiaryFonts.regularName)

    static func isInstalled(_ name: String) -> Bool {
        UIFont(name: name, size: 12) != nil
    }

    func prepare() {
        guard !songtiReady else { return }
        Self.download([Self.regularName, Self.boldName])
    }

    /// 进度回调在 CoreText 的后台队列上执行，不能继承主线程隔离。
    nonisolated private static func download(_ names: [String]) {
        let descriptors = names.map {
            CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: $0] as CFDictionary)
        } as CFArray
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler(descriptors, nil) { @Sendable state, _ in
            if state == .didFinish {
                Task { @MainActor in
                    DiaryFonts.shared.songtiReady = DiaryFonts.isInstalled(DiaryFonts.regularName)
                }
            }
            return true
        }
    }

    /// 宋体下载完成前的系统衬线体。每段正文每次刷新都要用，按字号缓存。
    @ObservationIgnored private var fallbackCache: [String: Font] = [:]

    func fallbackFont(size: CGFloat, bold: Bool, style: Font.TextStyle) -> Font {
        let key = "\(size)|\(bold)|\(style)"
        if let font = fallbackCache[key] { return font }
        let font = Font(uiFont(size: size, bold: bold, textStyle: style.uiKit))
        fallbackCache[key] = font
        return font
    }

    func uiFont(size: CGFloat, bold: Bool = false, textStyle: UIFont.TextStyle = .body) -> UIFont {
        let base: UIFont
        if songtiReady, let f = UIFont(name: bold ? Self.boldName : Self.regularName, size: size) {
            base = f
        } else {
            let system = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
            base = UIFont(descriptor: system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor, size: size)
        }
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
    }
}

extension Font {
    /// 日记正文字体，随动态字体缩放。
    static func diary(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        if DiaryFonts.shared.songtiReady {
            return .custom(bold ? DiaryFonts.boldName : DiaryFonts.regularName, size: size, relativeTo: style)
        }
        return DiaryFonts.shared.fallbackFont(size: size, bold: bold, style: style)
    }
}

extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}
