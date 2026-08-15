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
                if cyclone.track.count > 1 {
                    if store.mode == .historical {
                        MapPolyline(coordinates: cyclone.track.map(\.coordinate))
                            .stroke(cyclone.category.color.opacity(isSelected ? 1.0 : 0.7), lineWidth: isSelected ? 4 : 2)
                            .tag(CycloneSelection(id: cyclone.id))
                    } else {
                        MapPolyline(coordinates: cyclone.track.map(\.coordinate))
                            .stroke(cyclone.category.color.opacity(0.8), lineWidth: isSelected ? 4 : 2)
                    }
                }
                if cyclone.forecast.count > 1 {
                    MapPolyline(coordinates: cyclone.forecast.map(\.coordinate))
                        .stroke(.orange.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                }
                if cyclone.isActive || store.mode == .active {
                    Marker(cyclone.displayName, systemImage: "hurricane", coordinate: cyclone.coordinate)
                        .tint(cyclone.category.color)
                        .tag(CycloneSelection(id: cyclone.id))
                }
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
        .overlay(alignment: .top) {
            ControlBar(store: store, onFit: fitAll)
        }
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
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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
