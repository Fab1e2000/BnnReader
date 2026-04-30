import SwiftUI

struct TOCView: View {
    let entries: [TOCEntry]
    let onSelect: (TOCEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────────
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "list.bullet.indent")
                    .foregroundStyle(.secondary)
                Text("目录")
                    .font(.headline)
                Spacer()
                Text("\(entries.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quinary, in: .capsule)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if entries.isEmpty {
                ContentUnavailableView(
                    "无标题",
                    systemImage: "text.alignleft",
                    description: Text("该文件没有任何标题。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            Button { onSelect(entry) } label: {
                                tocRow(entry)
                            }
                            .buttonStyle(TOCRowButtonStyle())
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(width: 280)
        .frame(minHeight: 300, maxHeight: 680)
    }

    private func tocRow(_ entry: TOCEntry) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor(for: entry.level))
                .frame(width: dotSize(for: entry.level), height: dotSize(for: entry.level))
                .padding(.leading, CGFloat(entry.level - 1) * 14 + 6)

            Text(entry.text)
                .font(entryFont(for: entry.level))
                .foregroundStyle(entry.level <= 2 ? Color.primary : Color.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func dotSize(for level: Int) -> CGFloat {
        level == 1 ? 6 : level == 2 ? 5 : 4
    }

    private func entryFont(for level: Int) -> Font {
        switch level {
        case 1:  return .system(size: 13, weight: .semibold)
        case 2:  return .system(size: 13, weight: .regular)
        default: return .system(size: 12, weight: .regular)
        }
    }

    private func dotColor(for level: Int) -> Color {
        switch level {
        case 1:  return .accentColor
        case 2:  return .accentColor.opacity(0.65)
        default: return .secondary.opacity(0.4)
        }
    }
}

private struct TOCRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
    }
}
