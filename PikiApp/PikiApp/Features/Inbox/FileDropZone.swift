import SwiftUI

struct FileDropZone: View {
    let onDrop: ([URL]) -> Void
    let onBrowse: () -> Void
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .foregroundStyle(isTargeted ? Theme.primary : Theme.border)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Theme.primaryLight : .clear)
                )

            VStack(spacing: 8) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 24))
                    .foregroundStyle(isTargeted ? Theme.primary : Theme.textTertiary)
                Text("拖入文件或点击浏览")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(height: 80)
        .contentShape(Rectangle())
        .onTapGesture(perform: onBrowse)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let data = try? await provider.loadItem(
                        forTypeIdentifier: "public.file-url"
                    ) as? Data,
                       let path = String(data: data, encoding: .utf8),
                       let url = URL(string: path) {
                        urls.append(url)
                    }
                }
                if !urls.isEmpty {
                    await MainActor.run { onDrop(urls) }
                }
            }
            return true
        }
    }
}
