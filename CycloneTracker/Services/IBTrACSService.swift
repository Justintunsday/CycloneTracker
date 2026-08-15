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

    static let probeChunkSize = 64 * 1024

    // IBTrACS v04r01 list CSV 固定列(以真实文件表头校验)
    static let columnSID = 0
    static let columnSeason = 1
    static let columnBasin = 3
    static let columnName = 5
    static let columnTime = 6
    static let columnLat = 8
    static let columnLon = 9
    static let columnWmoWind = 10
    static let columnWmoPres = 11
    static let columnUsaAtcfID = 18
    static let columnUsaStatus = 22
    static let columnUsaWind = 23
    static let columnUsaPres = 24

    static func parseActiveCSV(_ text: String) -> [ActiveRow] {
        let lines = text.components(separatedBy: .newlines)
        guard lines.count > 2 else { return [] }
        var rows: [ActiveRow] = []
        for line in lines.dropFirst(2) where !line.isEmpty {
            let fields = CSVParser.fields(in: line)
            guard fields.count > columnUsaPres else { continue }
            guard let lat = Double(fields[columnLat]), let lon = Double(fields[columnLon]) else { continue }
            guard let date = DateParsing.ibtracsFormatter.date(from: fields[columnTime]) else { continue }
            let wind = Int(fields[columnWmoWind]) ?? Int(fields[columnUsaWind])
            let pressure = Int(fields[columnWmoPres]) ?? Int(fields[columnUsaPres])
            rows.append(ActiveRow(
                sid: fields[columnSID],
                name: fields[columnName],
                basin: fields[columnBasin],
                atcfID: fields[columnUsaAtcfID],
                latitude: lat,
                longitude: lon,
                windKnots: wind,
                pressureMB: pressure,
                status: fields[columnUsaStatus],
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
        let fileName = "ibtracs.\(basin.rawValue).list.v04r01.csv"
        let urlString = "\(baseURL)/\(fileName)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(basin.rawValue)-\(year).csv")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var sliceData: Data?
        do {
            sliceData = try await fetchYearSlice(urlString: urlString, year: year, onPhase: onPhase)
        } catch APIError.rangeNotSupported {
            sliceData = nil
        }
        if let sliceData {
            try sliceData.write(to: fileURL)
        } else {
            onPhase("服务器不支持分段下载,正在下载完整海盆数据(可能较慢)…")
            try await APIClient.shared.download(to: fileURL, from: urlString)
        }
        onPhase("正在解析 \(year) 年 \(basin.displayName) 气旋…")
        return try await Task.detached {
            try parseHistoricalFile(at: fileURL, year: year, basin: basin)
        }.value
    }

    private static func fetchYearSlice(
        urlString: String,
        year: Int,
        onPhase: @escaping @Sendable (String) -> Void
    ) async throws -> Data {
        let (_, total) = try await APIClient.shared.rangeData(from: urlString, range: "bytes=0-0")
        guard let totalSize = total else { throw APIError.invalidData("无法获取文件大小") }
        if totalSize < 2 * 1024 * 1024 {
            return try await APIClient.shared.data(from: urlString)
        }
        onPhase("正在定位 \(year) 年数据位置…")
        let start = try await searchBoundary(urlString: urlString, totalSize: totalSize, season: year)
        let end = try await searchBoundary(urlString: urlString, totalSize: totalSize, season: year + 1)
        let lo = max(0, start - probeChunkSize)
        let hi = min(totalSize - 1, end + probeChunkSize)
        onPhase("正在下载 \(year) 年数据(分段,约几百 KB)…")
        var (data, _) = try await APIClient.shared.rangeData(from: urlString, range: "bytes=\(lo)-\(hi)")
        if let firstNewline = data.firstIndex(of: 0x0A) {
            data = data.subdata(in: data.index(after: firstNewline)..<data.endIndex)
        }
        return data
    }

    private static func searchBoundary(urlString: String, totalSize: Int, season: Int) async throws -> Int {
        var lo = 0
        var hi = totalSize
        while lo < hi {
            let mid = (lo + hi) / 2
            let midSeason = try await probeSeason(urlString: urlString, at: mid)
            if let midSeason {
                if midSeason >= season {
                    hi = mid
                } else {
                    lo = mid + 1
                }
            } else {
                hi = mid
            }
        }
        return lo
    }

    private static func probeSeason(urlString: String, at offset: Int) async throws -> Int? {
        let (data, _) = try await APIClient.shared.rangeData(
            from: urlString,
            range: "bytes=\(offset)-\(offset + probeChunkSize)"
        )
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var lines = text.components(separatedBy: "\n")
        if offset > 0, !lines.isEmpty {
            lines.removeFirst()
        }
        for line in lines.prefix(3) {
            let fields = CSVParser.fields(in: line)
            if fields.count > 1, let season = Int(fields[1]) {
                return season
            }
        }
        return nil
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
        var buffer = Data()
        let chunkSize = 1 << 20

        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                guard let line = String(data: lineData, encoding: .utf8) else { continue }

                let fields = CSVParser.fields(in: line)
                guard fields.count > columnUsaPres else { continue }
                guard Int(fields[columnSeason]) == year else { continue }
                guard let rowBasin = CycloneBasin.fromIBTrACS(fields[columnBasin]), rowBasin == basin else { continue }
                guard let lat = Double(fields[columnLat]), let lon = Double(fields[columnLon]) else { continue }
                guard let date = DateParsing.ibtracsFormatter.date(from: fields[columnTime]) else { continue }

                let wind = Int(fields[columnWmoWind]) ?? Int(fields[columnUsaWind])
                let pressure = Int(fields[columnWmoPres]) ?? Int(fields[columnUsaPres])
                var storm = storms[fields[columnSID]] ?? StormAccumulator()
                if storm.sid.isEmpty {
                    storm.sid = fields[columnSID]
                    storm.name = fields[columnName]
                    storm.basin = rowBasin
                }
                storm.points.append(TrackPoint(
                    id: "\(fields[columnSID])-\(fields[columnTime])",
                    date: date,
                    latitude: lat,
                    longitude: lon,
                    windKnots: wind,
                    pressureMB: pressure,
                    category: StormCategory.fromWind(knots: wind ?? 0)
                ))
                storms[fields[columnSID]] = storm
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
