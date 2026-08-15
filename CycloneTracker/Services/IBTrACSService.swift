import Foundation

struct IBTrACSService: Sendable {
    static let baseURL = "https://www.ncei.noaa.gov/data/international-best-track-archive-for-climate-stewardship-ibtracs/v04r01/access/csv"

    struct ActiveRow: Sendable {
        let sid: String
        let name: String
        let basin: String
        let atcfID: String
        let latitude: Double
        let longitude: Double
        let windKnots: Int?
        let pressureMB: Int?
        let status: String
        let date: Date
    }

    static func fetchActiveRows() async throws -> [ActiveRow] {
        let data = try await APIClient.shared.data(from: "\(baseURL)/ibtracs.ACTIVE.list.v04r01.csv")
        guard let text = String(data: data, encoding: .utf8) else {
            throw APIError.invalidData("ACTIVE 文件编码无效")
        }
        return parseActiveCSV(text)
    }

    static func parseActiveCSV(_ text: String) -> [ActiveRow] {
        let lines = text.components(separatedBy: .newlines)
        guard lines.count > 2 else { return [] }
        let header = CSVParser.fields(in: lines[0])
        let columnIndex = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        guard let sidIndex = columnIndex["SID"],
              let basinIndex = columnIndex["BASIN"],
              let nameIndex = columnIndex["NAME"],
              let timeIndex = columnIndex["ISO_TIME"],
              let latIndex = columnIndex["LAT"],
              let lonIndex = columnIndex["LON"],
              let wmoWindIndex = columnIndex["WMO_WIND"],
              let wmoPresIndex = columnIndex["WMO_PRES"],
              let usaAtcfIndex = columnIndex["USA_ATCF_ID"],
              let usaWindIndex = columnIndex["USA_WIND"],
              let usaPresIndex = columnIndex["USA_PRES"],
              let usaStatusIndex = columnIndex["USA_STATUS"]
        else { return [] }

        var rows: [ActiveRow] = []
        for line in lines.dropFirst(2) where !line.isEmpty {
            let fields = CSVParser.fields(in: line)
            guard fields.count > max(sidIndex, basinIndex, nameIndex, timeIndex, latIndex, lonIndex, usaAtcfIndex) else { continue }
            guard let lat = Double(fields[latIndex]), let lon = Double(fields[lonIndex]) else { continue }
            guard let date = DateParsing.ibtracsFormatter.date(from: fields[timeIndex]) else { continue }
            let wind = Int(fields[wmoWindIndex]) ?? Int(fields[usaWindIndex])
            let pressure = Int(fields[wmoPresIndex]) ?? Int(fields[usaPresIndex])
            rows.append(ActiveRow(
                sid: fields[sidIndex],
                name: fields[nameIndex],
                basin: fields[basinIndex],
                atcfID: fields[usaAtcfIndex],
                latitude: lat,
                longitude: lon,
                windKnots: wind,
                pressureMB: pressure,
                status: fields[usaStatusIndex],
                date: date
            ))
        }
        return rows
    }

    static func historicalCyclones(
        year: Int,
        basin: CycloneBasin,
        onPhase: @escaping @Sendable (String) -> Void
    ) async throws -> [Cyclone] {
        let currentYear = Calendar.current.component(.year, from: Date())
        let fileName: String
        if year >= currentYear - 2 {
            fileName = "ibtracs.last3years.list.v04r01.csv"
        } else {
            fileName = "ibtracs.\(basin.rawValue).list.v04r01.csv"
        }
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        onPhase("正在下载 IBTrACS 数据…")
        try await APIClient.shared.download(to: fileURL, from: "\(baseURL)/\(fileName)")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        onPhase("正在解析 \(year) 年 \(basin.displayName) 气旋…")
        return try await Task.detached {
            try parseHistoricalFile(at: fileURL, year: year, basin: basin)
        }.value
    }

    nonisolated static func parseHistoricalFile(at url: URL, year: Int, basin: CycloneBasin) throws -> [Cyclone] {
        struct StormAccumulator {
            var sid: String = ""
            var name: String = ""
            var basin: CycloneBasin = .na
            var points: [TrackPoint] = []
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var storms: [String: StormAccumulator] = [:]
        var headerColumns: [String: Int] = [:]
        var headerLoaded = false
        var skipUnitsLine = false
        var buffer = Data()
        let chunkSize = 1 << 20

        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                guard let line = String(data: lineData, encoding: .utf8) else { continue }

                if !headerLoaded {
                    headerColumns = Dictionary(uniqueKeysWithValues: CSVParser.fields(in: line).enumerated().map { ($1, $0) })
                    headerLoaded = true
                    skipUnitsLine = true
                    continue
                }
                if skipUnitsLine {
                    skipUnitsLine = false
                    continue
                }

                guard let sidIndex = headerColumns["SID"],
                      let seasonIndex = headerColumns["SEASON"],
                      let basinIndex = headerColumns["BASIN"],
                      let nameIndex = headerColumns["NAME"],
                      let timeIndex = headerColumns["ISO_TIME"],
                      let latIndex = headerColumns["LAT"],
                      let lonIndex = headerColumns["LON"],
                      let wmoWindIndex = headerColumns["WMO_WIND"],
                      let wmoPresIndex = headerColumns["WMO_PRES"],
                      let usaWindIndex = headerColumns["USA_WIND"],
                      let usaPresIndex = headerColumns["USA_PRES"]
                else { continue }

                let fields = CSVParser.fields(in: line)
                guard fields.count > max(sidIndex, seasonIndex, basinIndex, nameIndex, timeIndex, latIndex, lonIndex) else { continue }
                guard Int(fields[seasonIndex]) == year else { continue }
                guard let rowBasin = CycloneBasin.fromIBTrACS(fields[basinIndex]), rowBasin == basin else { continue }
                guard let lat = Double(fields[latIndex]), let lon = Double(fields[lonIndex]) else { continue }
                guard let date = DateParsing.ibtracsFormatter.date(from: fields[timeIndex]) else { continue }

                let wind = Int(fields[wmoWindIndex]) ?? Int(fields[usaWindIndex])
                let pressure = Int(fields[wmoPresIndex]) ?? Int(fields[usaPresIndex])
                var storm = storms[fields[sidIndex]] ?? StormAccumulator()
                if storm.sid.isEmpty {
                    storm.sid = fields[sidIndex]
                    storm.name = fields[nameIndex]
                    storm.basin = rowBasin
                }
                storm.points.append(TrackPoint(
                    id: "\(fields[sidIndex])-\(fields[timeIndex])",
                    date: date,
                    latitude: lat,
                    longitude: lon,
                    windKnots: wind,
                    pressureMB: pressure,
                    category: StormCategory.fromWind(knots: wind ?? 0)
                ))
                storms[fields[sidIndex]] = storm
            }
        }

        return storms.values.compactMap { storm -> Cyclone? in
            guard let last = storm.points.max(by: { $0.date < $1.date }) else { return nil }
            let peakWind = storm.points.compactMap(\.windKnots).max() ?? 0
            let peakPressure = storm.points.compactMap(\.pressureMB).min() ?? 0
            let peakCategory = storm.points.map(\.category).max() ?? .disturbance
            return Cyclone(
                id: "IB-\(storm.sid)",
                name: storm.name,
                basin: storm.basin,
                source: .ibtracs,
                isActive: false,
                windKnots: peakWind,
                pressureMB: peakPressure,
                category: peakCategory,
                latitude: last.latitude,
                longitude: last.longitude,
                date: last.date,
                track: storm.points.sorted { $0.date < $1.date },
                forecast: []
            )
        }
        .sorted { $0.category > $1.category }
    }
}
