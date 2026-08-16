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
            throw APIError.invalidData(L("ACTIVE 文件编码无效"))
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

    static func cacheFileURL(basin: CycloneBasin, year: Int) -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IBTrACSCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(basin.rawValue)-\(year).csv")
    }

    static func historicalCyclones(
        year: Int,
        basin: CycloneBasin,
        onPhase: @escaping @Sendable (String) -> Void
    ) async throws -> [Cyclone] {
        let cacheURL = cacheFileURL(basin: basin, year: year)
        let urlString = "\(baseURL)/ibtracs.\(basin.rawValue).list.v04r01.csv"

        if FileManager.default.fileExists(atPath: cacheURL.path) {
            onPhase(String(format: L("已使用本地缓存: %@ 年 %@…"), String(year), basin.displayName))
        } else {
            do {
                let data = try await fetchYearSlice(urlString: urlString, year: year, onPhase: onPhase)
                try data.write(to: cacheURL)
            } catch APIError.rangeNotSupported {
                onPhase(L("服务器不支持分段下载,正在下载完整海盆数据(可能较慢)…"))
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(basin.rawValue)-\(year)-full.csv")
                defer { try? FileManager.default.removeItem(at: tempURL) }
                try await APIClient.shared.download(to: tempURL, from: urlString)
                onPhase(String(format: L("正在解析 %@ 年 %@ 气旋…"), String(year), basin.displayName))
                return try await Task.detached {
                    try parseHistoricalFile(at: tempURL, year: year, basin: basin)
                }.value
            }
        }

        onPhase(String(format: L("正在解析 %@ 年 %@ 气旋…"), String(year), basin.displayName))
        do {
            return try await Task.detached {
                try parseHistoricalFile(at: cacheURL, year: year, basin: basin)
            }.value
        } catch {
            try? FileManager.default.removeItem(at: cacheURL)
            throw error
        }
    }

    static func prefetchRecentYears(
        basin: CycloneBasin,
        years: [Int],
        onPhase: @escaping @Sendable (String) -> Void
    ) async throws {
        let urlString = "\(baseURL)/ibtracs.\(basin.rawValue).list.v04r01.csv"
        var downloaded = 0
        var skipped = 0
        for year in years {
            try Task.checkCancellation()
            let cacheURL = cacheFileURL(basin: basin, year: year)
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                skipped += 1
                continue
            }
            onPhase(String(format: L("正在缓存 %@ 年 %@(%d/%d)…"), String(year), basin.displayName, downloaded + 1, years.count))
            do {
                let data = try await fetchYearSlice(urlString: urlString, year: year, onPhase: { _ in })
                try data.write(to: cacheURL)
                downloaded += 1
            } catch APIError.rangeNotSupported {
                onPhase(String(format: L("缓存完成: 新下载 %d 年,已存在 %d 年"), downloaded, skipped))
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // 单个年份下载失败则跳过,继续其他年份
            }
        }
        onPhase(String(format: L("缓存完成: 新下载 %d 年,已存在 %d 年"), downloaded, skipped))
    }

    private     static func fetchYearSlice(
        urlString: String,
        year: Int,
        onPhase: @escaping @Sendable (String) -> Void
    ) async throws -> Data {
        let (_, total) = try await APIClient.shared.rangeData(from: urlString, range: "bytes=0-0")
        guard let totalSize = total else { throw APIError.invalidData(L("无法获取文件大小")) }
        if totalSize < 2 * 1024 * 1024 {
            return try await APIClient.shared.data(from: urlString)
        }

        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let firstYear = 1841
        let yearSpan = max(currentYear - firstYear + 1, 1)
        let bytesPerYear = Double(totalSize) / Double(yearSpan)
        let initialChunk = Int(bytesPerYear * 1.2)

        onPhase(String(format: L("正在快速定位 %@ 年数据…"), String(year)))

        var start = max(0, min(totalSize - 1, Int(Double(year - firstYear) * bytesPerYear - bytesPerYear * 0.4)))
        var end = min(totalSize, start + initialChunk)
        var data = Data()

        for _ in 0..<10 {
            let lo = max(0, start)
            let hi = min(totalSize - 1, end - 1)
            guard hi > lo else { break }
            let (chunk, _) = try await APIClient.shared.rangeData(from: urlString, range: "bytes=\(lo)-\(hi)")
            data = chunk
            guard let (minSeason, maxSeason) = seasonRange(in: chunk) else { break }

            if minSeason < year, maxSeason > year { break }
            if minSeason == year, maxSeason == year {
                if start > 0 {
                    start = max(0, start - Int(bytesPerYear * 0.8))
                    continue
                }
                if end < totalSize {
                    end = min(totalSize, end + Int(bytesPerYear * 0.8))
                    continue
                }
                break
            }
            if minSeason == year, start > 0 {
                start = max(0, start - Int(bytesPerYear * 0.8))
                continue
            }
            if maxSeason == year, end < totalSize {
                end = min(totalSize, end + Int(bytesPerYear * 0.8))
                continue
            }
            if maxSeason < year {
                if end >= totalSize { break }
                start = min(totalSize - 1, start + Int(Double(year - maxSeason) * bytesPerYear * 0.9))
                end = min(totalSize, start + initialChunk)
                continue
            }
            if minSeason > year {
                if start <= 0 { break }
                start = max(0, start - Int(Double(minSeason - year) * bytesPerYear * 0.9))
                end = start + initialChunk
                continue
            }
            break
        }

        if let firstNewline = data.firstIndex(of: 0x0A) {
            data = data.subdata(in: data.index(after: firstNewline)..<data.endIndex)
        }
        return data
    }

    private static func seasonRange(in chunk: Data) -> (min: Int, max: Int)? {
        guard let text = String(data: chunk, encoding: .utf8) else { return nil }
        var minSeason = Int.max
        var maxSeason = Int.min
        for line in text.components(separatedBy: "\n") {
            let fields = CSVParser.fields(in: line)
            if fields.count > 1, let season = Int(fields[1]) {
                minSeason = min(minSeason, season)
                maxSeason = max(maxSeason, season)
            }
        }
        guard minSeason != Int.max, maxSeason != Int.min else { return nil }
        return (minSeason, maxSeason)
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
