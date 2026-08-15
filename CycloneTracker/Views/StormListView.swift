import SwiftUI

struct StormListView: View {
    @Bindable var store: CycloneStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.displayedCyclones) { cyclone in
                Button {
                    store.selectedCyclone = cyclone
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(cyclone.category.color)
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(cyclone.displayName)
                                    .font(.body.weight(.medium))
                                Text(cyclone.category.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(cyclone.basin.displayName) · \(cyclone.windKnots) kt · \(cyclone.pressureMB) hPa · \(cyclone.coordinate.formatted)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if cyclone.isActive {
                            Text("活跃")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.red.opacity(0.15), in: Capsule())
                                .foregroundStyle(.red)
                        }
                    }
                }
                .tint(.primary)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var navigationTitle: String {
        store.mode == .active
            ? "活跃热带气旋 (\(store.activeCyclones.count))"
            : "\(store.selectedDate.formatted(date: .abbreviated, time: .omitted)) \(store.selectedBasin.displayName) (\(store.historicalCyclones.count))"
    }
}
