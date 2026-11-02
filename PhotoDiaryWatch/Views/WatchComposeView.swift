import SwiftUI

/// 口述一段：系统输入（听写、涂写、键盘），发给 iPhone 写进照片说明。
struct WatchComposeView: View {
    let assetID: String
    let mode: WatchWrite.Mode
    let day: DayStamp?

    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var sent: WatchWrite?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let image = store.image(assetID) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(.rect(cornerRadius: 14, style: .continuous))
                        .accessibilityHidden(true)
                }
                if let sent {
                    sentState(sent)
                } else {
                    prompt
                    TextFieldLink(prompt: Text(mode == .append ? "过了些日子，再看这张照片…" : "写下当时的感受")) {
                        Label(mode == .append ? "口述感想" : "口述日记", systemImage: "mic.fill")
                    } onSubmit: { text in
                        send(text)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(mode == .append ? "追加感想" : "写日记")
    }

    @ViewBuilder private var prompt: some View {
        if let day {
            Text(day == .today ? String(localized: "今天的照片") : String(localized: "拍摄于 \(DiaryDates.full(day))"))
                .font(.footnote.weight(.semibold))
        }
    }

    private func sentState(_ write: WatchWrite) -> some View {
        let confirmed = store.lastConfirmed == write.id
        return VStack(spacing: 8) {
            Image(systemName: confirmed ? "checkmark.circle.fill" : "paperplane.fill")
                .font(.title)
                .accessibilityHidden(true)
                .foregroundStyle(confirmed ? Color.green : Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
            Text(confirmed ? "已写进照片说明" : "已发到 iPhone")
                .font(.headline)
            Text(write.text)
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .multilineTextAlignment(.center)
            Button("完成") { dismiss() }
                .padding(.top, 4)
        }
        .animation(.snappy, value: confirmed)
    }

    private func send(_ text: String) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let write = WatchWrite(assetID: assetID, text: body, mode: mode)
        store.send(write)
        withAnimation(.snappy) { sent = write }
    }
}
