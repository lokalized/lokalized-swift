import Foundation
import Lokalized

/// Reproduces the source transport's JSON.stringify(value, null, 2) shape without
/// a String-keyed dictionary or numeric conversion. The frozen corpus numbers
/// used in files are already canonical JSON numeric literals.
enum FixtureJSONWriter {
    static func bytes(_ value: JSONValue) throws -> Data {
        Data((try write(value, level: 0) + "\n").utf8)
    }

    private static func write(_ value: JSONValue, level: Int) throws -> String {
        let indent = String(repeating: "  ", count: level + 1)
        let closing = String(repeating: "  ", count: level)
        switch value {
        case .object(let members):
            _ = try value.checkedObject(at: "fixture")
            if members.isEmpty { return "{}" }
            // JS own property iteration promotes canonical array-index names.
            let indexed = members.enumerated().sorted { lhs, rhs in
                let left = arrayIndex(lhs.element.name.string)
                let right = arrayIndex(rhs.element.name.string)
                switch (left, right) {
                case (.some(let a), .some(let b)): return a < b
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.offset < rhs.offset
                }
            }.map(\.element)
            let rows = try indexed.map { member in indent + quote(member.name.string) + ": " + (try write(member.value, level: level + 1)) }
            return "{\n" + rows.joined(separator: ",\n") + "\n" + closing + "}"
        case .array(let elements):
            if elements.isEmpty { return "[]" }
            return "[\n" + (try elements.map { indent + (try write($0, level: level + 1)) }).joined(separator: ",\n") + "\n" + closing + "]"
        case .string(let string): return quote(string)
        case .number(let literal): return literal
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        }
    }

    private static func arrayIndex(_ string: String) -> UInt32? {
        let bytes = Array(string.utf8)
        guard !bytes.isEmpty, bytes.allSatisfy({ (48...57).contains($0) }),
              let value = UInt32(string), value < UInt32.max, String(value) == string else { return nil }
        return value
    }

    static func quote(_ string: String) -> String {
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 8: result += "\\b"
            case 9: result += "\\t"
            case 10: result += "\\n"
            case 12: result += "\\f"
            case 13: result += "\\r"
            case 0..<32:
                let hex = String(scalar.value, radix: 16)
                result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
