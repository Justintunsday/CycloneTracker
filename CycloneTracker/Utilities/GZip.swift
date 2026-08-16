import Compression
import Foundation

enum GZip {
    static func decompress(_ data: Data) throws -> Data {
        guard data.count > 18, data[data.startIndex] == 0x1F, data[data.startIndex + 1] == 0x8B else {
            throw APIError.invalidData(L("gzip 文件头无效"))
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
        guard offset < data.count else { throw APIError.invalidData(L("gzip 文件头损坏")) }
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
