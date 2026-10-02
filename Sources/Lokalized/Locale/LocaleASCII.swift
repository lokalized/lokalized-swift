/// BCP 47's ASCII casing and predicates, independent of host Unicode tables.
package enum LocaleASCII {
    package static func lower(_ text: String) -> String {
        String(decoding: text.utf8.map { (65...90).contains($0) ? $0 + 32 : $0 }, as: UTF8.self)
    }
    package static func upper(_ text: String) -> String {
        String(decoding: text.utf8.map { (97...122).contains($0) ? $0 - 32 : $0 }, as: UTF8.self)
    }
    package static func title(_ text: String) -> String {
        let bytes = Array(lower(text).utf8)
        guard let first = bytes.first else { return "" }
        return String(decoding: [(97...122).contains(first) ? first - 32 : first] + bytes.dropFirst(), as: UTF8.self)
    }
    package static func alpha(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) }
    }
    package static func numeric(_ text: String) -> Bool { !text.isEmpty && text.utf8.allSatisfy { (48...57).contains($0) } }
    package static func alphanumeric(_ text: String) -> Bool { !text.isEmpty && text.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) } }
    package static func language(_ text: String) -> Bool { (2...8).contains(text.utf8.count) && alpha(text) }
    package static func script(_ text: String) -> Bool { text.utf8.count == 4 && alpha(text) }
    package static func region(_ text: String) -> Bool { (text.utf8.count == 2 && alpha(text)) || (text.utf8.count == 3 && numeric(text)) }
    package static func variant(_ text: String) -> Bool {
        ((5...8).contains(text.utf8.count) || (text.utf8.count == 4 && text.utf8.first.map { (48...57).contains($0) } == true)) && alphanumeric(text)
    }
    package static func privateSubtag(_ text: String) -> Bool { (1...8).contains(text.utf8.count) && alphanumeric(text) }
}
