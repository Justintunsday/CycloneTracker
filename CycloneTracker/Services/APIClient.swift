import Compression
import Foundation

enum APIError: LocalizedError {
    case invalidURL(String)
    case badStatus(Int, String)
    case invalidData(String)
    case rangeNotSupported

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "无效的请求地址: \(url)"
        case .badStatus(let code, let url):
            return "服务器返回错误 (\(code)): \(url)"
        case .invalidData(let detail):
            return "数据解析失败: \(detail)"
        case .rangeNotSupported:
            return "服务器不支持分段下载"
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
            throw APIError.invalidData("服务器无响应")
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

enum GZip {
    static func decompress(_ data: Data) throws -> Data {
        guard data.count > 18, data[data.startIndex] == 0x1F, data[data.startIndex + 1] == 0x8B else {
            throw APIError.invalidData("gzip 文件头无效")
        }
        var offset = 10
        let flags = data[data.startIndex + 3]
        if flags & 0x04 != 0, offset + 2 <= data.count {
            let length = Int(data[data.startIndex + offset]) | (Int(data[data.startIndex + offset + 1]) << 8)
            offset += 2 + length
        }
        if flags & 0x08 != 0 {
            while offset < data.count, data[data.startIndex + offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 {
            while offset < data.count, data[data.startIndex + offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }
        guard offset < data.count else { throw APIError.invalidData("gzip 文件头损坏") }
        let payload = data.subdata(in: offset..<data.count)
        var cursor = 0
        let filter = try InputFilter<Data>(.decompress, using: .zlib) { maxLength in
            guard cursor < payload.count else { return nil }
            let end = min(cursor + maxLength, payload.count)
            let chunk = payload.subdata(in: cursor..<end)
            cursor = end
            return chunk
        }
        var output = Data()
        while let chunk = try filter.readData(ofLength: 64 * 1024), !chunk.isEmpty {
            output.append(chunk)
        }
        return output
    }
}

enum CSVParser {
    static func fields(in line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if inQuotes {
                if character == "\"" {
                    let next = line.index(after: index)
                    if next < line.endIndex, line[next] == "\"" {
                        current.append("\"")
                        index = line.index(after: next)
                    } else {
                        inQuotes = false
                        index = next
                    }
                } else {
                    current.append(character)
                    index = line.index(after: index)
                }
            } else if character == "\"" {
                inQuotes = true
                index = line.index(after: index)
            } else if character == "," {
                fields.append(current)
                current = ""
                index = line.index(after: index)
            } else {
                current.append(character)
                index = line.index(after: index)
            }
        }
        fields.append(current)
        return fields
    }
}

enum DateParsing {
    static func parseISO(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    static let ibtracsFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static let atcfFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHH"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
