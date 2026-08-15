import Foundation
import Observation

@MainActor
@Observable
final class CycloneStore {
    enum Mode: String, CaseIterable, Identifiable {
        case active = "实时"
        case historical = "历史"
        var id: String { rawValue }
    }

    var mode: Mode = .active
    var activeCyclones: [Cyclone] = []
    var historicalCyclones: [Cyclone] = []
    var selectedCyclone: Cyclone?
    var isLoading = false
    var loadingMessage = ""
    var errorMessage: String?
    var lastRefresh: Date?

    var selectedDate: Date = Date()
    var selectedBasin: CycloneBasin = .wp
    var didLoadHistorical = false
    var isCachingRecent = false
    var cachingMessage = ""

    private var prefetchTask: Task<Void, Never>?

    var historicalDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 1851, month: 1, day: 1)) ?? Date()
        let today = calendar.startOfDay(for: Date())
        return start...today
    }

    var displayedCyclones: [Cyclone] {
        mode == .active ? activeCyclones : historicalCyclones
    }

    func refreshActive() async {
        guard !isLoading else { return }
        isLoading = true
        loadingMessage = "正在获取全球热带气旋数据…"
        errorMessage = nil
        defer { isLoading = false }
        do {
            let rows = try await IBTrACSService.fetchActiveRows()
            async let nhcTask = NHCService.activeStorms()
            async let jtwcTask = JTWCService.activeStorms(rows: rows)
            var storms = ((try? await nhcTask) ?? []) + ((try? await jtwcTask) ?? [])
            storms = enrichWithActiveRows(storms, rows: rows)
            let nhcIDs = Set(storms.filter { $0.source == .nhc }
                .map { $0.id.replacingOccurrences(of: "NHC-", with: "").lowercased() })
            let jtwcKeys = Set(rows
                .filter { JTWCService.isJTWCKey($0.atcfID.lowercased()) }
                .map { $0.atcfID.lowercased() })
            storms += stormsFromActiveRows(rows, excluding: nhcIDs.union(jtwcKeys))
            activeCyclones = storms.filter(\.isActive).sorted { $0.category > $1.category }
            lastRefresh = Date()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadHistorical() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        selectedCyclone = nil
        defer { isLoading = false }
        do {
            let year = Calendar.current.component(.year, from: selectedDate)
            let all = try await IBTrACSService.historicalCyclones(
                year: year,
                basin: selectedBasin,
                onPhase: { phase in
                    Task { @MainActor in
                        self.loadingMessage = phase
                    }
                }
            )
            historicalCyclones = all
                .compactMap { snapshot(of: $0, on: selectedDate) }
                .sorted { $0.category > $1.category }
            didLoadHistorical = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func snapshot(of cyclone: Cyclone, on day: Date) -> Cyclone? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let dayPoints = cyclone.track.filter { $0.date >= dayStart && $0.date < dayEnd }
        guard let last = dayPoints.last else { return nil }
        let wind = last.windKnots ?? cyclone.windKnots
        let pressure = last.pressureMB ?? cyclone.pressureMB
        return Cyclone(
            id: cyclone.id,
            name: cyclone.name,
            basin: cyclone.basin,
            source: cyclone.source,
            isActive: false,
            windKnots: wind,
            pressureMB: pressure,
            category: StormCategory.fromWind(knots: wind),
            latitude: last.latitude,
            longitude: last.longitude,
            date: last.date,
            track: cyclone.track,
            forecast: []
        )
    }

    func retry() async {
        if mode == .active {
            await refreshActive()
        } else {
            await loadHistorical()
        }
    }

    func cacheRecentYears(basins: [CycloneBasin], count: Int = 10) {
        prefetchTask?.cancel()
        isCachingRecent = true
        cachingMessage = "准备缓存…"
        let currentYear = Calendar.current.component(.year, from: Date())
        let years = Array(max(1851, currentYear - count + 1)...currentYear)
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                for basin in basins {
                    try await IBTrACSService.prefetchRecentYears(basin: basin, years: years) { phase in
                        Task { @MainActor [weak self] in
                            self?.cachingMessage = phase
                        }
                    }
                }
            } catch is CancellationError {
                cachingMessage = "缓存已取消"
            } catch {
                cachingMessage = "缓存失败: \(error.localizedDescription)"
            }
            isCachingRecent = false
        }
    }

    func cancelCaching() {
        prefetchTask?.cancel()
    }

    private func enrichWithActiveRows(_ cyclones: [Cyclone], rows: [IBTrACSService.ActiveRow]) -> [Cyclone] {
        var rowsByAtcfID: [String: [IBTrACSService.ActiveRow]] = [:]
        for row in rows where !row.atcfID.isEmpty {
            rowsByAtcfID[row.atcfID.lowercased(), default: []].append(row)
        }
        return cyclones.map { cyclone in
            guard cyclone.track.isEmpty else { return cyclone }
            let key = cyclone.id.replacingOccurrences(of: "NHC-", with: "").lowercased()
            guard let stormRows = rowsByAtcfID[key] else { return cyclone }
            let track = JTWCService.track(from: stormRows)
            guard let last = track.last else { return cyclone }
            return Cyclone(
                id: cyclone.id,
                name: cyclone.name,
                basin: cyclone.basin,
                source: cyclone.source,
                isActive: cyclone.isActive,
                windKnots: cyclone.windKnots,
                pressureMB: cyclone.pressureMB,
                category: cyclone.category,
                latitude: last.latitude,
                longitude: last.longitude,
                date: last.date,
                track: track,
                forecast: cyclone.forecast
            )
        }
    }

    private func stormsFromActiveRows(
        _ rows: [IBTrACSService.ActiveRow],
        excluding handledAtcfIDs: Set<String>
    ) -> [Cyclone] {
        var bySID: [String: [IBTrACSService.ActiveRow]] = [:]
        for row in rows where !handledAtcfIDs.contains(row.atcfID.lowercased()) {
            bySID[row.sid, default: []].append(row)
        }
        var extra: [Cyclone] = []
        for (sid, stormRows) in bySID {
            let track = JTWCService.track(from: stormRows)
            guard let last = track.last else { continue }
            let wind = stormRows.compactMap(\.windKnots).max() ?? 0
            let pressure = stormRows.compactMap(\.pressureMB).min() ?? 0
            let category = track.map(\.category).max() ?? .disturbance
            let basin = CycloneBasin.fromIBTrACS(stormRows.first?.basin ?? "") ?? .na
            let isActive = last.date.timeIntervalSinceNow > -72 * 3600
            extra.append(Cyclone(
                id: "IB-\(sid)",
                name: stormRows.first?.name ?? "",
                basin: basin,
                source: .ibtracs,
                isActive: isActive,
                windKnots: wind,
                pressureMB: pressure,
                category: category,
                latitude: last.latitude,
                longitude: last.longitude,
                date: last.date,
                track: track,
                forecast: []
            ))
        }
        return extra
    }
}
