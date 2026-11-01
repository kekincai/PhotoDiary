import SwiftUI

/// 隐藏的说明：上面是已隐藏的，红色减号移出；下面是照片库里常见的短说明，绿色加号隐藏。
/// 和系统列表编辑的加减号一致，状态一眼能看出来，不用再写说明。
struct HiddenCaptionsView: View {
    @Environment(DiaryStore.self) private var store
    @State private var captions = CaptionFilter.patterns
    @State private var adding = false
    @State private var draft = ""

    var body: some View {
        let counts = store.hiddenCaptionCounts()
        let suggestions = store.frequentShortCaptions()
        Form {
            Section {
                ForEach(captions, id: \.self) { caption in
                    row(caption, count: counts[CaptionFilter.normalized(caption)] ?? 0, hidden: true)
                        // 自己写左滑按钮：系统 onDelete 的“删除”跟系统语言，App 内切换语言时不会变。
                        .swipeActions {
                            Button("取消隐藏", systemImage: "eye") { show(caption) }
                                .tint(.red)
                        }
                }
                Button("添加…", systemImage: "plus") { adding = true }
            } header: {
                Text("已隐藏")
            } footer: {
                Text("说明和这些文字完全一样的照片不算日记。")
            }
            if !suggestions.isEmpty {
                Section("常见的短说明") {
                    ForEach(suggestions, id: \.caption) { item in
                        row(item.caption, count: item.count, hidden: false)
                    }
                }
            }
        }
        .navigationTitle("隐藏的说明")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: captions)
        .alert("隐藏这段说明", isPresented: $adding) {
            TextField("说明文字，例如 0", text: $draft)
            Button("取消", role: .cancel) { draft = "" }
            Button("隐藏") { hide(draft); draft = "" }
        }
    }

    private func row(_ caption: String, count: Int, hidden: Bool) -> some View {
        Button {
            if hidden { show(caption) } else { hide(caption) }
        } label: {
            HStack(spacing: Metrics.Spacing.m) {
                Image(systemName: hidden ? "minus.circle.fill" : "plus.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, hidden ? Color.red : Color.green)
                Text(verbatim: caption)
                    .font(.body.monospaced())
                    .foregroundStyle(hidden ? Color.meta : Color.ink)
                    .strikethrough(hidden, color: Color.meta)
                Spacer()
                if count > 0 {
                    Text("\(count) 张")
                        .monospacedDigit()
                        .foregroundStyle(Color.meta)
                }
            }
        }
        .accessibilityLabel(hidden ? Text("取消隐藏“\(caption)”") : Text("隐藏“\(caption)”，\(count) 张照片"))
    }

    private func hide(_ caption: String) {
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              !captions.contains(where: { CaptionFilter.normalized($0) == CaptionFilter.normalized(text) }) else { return }
        withAnimation(.snappy) { captions.append(text) }
        save()
    }

    private func show(_ caption: String) {
        withAnimation(.snappy) { captions.removeAll { $0 == caption } }
        save()
    }

    private func save() {
        CaptionFilter.patterns = captions
        store.captionFilterChanged()
    }
}
