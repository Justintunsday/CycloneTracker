import Foundation

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
