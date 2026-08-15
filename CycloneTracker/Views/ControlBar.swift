import SwiftUI

struct ControlBar: View {
    @Bindable var store: CycloneStore
    let onFit: () -> Void
    @State private var showList = false

    var body: some View {
        VStack(spacing: 8) {
            Picker("模式", selection: $store.mode) {
                ForEach(CycloneStore.Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if store.mode == .historical {
                HStack(spacing: 10) {
                    DatePicker(
                        "日期",
                        selection: $store.selectedDate,
                        in: store.historicalDateRange,
                        displayedComponents: .date
                    )
                    .labelsHidden()

                    Menu {
                        Picker("海盆", selection: $store.selectedBasin) {
                            ForEach(CycloneBasin.allCases) { basin in
                                Text(basin.displayName).tag(basin)
                            }
                        }
                    } label: {
                        Label(store.selectedBasin.displayName, systemImage: "globe.asia.australia.fill")
                            .font(.subheadline)
                    }

                    Spacer()

                    Button(action: onFit) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    Button {
                        showList = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Text("更新: \(store.lastRefresh?.formatted(date: .omitted, time: .shortened) ?? "—")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await store.refreshActive() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    Button(action: onFit) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    Button {
                        showList = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .onChange(of: store.mode) { _, newMode in
            if newMode == .historical, store.historicalCyclones.isEmpty {
                Task { await store.loadHistorical() }
            }
        }
        .onChange(of: store.selectedDate) { _, _ in
            if store.mode == .historical {
                Task { await store.loadHistorical() }
            }
        }
        .onChange(of: store.selectedBasin) { _, _ in
            if store.mode == .historical {
                Task { await store.loadHistorical() }
            }
        }
        .sheet(isPresented: $showList) {
            StormListView(store: store)
        }
    }
}
