import MapKit
import SwiftUI

struct CycloneMapView: View {
    @Bindable var store: CycloneStore
    @State private var position: MapCameraPosition = .automatic
    @State private var selection: CycloneSelection?
    @State private var didInitialFit = false

    var body: some View {
        Map(position: $position, selection: $selection) {
            ForEach(store.displayedCyclones) { cyclone in
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
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
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
        .overlay(alignment: .trailing) {
            MapSideControls(store: store, onFit: fitAll)
                .padding(.trailing, 8)
                .offset(y: store.selectedCyclone != nil ? -140 : 0)
                .animation(.easeInOut(duration: 0.2), value: store.selectedCyclone != nil)
        }
        .overlay(alignment: .bottomTrailing) {
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
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(.oceanGlass.opacity(0.08)), in: Capsule())
                .specularRim(in: Capsule())
                .padding(.trailing, 12)
                .padding(.bottom, store.selectedCyclone != nil ? 240 : 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.25), value: store.isCachingRecent)
        .overlay(alignment: .bottom) {
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
                .padding(.bottom, 8)
            }
        }
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
                .specularRim(in: RoundedRectangle(cornerRadius: 16))
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
                .specularRim(in: RoundedRectangle(cornerRadius: 16))
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
