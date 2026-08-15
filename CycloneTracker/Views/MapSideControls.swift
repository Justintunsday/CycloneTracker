import SwiftUI

struct MapSideControls: View {
    @Bindable var store: CycloneStore
    let onFit: () -> Void
    @State private var showList = false
    @State private var showDatePicker = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            VStack(spacing: 6) {
                Button {
                    store.mode = store.mode == .active ? .historical : .active
                    if store.mode == .historical, store.historicalCyclones.isEmpty {
                        Task { await store.loadHistorical() }
                    }
                } label: {
                    Image(systemName: store.mode == .active ? "hurricane" : "clock.arrow.circlepath")
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel(store.mode == .active ? "切换至历史模式" : "切换至实时模式")

                if store.mode == .historical {
                    Button {
                        showDatePicker = true
                    } label: {
                        Image(systemName: "calendar")
                            .frame(width: 34, height: 34)
                    }
                    .accessibilityLabel("选择日期")

                    Menu {
                        Picker("海盆", selection: $store.selectedBasin) {
                            ForEach(CycloneBasin.allCases) { basin in
                                Text(basin.displayName).tag(basin)
                            }
                        }
                    } label: {
                        Image(systemName: "globe.asia.australia.fill")
                            .frame(width: 34, height: 34)
                    }
                    .accessibilityLabel("选择海盆")

                    Menu {
                        Button("缓存当前海盆近10年") {
                            store.cacheRecentYears(basins: [store.selectedBasin])
                        }
                        Button("缓存全部海盆近10年") {
                            store.cacheRecentYears(basins: CycloneBasin.allCases)
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .frame(width: 34, height: 34)
                    }
                    .accessibilityLabel("缓存近10年数据")
                } else {
                    Button {
                        Task { await store.refreshActive() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 34, height: 34)
                    }
                    .accessibilityLabel("刷新实时数据")
                }

                Button(action: onFit) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("缩放至全部气旋")

                Button {
                    showList = true
                } label: {
                    Image(systemName: "list.bullet")
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("气旋列表")
            }
            .padding(6)
            .glassEffect(.regular, in: Capsule())

            if store.isCachingRecent {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(store.cachingMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button {
                        store.cancelCaching()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: Capsule())
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
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(store: store)
        }
        .sheet(isPresented: $showList) {
            StormListView(store: store)
        }
    }
}

struct DatePickerSheet: View {
    @Bindable var store: CycloneStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                DatePicker(
                    "日期",
                    selection: $store.selectedDate,
                    in: store.historicalDateRange,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)

                Button {
                    dismiss()
                } label: {
                    Text("确定")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
            }
            .padding()
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
