import SwiftUI

struct MapSideControls: View {
    @Bindable var store: CycloneStore
    let onFit: () -> Void
    @State private var showList = false
    @State private var showDatePicker = false
    @State private var isExpanded = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(duration: 0.45, bounce: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "xmark" : "line.3.horizontal")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(CircleGlassButtonStyle())
            .circleGlass()
            .accessibilityLabel(isExpanded ? "收起工具栏" : "展开工具栏")

            if isExpanded {
                controls
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
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

    private var controls: some View {
        HStack(spacing: 8) {
            if store.mode == .active {
                Button(action: toggleMode) {
                    Image(systemName: "hurricane")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(CircleGlassButtonStyle())
                .circleGlass()
                .accessibilityLabel("切换至历史模式")
            } else {
                Button(action: toggleMode) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(CircleGlassButtonStyle())
                .circleGlass(tintOpacity: 0.28)
                .accessibilityLabel("切换至实时模式")
            }

            if store.mode == .historical {
                Button {
                    showDatePicker = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(CircleGlassButtonStyle())
                .circleGlass()
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
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .circleGlass()
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
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .circleGlass()
                .accessibilityLabel("缓存近10年数据")
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                Button {
                    Task { await store.refreshActive() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(CircleGlassButtonStyle())
                .circleGlass()
                .accessibilityLabel("刷新实时数据")
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }

            Button(action: onFit) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(CircleGlassButtonStyle())
            .circleGlass()
            .accessibilityLabel("缩放至全部气旋")

            Button {
                showList = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(CircleGlassButtonStyle())
            .circleGlass()
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
