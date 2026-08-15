import CoreLocation
import MapKit
import SwiftUI

struct StormDetailCard: View {
    let cyclone: Cyclone
    let onLocate: () -> Void
    let onClose: () -> Void
    @State private var placeName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(cyclone.displayName)
                            .font(.title3.bold())
                        Text(cyclone.category.displayName)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(cyclone.category.color, in: Capsule())
                            .foregroundStyle(badgeForeground)
                    }
                    HStack(spacing: 6) {
                        Text(cyclone.basin.displayName)
                        Text("·")
                        Text("来源: \(cyclone.source.displayName)")
                        if cyclone.isActive {
                            Text("·")
                            Text("活跃").foregroundStyle(.red)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 18) {
                metric("最大风速", cyclone.windKnots > 0 ? "\(cyclone.windKnots) kt" : "—")
                metric("换算", "\(cyclone.windKmh) km/h · \(cyclone.windMs) m/s")
                metric("中心气压", cyclone.pressureMB > 0 ? "\(cyclone.pressureMB) hPa" : "—")
            }

            HStack(spacing: 8) {
                Label(cyclone.coordinate.formatted, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                if let placeName {
                    Text(placeName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 10) {
                Text(timeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let url = cyclone.infoURL {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
                Button(action: onLocate) {
                    Image(systemName: "scope")
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 4)
        .task(id: cyclone.id) {
            await resolvePlaceName()
        }
    }

    private var badgeForeground: Color {
        [StormCategory.category1, .storm].contains(cyclone.category) ? .black : .white
    }

    private var timeText: String {
        if cyclone.isActive {
            return "定位时间: \(cyclone.date.formatted(date: .abbreviated, time: .shortened))"
        }
        let start = (cyclone.startDate ?? cyclone.date).formatted(date: .abbreviated, time: .omitted)
        let end = (cyclone.endDate ?? cyclone.date).formatted(date: .abbreviated, time: .omitted)
        return "活动时间: \(start) – \(end)"
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func resolvePlaceName() async {
        let latitude = cyclone.latitude
        let longitude = cyclone.longitude
        let parts: [String]? = await Task.detached {
            let location = CLLocation(latitude: latitude, longitude: longitude)
            guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
            guard let items = try? await request.mapItems, let item = items.first else { return nil }
            let placemark = item.placemark
            var components: [String] = []
            if let ocean = placemark.ocean { components.append(ocean) }
            if let name = item.name { components.append(name) }
            if let locality = placemark.locality { components.append(locality) }
            if let country = placemark.country { components.append(country) }
            return components
        }.value
        placeName = parts.map { $0.joined(separator: " · ") }
    }
}
