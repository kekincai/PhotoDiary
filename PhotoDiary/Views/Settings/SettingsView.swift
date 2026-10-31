import SwiftUI
import Photos
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("brand") private var brand: BrandColor = .lake
    @State private var confirmRebuild = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("主题色") {
                    HStack(spacing: 0) {
                        ForEach(BrandColor.allCases) { option in
                            Button {
                                withAnimation(.snappy) { brand = option }
                            } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 40, height: 40)
                                        .overlay {
                                            if brand == option {
                                                Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(.white)
                                            }
                                        }
                                        .padding(3)
                                        .overlay(Circle().strokeBorder(brand == option ? option.color : .clear, lineWidth: 2))
                                    Text(option.name).font(.caption).foregroundStyle(Color.ink)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.press)
                            .accessibilityAddTraits(brand == option ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                    .sensoryFeedback(.selection, trigger: brand)
                }

                Section("照片访问") {
                    LabeledContent("权限", value: accessText)
                    if store.isLimited {
                        Button("选择更多照片") { LimitedLibrary.present() }
                    }
                    Button("在“设置”中修改") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }

                Section {
                    ShareLink(item: MarkdownExport(text: store.markdownExport()),
                              preview: SharePreview("照片日记.md", image: Image(systemName: "doc.text"))) {
                        Label("导出全部日记（Markdown）", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        confirmRebuild = true
                    } label: {
                        Label("重建索引", systemImage: "arrow.clockwise")
                    }
                } footer: {
                    Text("日记保存在照片的“说明”里，随照片经 iCloud 同步。本 App 只保存可以随时重建的索引，删除 App 不会丢失日记。")
                }

                Section("说明格式") {
                    Text("风很舒服，第一次用新镜头拍日落 #旅行#\n— 2026.10.31\n\n三年后再看，还是喜欢这张\n— 2029.11.02")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color.meta)
                    Text("每段末尾一行是写作日期；#话题# 会同步为照片关键词。在照片 App 的说明栏里按这个格式写，也会出现在日记里。")
                        .font(.footnote)
                        .foregroundStyle(Color.meta)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog("重建索引？", isPresented: $confirmRebuild, titleVisibility: .visible) {
                Button("重新读取整个照片库") { store.rebuildIndex(); dismiss() }
            } message: {
                Text("会重新读取所有照片的说明，照片多时需要一些时间。")
            }
        }
        .tint(brand.color)
    }

    private var accessText: String {
        switch store.authorization {
        case .authorized: "完整访问"
        case .limited: "有限访问"
        case .denied, .restricted: "未允许"
        default: "未设置"
        }
    }
}

struct MarkdownExport: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { export in
            let url = URL.temporaryDirectory.appending(path: "照片日记.md")
            try export.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
