import SwiftUI

struct CachingToast: View {
    @Bindable var store: CycloneStore

    var body: some View {
        Group {
            if store.isCachingRecent {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(store.cachingMessage)
                        .font(.caption2)
                        .lineLimit(1)
                    Button {
                        store.cancelCaching()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(.oceanGlass.opacity(0.08)), in: Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.trailing, 12)
        .padding(.bottom, 8)
        .animation(.spring(duration: 0.5, bounce: 0.25), value: store.isCachingRecent)
    }
}
