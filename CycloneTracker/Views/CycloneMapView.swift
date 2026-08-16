import MapKit
import SwiftUI

struct CycloneMapView: View {
    @Bindable var store: CycloneStore
    @State private var position: MapCameraPosition = .automatic
    @State private var selection: CycloneSelection?
    @State private var didInitialFit = false
    @State private var showList = false
    @State private var showDatePicker = false
    @State private var locationService = UserLocationService()
    @State private var pendingFocus = false

    var body: some View {
        Map(position: $position, selection: $selection) {
            UserAnnotation()
            ForEach(store.displayedCyclones) { cyclone in
                cycloneContent(for: cyclone)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onChange(of: selection) { _, newValue in
            if let newValue {
                if let match = store.displayedCyclones.first(where: { $0.id == newValue.id }) {
                    store.selectedCyclone = match
                } else if let match = store.displayedCyclones.first(where: { $0.displayName == newValue.id }) {
                    store.selectedCyclone = match
                } else if let coordinate = newValue.feature?.coordinate {
                    store.selectedCyclone = store.displayedCyclones.first { cyclone in
                        abs(cyclone.latitude - coordinate.latitude) < 0.05
                            && abs(cyclone.longitude - coordinate.longitude) < 0.05
                    }
                }
            } else {
                store.selectedCyclone = nil
            }
        }
        .onChange(of: store.activeCyclones) { _, newValue in
            if !newValue.isEmpty, !didInitialFit {
                didInitialFit = true
                fitAll()
            }
        }
        .onChange(of: locationService.lastLocation) { _, newValue in
            guard pendingFocus, let newValue else { return }
            pendingFocus = false
            center(on: newValue.coordinate)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                if store.mode == .active {
                    Button(action: toggleMode) {
                        Image(systemName: "hurricane")
                    }
                    .accessibilityLabel("切换至历史模式")
                } else {
                    Button(action: toggleMode) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("切换至实时模式")
                }

                if store.mode == .historical {
                    Button {
                        showDatePicker = true
                    } label: {
                        Image(systemName: "calendar")
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
                    }
                    .accessibilityLabel("缓存近10年数据")
                } else {
                    Button {
                        Task { await store.refreshActive() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新实时数据")

                    Menu {
                        Picker("海域筛选", selection: $store.activeBasinFilter) {
                            Text("全部海域").tag(CycloneBasin?.none)
                            ForEach(CycloneBasin.allCases) { basin in
                                Text(basin.displayName).tag(Optional(basin))
                            }
                        }
                    } label: {
                        Image(systemName: "water.waves")
                    }
                    .accessibilityLabel("筛选海域")
                }
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    pendingFocus = true
                    locationService.requestAndFocus()
                } label: {
                    Image(systemName: "location.fill")
                }
                .accessibilityLabel("定位到当前位置")

                Button(action: fitAll) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel("缩放至全部气旋")

                Button {
                    showList = true
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("气旋列表")
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
        .overlay(alignment: .bottomTrailing) {
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
        .safeAreaBar(edge: .bottom, spacing: 8) {
            Group {
                if let cyclone = store.selectedCyclone {
                    StormDetailCard(
                        cyclone: cyclone,
                        onLocate: { center(on: cyclone.coordinate) },
                        onClose: {
                            selection = nil
                            store.selectedCyclone = nil
                        }
                    )
                    .padding(.horizontal)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.4, bounce: 0.2), value: store.selectedCyclone?.id)
        }
        .scrollEdgeEffectStyle(.hard, for: .bottom)
        .overlay(alignment: .center) {
            if store.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(store.loadingMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .glassEffect(.regular.tint(.oceanGlass.opacity(0.06)), in: RoundedRectangle(cornerRadius: 16))
            } else if store.mode == .historical, store.didLoadHistorical, store.historicalCyclones.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tropicalstorm")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("\(store.selectedDate.formatted(date: .abbreviated, time: .omitted)) \(store.selectedBasin.displayName) 无活跃气旋记录")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .glassEffect(.regular.tint(.oceanGlass.opacity(0.06)), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert(
            "数据加载失败",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("重试") {
                Task { await store.retry() }
            }
            Button("取消", role: .cancel) {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    @MapContentBuilder
    private func cycloneContent(for cyclone: Cyclone) -> some MapContent {
        let isSelected = store.selectedCyclone?.id == cyclone.id
        let lineColor = store.mode == .historical
            ? StormCategory.fromWind(knots: cyclone.peakWindKnots).color
            : cyclone.category.color
        if cyclone.track.count > 1 {
            if store.mode == .historical {
                MapPolyline(coordinates: cyclone.track.map(\.coordinate))
                    .stroke(lineColor.opacity(isSelected ? 1.0 : 0.7), lineWidth: isSelected ? 4 : 2)
                    .tag(CycloneSelection(id: cyclone.id))
            } else {
                MapPolyline(coordinates: cyclone.track.map(\.coordinate))
                    .stroke(lineColor.opacity(0.8), lineWidth: isSelected ? 4 : 2)
            }
        }
        if cyclone.forecast.count > 1 {
            MapPolyline(coordinates: cyclone.forecast.map(\.coordinate))
                .stroke(.orange.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
        }
        Marker(cyclone.displayName, systemImage: "hurricane", coordinate: cyclone.coordinate)
            .tint(cyclone.category.color)
            .tag(CycloneSelection(id: cyclone.id))
    }

    private func toggleMode() {
        store.mode = store.mode == .active ? .historical : .active
        if store.mode == .historical, store.historicalCyclones.isEmpty {
            Task { await store.loadHistorical() }
        }
    }

    private func fitAll() {
        let coordinates = store.displayedCyclones.map(\.coordinate)
        guard let first = coordinates.first else { return }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        var longitudeSpan = maxLon - minLon
        var centerLongitude = (minLon + maxLon) / 2
        if longitudeSpan > 180 {
            longitudeSpan = 360
            centerLongitude = 0
        }
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 8),
            longitudeDelta: max(longitudeSpan * 1.6, 10)
        )
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: centerLongitude),
            span: span
        )
        withAnimation(.easeInOut) {
            position = .region(region)
        }
    }

    private func center(on coordinate: CLLocationCoordinate2D) {
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12)
        )
        withAnimation(.easeInOut) {
            position = .region(region)
        }
    }
}
