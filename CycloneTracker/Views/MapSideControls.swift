import SwiftUI

struct MapSideControls: View {
    @Bindable var store: CycloneStore
    let onFit: () -> Void
    @State private var showList = false
    @State private var showDatePicker = false

    var body: some View {
        VStack(spacing: 10) {
            dataGroup
            mapGroup
        }
        .animation(.spring(duration: 0.45, bounce: 0.3), value: store.mode)
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

    private func toggleMode() {
        store.mode = store.mode == .active ? .historical : .active
        if store.mode == .historical, store.historicalCyclones.isEmpty {
            Task { await store.loadHistorical() }
        }
    }

    private var dataGroup: some View {
        VStack(spacing: 10) {
            if store.mode == .active {
                Button(action: toggleMode) {
                    Image(systemName: "hurricane")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("切换至历史模式")
            } else {
                Button(action: toggleMode) {
                    Image(systemName: "clock.arrow.circlepath")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glassProminent)
                .accessibilityLabel("切换至实时模式")
            }

            if store.mode == .historical {
                Button {
                    showDatePicker = true
                } label: {
                    Image(systemName: "calendar")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("选择日期")
                .transition(.scale(scale: 0.5).combined(with: .opacity))

                Menu {
                    Picker("海盆", selection: $store.selectedBasin) {
                        ForEach(CycloneBasin.allCases) { basin in
                            Text(basin.displayName).tag(basin)
                        }
                    }
                } label: {
                    Image(systemName: "globe.asia.australia.fill")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("选择海盆")
                .transition(.scale(scale: 0.5).combined(with: .opacity))

                Menu {
                    Button("缓存当前海盆近10年") {
                        store.cacheRecentYears(basins: [store.selectedBasin])
                    }
                    Button("缓存全部海盆近10年") {
                        store.cacheRecentYears(basins: CycloneBasin.allCases)
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("缓存近10年数据")
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                Button {
                    Task { await store.refreshActive() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("刷新实时数据")
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
    }

    private var mapGroup: some View {
        VStack(spacing: 10) {
            Button(action: onFit) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("缩放至全部气旋")

            Button {
                showList = true
            } label: {
                Image(systemName: "list.bullet")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("气旋列表")
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
