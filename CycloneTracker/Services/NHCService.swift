import Foundation

struct NHCService: Sendable {
    static let baseURL = "https://www.nhc.noaa.gov"
    static let atcfBaseURL = "https://ftp.nhc.noaa.gov/atcf/aid_public"

    struct StormSummary: Decodable, Sendable {
        let id: String
        let name: String
        let classification: String?
        let intensity: String?
        let pressure: String?
        let latitudeNumeric: Double?
        let longitudeNumeric: Double?
        let lastUpdate: String?
    }

    struct CurrentStormsResponse: Decodable, Sendable {
        let activeStorms: [StormSummary]
    }

    static func activeStorms() async throws -> [Cyclone] {
        let data = try await APIClient.shared.data(from: "\(baseURL)/CurrentStorms.json")
        let response = try JSONDecoder().decode(CurrentStormsResponse.self, from: data)
        var storms: [Cyclone] = []
        for summary in response.activeStorms {
            guard let latitude = summary.latitudeNumeric, let longitude = summary.longitudeNumeric else { continue }
            let wind = Int(summary.intensity ?? "") ?? 0
            let pressure = Int(summary.pressure ?? "") ?? 0
            var track: [TrackPoint] = []
            var forecast: [TrackPoint] = []
            if let atcf = try? await fetchATCF(stormID: summary.id) {
                track = atcf.track
                forecast = atcf.forecast
            }
            let date = DateParsing.isoFormatter.date(from: summary.lastUpdate ?? "") ?? track.last?.date ?? Date()
            storms.append(Cyclone(
                id: "NHC-\(summary.id.uppercased())",
                name: summary.name,
                basin: basin(for: summary.id),
                source: .nhc,
                isActive: true,
                windKnots: wind,
                pressureMB: pressure,
                category: StormCategory.fromWind(knots: wind),
                latitude: latitude,
                longitude: longitude,
                date: date,
                track: track,
                forecast: forecast
            ))
        }
        return storms
    }

    static func fetchATCF(stormID: String) async throws -> (track: [TrackPoint], forecast: [TrackPoint]) {
        let fileName = "a\(stormID.lowercased()).dat.gz"
        let data = try await APIClient.shared.data(from: "\(atcfBaseURL)/\(fileName)")
        let decompressed = try GZip.decompress(data)
        guard let text = String(data: decompressed, encoding: .utf8) else {
            throw APIError.invalidData("ATCF 文件编码无效")
        }
        return parseATCF(text)
    }

    static func parseATCF(_ text: String) -> (track: [TrackPoint], forecast: [TrackPoint]) {
        var byTime: [String: TrackPoint] = [:]
        var forecast: [TrackPoint] = []
        for line in text.components(separatedBy: .newlines) {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count > 10 else { continue }
            let tech = fields[4]
            guard ["CARQ", "OFCL", "BEST", "TCVA"].contains(tech) else { continue }
            guard let tau = Int(fields[5]) else { continue }
            guard let lat = parseLatLon(fields[6]), let lon = parseLatLon(fields[7]) else { continue }
            guard let date = DateParsing.atcfFormatter.date(from: fields[2]) else { continue }
            let wind = Int(fields[8])
            let pressure = Int(fields[9])
            let point = TrackPoint(
                id: "\(fields[2])-\(tech)-\(tau)",
                date: date,
                latitude: lat,
                longitude: lon,
                windKnots: wind,
                pressureMB: pressure,
                category: StormCategory.fromWind(knots: wind ?? 0)
            )
            if tau <= 0 {
                byTime[fields[2]] = point
            } else {
                forecast.append(point)
            }
        }
        let track = byTime.values.sorted { $0.date < $1.date }
        return (track, forecast.sorted { $0.date < $1.date })
    }

    static func parseLatLon(_ raw: String) -> Double? {
        guard let hemisphere = raw.last else { return nil }
        guard "NSEW".contains(hemisphere) else { return nil }
        let number = String(raw.dropLast())
        guard var value = Double(number) else { return nil }
        if !number.contains(".") {
            value /= 10
        }
        return (hemisphere == "S" || hemisphere == "W") ? -value : value
    }

    static func basin(for stormID: String) -> CycloneBasin {
        stormID.lowercased().hasPrefix("al") ? .na : .ep
    }
}
