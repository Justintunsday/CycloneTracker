import Compression
import Foundation

enum APIError: LocalizedError {
    case invalidURL(String)
    case badStatus(Int, String)
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "无效的请求地址: \(url)"
        case .badStatus(let code, let url):
            return "服务器返回错误 (\(code)): \(url)"
        case .invalidData(let detail):
            return "数据解析失败: \(detail)"
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
        return try inflate(data.subdata(in: offset..<data.count))
    }

    private static func inflate(_ source: Data) throws -> Data {
        var src = [UInt8](source)
        var output = Data()
        let chunkSize = 64 * 1024
        let status: compression_status = src.withUnsafeMutableBufferPointer { srcPointer -> compression_status in
            guard let srcBase = srcPointer.baseAddress else { return COMPRESSION_STATUS_ERROR }
            var stream = compression_stream()
            guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else {
                return COMPRESSION_STATUS_ERROR
            }
            defer { compression_stream_destroy(&stream) }
            stream.src_ptr = UnsafePointer(srcBase)
            stream.src_size = srcPointer.count
            var result: compression_status = COMPRESSION_STATUS_OK
            repeat {
                var destination = [UInt8](repeating: 0, count: chunkSize)
                destination.withUnsafeMutableBufferPointer { dstPointer in
                    stream.dst_ptr = dstPointer.baseAddress!
                    stream.dst_size = dstPointer.count
                    result = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE))
                    output.append(dstPointer.baseAddress!, count: chunkSize - stream.dst_size)
                }
            } while result == COMPRESSION_STATUS_OK
            return result
        }
        guard status == COMPRESSION_STATUS_END else {
            throw APIError.invalidData("gzip 解压失败")
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
