import Foundation

struct JTWCService: Sendable {
    static let atcfBaseURL = "https://ftp.nhc.noaa.gov/atcf/aid_public"

    static func activeStorms(rows: [IBTrACSService.ActiveRow]) async throws -> [Cyclone] {
        var rowsByAtcfID: [String: [IBTrACSService.ActiveRow]] = [:]
        for row in rows {
            let key = row.atcfID.lowercased()
            guard !key.isEmpty, isJTWCKey(key) else { continue }
            rowsByAtcfID[key, default: []].append(row)
        }

        var freshFixes: [String: (track: [TrackPoint], forecast: [TrackPoint])] = [:]
        if let files = try? await listATCFStorms() {
            for file in files {
                if let parsed = try? await fetchATCF(fileName: file) {
                    freshFixes[file] = parsed
                }
            }
        }

        var cyclones: [Cyclone] = []
        var usedIDs: Set<String> = []

        for (fileName, parsed) in freshFixes.sorted(by: { $0.key < $1.key }) {
            let stormKey = stormID(from: fileName)
            usedIDs.insert(stormKey)
            let rowsForStorm = rowsByAtcfID[stormKey] ?? []
            guard let cyclone = makeCyclone(
                key: stormKey,
                rows: rowsForStorm,
                freshTrack: parsed.track,
                forecast: parsed.forecast
            ) else { continue }
            cyclones.append(cyclone)
        }

        for (key, stormRows) in rowsByAtcfID where !usedIDs.contains(key) {
            guard let cyclone = makeCyclone(key: key, rows: stormRows, freshTrack: [], forecast: []) else { continue }
            cyclones.append(cyclone)
        }

        return cyclones
    }

    static func isJTWCKey(_ key: String) -> Bool {
        ["wp", "io", "sh"].contains(String(key.prefix(2)))
    }

    static func stormID(from fileName: String) -> String {
        fileName
            .replacingOccurrences(of: ".dat.gz", with: "")
            .replacingOccurrences(of: ".dat", with: "")
            .dropFirst()
            .lowercased()
            .description
    }

    static func track(from rows: [IBTrACSService.ActiveRow]) -> [TrackPoint] {
        rows.map { row in
            TrackPoint(
                id: "\(row.sid)-\(row.date.timeIntervalSince1970)",
                date: row.date,
                latitude: row.latitude,
                longitude: row.longitude,
                windKnots: row.windKnots,
                pressureMB: row.pressureMB,
                category: StormCategory.fromWind(knots: row.windKnots ?? 0)
            )
        }
        .sorted { $0.date < $1.date }
    }

    static func basin(for key: String, firstLongitude: Double) -> CycloneBasin {
        switch key.prefix(2) {
        case "wp": return .wp
        case "io": return .ni
        default: return firstLongitude < 135 ? .si : .sp
        }
    }

    private static func makeCyclone(
        key: String,
        rows: [IBTrACSService.ActiveRow],
        freshTrack: [TrackPoint],
        forecast: [TrackPoint]
    ) -> Cyclone? {
        let rowTrack = track(from: rows)
        let track = freshTrack.isEmpty ? rowTrack : freshTrack
        guard let current = track.last ?? rowTrack.last else { return nil }
        let name = rows.first?.name ?? String(key.prefix(4).uppercased())
        let wind = current.windKnots ?? rows.compactMap(\.windKnots).max() ?? 0
        let pressure = current.pressureMB ?? rows.compactMap(\.pressureMB).min() ?? 0
        let basin = Self.basin(for: key, firstLongitude: current.longitude)
        return Cyclone(
            id: "JTWC-\(key.uppercased())",
            name: name,
            basin: basin,
            source: .jtwc,
            isActive: true,
            windKnots: wind,
            pressureMB: pressure,
            category: StormCategory.fromWind(knots: wind),
            latitude: current.latitude,
            longitude: current.longitude,
            date: current.date,
            track: track,
            forecast: forecast
        )
    }

    static func listATCFStorms() async throws -> [String] {
        let htmlData = try await APIClient.shared.data(from: "\(atcfBaseURL)/")
        guard let html = String(data: htmlData, encoding: .utf8) else { return [] }
        let pattern = #/href="(a(?:wp|io|sh)\d{6}\.dat\.gz)"/#
        return html.matches(of: pattern).map { String($0.1) }
    }

    static func fetchATCF(fileName: String) async throws -> (track: [TrackPoint], forecast: [TrackPoint]) {
        let data = try await APIClient.shared.data(from: "\(atcfBaseURL)/\(fileName)")
        let decompressed = try GZip.decompress(data)
        guard let text = String(data: decompressed, encoding: .utf8) else {
            throw APIError.invalidData(L("ATCF 文件编码无效"))
        }
        return parseJTWCATCF(text)
    }

    static func parseJTWCATCF(_ text: String) -> (track: [TrackPoint], forecast: [TrackPoint]) {
        var byTime: [String: TrackPoint] = [:]
        for line in text.components(separatedBy: .newlines) {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count > 10, fields[4] == "JTWC" else { continue }
            guard let tau = Int(fields[5]), tau <= 0 else { continue }
            guard let lat = NHCService.parseLatLon(fields[6]), let lon = NHCService.parseLatLon(fields[7]) else { continue }
            guard let date = DateParsing.atcfFormatter.date(from: fields[2]) else { continue }
            let wind = Int(fields[8])
            let pressure = Int(fields[9])
            byTime[fields[2]] = TrackPoint(
                id: "\(fields[2])-JTWC",
                date: date,
                latitude: lat,
                longitude: lon,
                windKnots: wind,
                pressureMB: pressure,
                category: StormCategory.fromWind(knots: wind ?? 0)
            )
        }
        return (byTime.values.sorted { $0.date < $1.date }, [])
    }
}
