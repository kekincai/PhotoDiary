import SwiftUI
import Photos

/// 所有标签及数量；支持批量改名、合并。
struct TagsView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.brand) private var brand
    @State private var selection = Set<String>()
    @State private var editMode: EditMode = .inactive
    @State private var renaming: Set<String>?
    @State private var newName = ""
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        List(selection: $selection) {
            if store.tagCounts.isEmpty {
                EmptyHint(symbol: "number", title: "还没有标签", message: "在日记里写 #话题#，标签会自动出现，也会同步成照片的关键词。")
                    .listRowBackground(Color.clear)
            }
            ForEach(store.tagCounts, id: \.name) { tag in
                NavigationLink(value: Route.tag(tag.name)) {
                    HStack {
                        Text("#\(tag.name)#")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(brand)
                        Spacer()
                        Text("\(tag.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.meta)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("改名") { startRename([tag.name]) }.tint(brand)
                }
                .contextMenu {
                    Button("改名", systemImage: "pencil") { startRename([tag.name]) }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("标签")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !store.tagCounts.isEmpty {
                    Button(editMode.isEditing ? "完成" : "选择") {
                        withAnimation(.snappy) {
                            editMode = editMode.isEditing ? .inactive : .active
                            selection.removeAll()
                        }
                    }
                }
            }
            if editMode.isEditing {
                ToolbarItem(placement: .bottomBar) {
                    Button(selection.count > 1 ? "合并 \(selection.count) 个标签" : "改名") {
                        startRename(selection)
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
        .overlay { if working { ProgressView().controlSize(.large) } }
        .alert(renameTitle, isPresented: .constant(renaming != nil)) {
            TextField("标签名", text: $newName)
            Button("取消", role: .cancel) { renaming = nil }
            Button("确定") { commitRename() }
        } message: {
            Text("会修改所有相关照片的说明，并同步照片关键词。")
        }
        .alert("没有完成", isPresented: .constant(errorMessage != nil)) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var renameTitle: String {
        (renaming?.count ?? 0) > 1 ? "合并为" : "改名为"
    }

    private func startRename(_ tags: Set<String>) {
        newName = store.tagCounts.first(where: { tags.contains($0.name) })?.name ?? ""
        renaming = tags
    }

    private func commitRename() {
        guard let olds = renaming else { return }
        renaming = nil
        let name = newName.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#＃"))
        guard CaptionFormat.isValidTagName(name) else {
            errorMessage = "标签不能为空、不能包含 # 或换行，最多 \(CaptionFormat.maxTagLength) 个字。"
            return
        }
        working = true
        Task {
            defer { working = false }
            do {
                try await store.renameTags(olds, to: name)
                editMode = .inactive
                selection.removeAll()
            } catch {
                let e = error as NSError
                if !(e.domain == PHPhotosErrorDomain && e.code == PHPhotosError.userCancelled.rawValue) {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct TagEntriesView: View {
    let tag: String
    @Environment(DiaryStore.self) private var store

    var body: some View {
        let entries = store.entries(tagged: tag)
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    NavigationLink(value: Route.entry(entry.id)) {
                        EntryRow(entry: entry, showsSeparator: entry.id != entries.last?.id)
                    }
                    .buttonStyle(.row())
                }
            }
            .padding(.vertical, 8)
        }
        .overlay {
            if entries.isEmpty { EmptyHint(symbol: "number", title: "没有日记", message: "这个标签下已经没有日记了。") }
        }
        .navigationTitle("#\(tag)#")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 其他来源的说明：默认不进日记流；编辑后转为日记。
struct ExternalCaptionsView: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List {
            Section {
                Toggle("在日记里显示", isOn: $store.showExternal)
            } footer: {
                Text("这些说明没有写作日期行，例如 Lightroom 导入时带来的 IPTC 说明或以前手写的说明。在本 App 编辑后会成为日记。")
            }
            Section {
                ForEach(store.externals) { entry in
                    NavigationLink(value: Route.entry(entry.id)) {
                        HStack(spacing: 12) {
                            AssetImage(id: entry.id, pointSize: CGSize(width: 48, height: 48))
                                .frame(width: 48, height: 48)
                                .clipShape(.rect(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.caption).font(.diary(15)).lineLimit(2)
                                Text(DiaryDates.full(entry.day)).font(.caption).foregroundStyle(Color.meta)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if store.externals.isEmpty {
                EmptyHint(symbol: "doc.text", title: "没有其他来源的说明", message: "照片库里没有不属于日记的说明。")
            }
        }
        .navigationTitle("其他来源的说明")
        .navigationBarTitleDisplayMode(.inline)
    }
}
