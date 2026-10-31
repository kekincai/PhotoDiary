import SwiftUI
import Photos
import UIKit

/// 编辑器状态：正文、光标前正在输入的标签，以及插入/补全标签的命令。
@Observable
final class EditorController {
    var text: String
    /// 光标前正在输入的标签（“#朋” → “朋”）；nil 表示不在输入标签。
    private(set) var tagQuery: String?
    var isEditing = false

    @ObservationIgnored weak var textView: UITextView?
    @ObservationIgnored var brand: UIColor = .systemBlue

    init(text: String) { self.text = text }

    func insertHash() {
        guard let tv = textView else { return }
        if !tv.isFirstResponder { tv.becomeFirstResponder() }
        tv.insertText("#")
    }

    /// 把“#朋”补全为“#朋友# ”。
    func complete(_ tag: String) {
        guard let tv = textView, let range = queryRange(in: tv) else { return }
        guard let start = tv.position(from: tv.beginningOfDocument, offset: range.location),
              let end = tv.position(from: start, offset: range.length),
              let textRange = tv.textRange(from: start, to: end) else { return }
        tv.replace(textRange, withText: "#\(tag)# ")
    }

    func dismissKeyboard() { textView?.resignFirstResponder() }
    func focus() { textView?.becomeFirstResponder() }

    // MARK: 内部

    fileprivate func textDidChange(in tv: UITextView) {
        text = tv.text
        updateQuery(in: tv)
        // 输入法正在组字时不改属性，避免打断候选。
        if tv.markedTextRange == nil { highlight(tv) }
    }

    fileprivate func selectionDidChange(in tv: UITextView) {
        updateQuery(in: tv)
        if tv.markedTextRange == nil { highlight(tv) }
    }

    private func updateQuery(in tv: UITextView) {
        let newQuery: String? = queryRange(in: tv).map { r in
            let ns = tv.text as NSString
            return ns.substring(with: NSRange(location: r.location + 1, length: r.length - 1))
        }
        if newQuery != tagQuery { tagQuery = newQuery }
    }

    /// 光标前未闭合的 “#xxx” 的范围（UTF-16）。
    private func queryRange(in tv: UITextView) -> NSRange? {
        guard tv.selectedRange.length == 0 else { return nil }
        let caret = tv.selectedRange.location
        let ns = tv.text as NSString
        let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
        let prefix = ns.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        // 去掉已经闭合的标签后，最后一个 # 之后的内容就是正在输入的标签。
        var searchFrom = prefix.startIndex
        if let lastTag = CaptionFormat.tagMatches(in: prefix).last { searchFrom = lastTag.range.upperBound }
        let tail = prefix[searchFrom...]
        guard let hash = tail.lastIndex(where: { $0 == "#" || $0 == "＃" }) else { return nil }
        let query = tail[tail.index(after: hash)...]
        guard query.count <= CaptionFormat.maxTagLength, !query.contains(where: \.isWhitespace) else { return nil }
        let location = lineStart + prefix[..<hash].utf16.count
        return NSRange(location: location, length: caret - location)
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 11
        return [
            .font: DiaryFonts.shared.uiFont(size: 19),
            .foregroundColor: UIColor.label,
            .paragraphStyle: style,
        ]
    }

    /// 标签在正文里高亮；正在输入的标签加下划线。
    func highlight(_ tv: UITextView) {
        let storage = tv.textStorage
        let full = NSRange(location: 0, length: storage.length)
        let text = tv.text ?? ""
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: full)
        let bold = DiaryFonts.shared.uiFont(size: 19, bold: true)
        for match in CaptionFormat.tagMatches(in: text) {
            let r = NSRange(match.range, in: text)
            storage.addAttributes([.foregroundColor: brand, .font: bold], range: r)
        }
        if let q = queryRange(in: tv) {
            storage.addAttributes([.foregroundColor: brand, .underlineStyle: NSUnderlineStyle.single.rawValue], range: q)
        }
        storage.endEditing()
        tv.typingAttributes = baseAttributes
    }
}

/// UITextView：衬线正文、标签高亮、键盘上方由 SwiftUI 提供工具栏。
struct DiaryTextView: UIViewRepresentable {
    let controller: EditorController
    var autofocus = true
    @Environment(\.brand) private var brand

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 24, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = true
        tv.keyboardDismissMode = .interactive
        tv.alwaysBounceVertical = true
        tv.delegate = context.coordinator
        tv.tintColor = UIColor(brand)
        tv.text = controller.text
        tv.accessibilityLabel = "日记正文"
        controller.textView = tv
        controller.brand = UIColor(brand)
        controller.highlight(tv)
        if autofocus {
            Task { tv.becomeFirstResponder() }
        }
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        controller.brand = UIColor(brand)
        tv.tintColor = UIColor(brand)
    }

    func makeCoordinator() -> Coordinator { Coordinator(controller) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let controller: EditorController
        init(_ controller: EditorController) { self.controller = controller }

        func textViewDidChange(_ tv: UITextView) { controller.textDidChange(in: tv) }
        func textViewDidChangeSelection(_ tv: UITextView) { controller.selectionDidChange(in: tv) }
        func textViewDidBeginEditing(_ tv: UITextView) { controller.isEditing = true }
        func textViewDidEndEditing(_ tv: UITextView) { controller.isEditing = false }
    }
}
