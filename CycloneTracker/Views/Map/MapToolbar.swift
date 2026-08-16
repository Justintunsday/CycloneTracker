import SwiftUI

struct MapToolbar: ToolbarContent {
    @Bindable var store: CycloneStore
    let onFitAll: () -> Void
    let onLocate: () -> Void
    @Binding var showDatePicker: Bool
    @Binding var showList: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {
            dataControls
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            mapControls
        }
    }

    @ViewBuilder
    private var dataControls: some View {
        if store.mode == .active {
            Button(action: toggleMode) {
                Image(systemName: "hurricane")
            }
            .accessibilityLabel(L("切换至历史模式"))
        } else {
            Button(action: toggleMode) {
                Image(systemName: "clock.arrow.circlepath")
            }
            .accessibilityLabel(L("切换至实时模式"))
        }

        if store.mode == .historical {
            Button {
                showDatePicker = true
            } label: {
                Image(systemName: "calendar")
            }
            .accessibilityLabel(L("选择日期"))

            Menu {
                Picker(L("海盆"), selection: $store.selectedBasin) {
                    ForEach(CycloneBasin.allCases) { basin in
                        Text(basin.displayName).tag(basin)
                    }
                }
            } label: {
                Image(systemName: "globe.asia.australia.fill")
            }
            .accessibilityLabel(L("选择海盆"))

            Menu {
                Button(L("缓存当前海盆近10年")) {
                    store.cacheRecentYears(basins: [store.selectedBasin])
                }
                Button(L("缓存全部海盆近10年")) {
                    store.cacheRecentYears(basins: CycloneBasin.allCases)
                }
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .accessibilityLabel(L("缓存近10年数据"))
        } else {
            Button {
                Task { await store.refreshActive() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel(L("刷新实时数据"))

            Menu {
                Picker(L("海域"), selection: $store.activeBasinFilter) {
                    Text(L("全部海域")).tag(CycloneBasin?.none)
                    ForEach(CycloneBasin.allCases) { basin in
                        Text(basin.displayName).tag(Optional(basin))
                    }
                }
            } label: {
                Image(systemName: "water.waves")
            }
            .accessibilityLabel(L("海域筛选"))
        }
    }

    @ViewBuilder
    private var mapControls: some View {
        Button(action: onLocate) {
            Image(systemName: "location.fill")
        }
        .accessibilityLabel(L("定位到当前位置"))

        Button(action: onFitAll) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .accessibilityLabel(L("缩放至全部气旋"))

        Button {
            showList = true
        } label: {
            Image(systemName: "list.bullet")
        }
        .accessibilityLabel(L("气旋列表"))
    }

    private func toggleMode() {
        store.mode = store.mode == .active ? .historical : .active
        if store.mode == .historical, store.historicalCyclones.isEmpty {
            Task { await store.loadHistorical() }
        }
    }
}
