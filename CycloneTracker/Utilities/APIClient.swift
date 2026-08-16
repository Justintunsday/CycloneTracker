import Foundation

enum APIError: LocalizedError {
    case invalidURL(String)
    case badStatus(Int, String)
    case invalidData(String)
    case rangeNotSupported

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return String(format: L("无效的请求地址: %@"), url)
        case .badStatus(let code, let url):
            return String(format: L("服务器返回错误 (%d): %@"), code, url)
        case .invalidData(let detail):
            return String(format: L("数据解析失败: %@"), detail)
        case .rangeNotSupported:
            return L("服务器不支持分段下载")
        }
    }
}

struct APIClient: Sendable {
    static let shared = APIClient()

    func data(from urlString: String, timeout: TimeInterval = 120) async throws -> Data {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL(urlString) }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("CycloneTracker/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode, urlString)
        }
        return data
    }

    func rangeData(from urlString: String, range: String, timeout: TimeInterval = 60) async throws -> (data: Data, totalSize: Int?) {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL(urlString) }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("CycloneTracker/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(range, forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidData(L("服务器无响应"))
        }
        guard http.statusCode == 206 else {
            if (200...299).contains(http.statusCode) {
                throw APIError.rangeNotSupported
            }
            throw APIError.badStatus(http.statusCode, urlString)
        }
        var totalSize: Int?
        if let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
           let slashIndex = contentRange.lastIndex(of: "/") {
            totalSize = Int(contentRange[contentRange.index(after: slashIndex)...])
        }
        return (data, totalSize)
    }

    func download(to fileURL: URL, from urlString: String, timeout: TimeInterval = 600) async throws {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL(urlString) }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("CycloneTracker/1.0", forHTTPHeaderField: "User-Agent")
        let (tempURL, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode, urlString)
        }
        try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: tempURL, to: fileURL)
    }
}
