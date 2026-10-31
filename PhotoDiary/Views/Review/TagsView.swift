import SwiftUI
import Photos

/// 所有标签，相簿式两列封面；“选择”后可批量改名、合并。
struct TagsView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.brand) private var brand
    @State private var selecting = false
    @State private var selection = Set<String>()
    @State private var renaming: Set<String>?
    @State private var newName = ""
    @State private var working = false
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)

    var body: some View {
        ScrollView {
            if store.tagCounts.isEmpty {
                EmptyHint(title: "还没有标签", message: "在日记里写 #话题#，这里就会出现，也会同步成照片的关键词。")
            }
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(store.tagCounts, id: \.name) { tag in
                    cover(tag)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .navigationTitle("标签")
        .navigationSubtitle(subtitle)
        .toolbarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !store.tagCounts.isEmpty {
                    Button(selecting ? "完成" : "选择") {
                        withAnimation(.snappy) {
                            selecting.toggle()
                            selection.removeAll()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            if selecting {
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

    private var subtitle: String {
        let n = store.tagCounts.count
        return n == 0 ? "" : String(localized: "\(n) 个标签 · 选择后可改名、合并")
    }

    @ViewBuilder
    private func cover(_ tag: DiaryStore.TagCount) -> some View {
        let detail = coverDetail(tag)
        if selecting {
            let selected = selection.contains(tag.name)
            Button {
                if selected { selection.remove(tag.name) } else { selection.insert(tag.name) }
            } label: {
                TagCover(name: tag.name, detail: detail)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24, weight: .medium))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(selected ? Color.white : Color.white, selected ? brand : Color.black.opacity(0.15))
                            .shadow(color: .black.opacity(0.25), radius: 2)
                            .padding(10)
                    }
                    .opacity(selection.isEmpty || selected ? 1 : 0.7)
            }
            .buttonStyle(.press)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .sensoryFeedback(.selection, trigger: selected)
        } else {
            NavigationLink(value: Route.tag(tag.name)) {
                TagCover(name: tag.name, detail: detail)
            }
            .buttonStyle(.press)
            .contextMenu {
                Button("改名", systemImage: "pencil") { startRename([tag.name]) }
            }
        }
    }

    /// 8 篇 · 最近 10月24日；只有一篇时直接写日期。
    private func coverDetail(_ tag: DiaryStore.TagCount) -> String {
        guard let latest = store.entries(tagged: tag.name).first else { return String(localized: "\(tag.count) 篇") }
        let date = DiaryDates.short(latest.day)
        return tag.count == 1 ? String(localized: "\(tag.count) 篇 · \(date)") : String(localized: "\(tag.count) 篇 · 最近 \(date)")
    }

    private var renameTitle: Text {
        (renaming?.count ?? 0) > 1 ? Text("合并为") : Text("改名为")
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
            errorMessage = String(localized: "标签不能为空、不能包含 # 或换行，最多 \(CaptionFormat.maxTagLength) 个字。")
            return
        }
        working = true
        Task {
            defer { working = false }
            do {
                try await store.renameTags(olds, to: name)
                selecting = false
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

/// 标签封面：最近一篇的照片，下方标签名和篇数。
struct TagCover: View {
    let name: String
    let detail: String
    @Environment(DiaryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .background(Color.tile)
                .overlay {
                    if let id = store.entries(tagged: name).first?.id {
                        AssetImage(id: id)
                    }
                }
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                .padding(.bottom, 5)
            Text(verbatim: "#\(name)#")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(Color.meta)
                .lineLimit(1)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// 某个标签下的日记：和首页一样的大照片卡片。
struct TagEntriesView: View {
    let tag: String
    @Environment(DiaryStore.self) private var store
    @Environment(\.zoomNamespace) private var namespace

    var body: some View {
        let entries = store.entries(tagged: tag)
        ScrollView {
            LazyVStack(spacing: 30) {
                ForEach(entries) { entry in
                    NavigationLink(value: Route.entry(entry.id)) {
                        EntryCard(entry: entry, namespace: namespace)
                    }
                    .buttonStyle(.press)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .overlay {
            if entries.isEmpty { EmptyHint(title: "这个标签下没有日记了", message: "可能已经改名或合并到别的标签。") }
        }
        .navigationTitle(Text(verbatim: "#\(tag)#"))
        .navigationSubtitle(Text("\(entries.count) 篇"))
        .toolbarTitleDisplayMode(.large)
    }
}
