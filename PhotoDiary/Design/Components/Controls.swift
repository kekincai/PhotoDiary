import SwiftUI

/// 浮在内容上的玻璃分段控件（日记的四种视图、从照片添加的范围）。
struct GlassSegmented<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    /// 点已选中的那一段。
    var onReselect: (() -> Void)? = nil
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    if selected { onReselect?() } else { selection = option }
                } label: {
                    Text(title(option))
                        .font(.system(size: 14, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.ink : Color.inkSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, Metrics.Spacing.m)
                        .frame(minWidth: 58, minHeight: 32)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Color.primary.opacity(0.075))
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.press)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(Metrics.Spacing.xs)
        .glassEffect(.regular.interactive(), in: .capsule)
        .animation(.snappy, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// 分组标题（22pt 半粗）；可点的组带灰色箭头。
struct SectionTitle: View {
    let title: String
    var chevron = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.ink)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 胶囊：灰底（地点、时间）或主题色浅底（标签）。
struct Chip<Content: View>: View {
    var height: CGFloat = 36
    var fill: Color = .tile
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) { content }
            .padding(.horizontal, Metrics.Spacing.l)
            .frame(height: height)
            .background(fill, in: .capsule)
    }
}

/// 空状态：一句话说清楚是什么空了，最多给一个动作。不放大图标，也不再加一行解释。
struct EmptyHint: View {
    let title: LocalizedStringKey
    var action: (label: LocalizedStringKey, perform: () -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.ink)
            if let action {
                Button(action.label, action: action.perform)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, Metrics.Spacing.s)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.text)
        .padding(.vertical, 40)
    }
}

/// 自动换行排列的标签。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > width, !rows[rows.count - 1].indices.isEmpty {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            rows[rows.count - 1].indices.append(i)
            rows[rows.count - 1].width += size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
