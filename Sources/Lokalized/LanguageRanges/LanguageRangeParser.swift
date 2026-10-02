package enum LanguageRangeParser {
    /// Strict public header parsing has no length or member cap. Negotiation's
    /// fail-soft HTTP ingress and direct-list count limits are separate layers.
    package static func parse(_ header: String, equivalents: LanguageRangeEquivalents = .ianaRegistry) throws -> [LanguageRange] {
        var normalized = Array(LanguageRangeLowercase.apply(String(header.unicodeScalars.filter { $0.value != 0x20 })).utf8)
        if normalized.starts(with: Array("accept-language:".utf8)) { normalized.removeFirst(16) }
        var members = normalized.split(separator: 44, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        if normalized.contains(44) { while members.last == "" { members.removeLast() } }
        var list: [LanguageRange] = []
        var seen = Set<String>()
        for member in members {
            var range = member
            var weight: Double = 1
            let memberBytes = Array(member.utf8)
            if let separator = firstOccurrence(Array(";q=".utf8), in: memberBytes) {
                range = String(decoding: memberBytes[..<separator], as: UTF8.self)
                let text = String(decoding: memberBytes[(separator + 3)...], as: UTF8.self)
                guard let parsed = LanguageRangeWeight.parse(text) else {
                    throw LanguageRangeError("weight=\"\(text)\" for language range \"\(range)\"")
                }
                weight = parsed
                if weight < 0 || weight > 1 {
                    throw LanguageRangeError("weight=\(JavaFloatingPoint.render(weight)) for language range \"\(range)\". It must be between 0.0 and 1.0.")
                }
            }
            if seen.contains(range) { continue }
            let parsed = try LanguageRange(range, weight: weight)
            let index = list.firstIndex { $0.weight < weight } ?? list.endIndex
            list.insert(parsed, at: index)
            seen.insert(range)
            for equivalent in expansions(range, equivalents: equivalents) where seen.insert(equivalent).inserted {
                list.insert(try LanguageRange(equivalent, weight: weight), at: index + 1)
            }
        }
        return list
    }

    package static func validateGrammar(_ range: String) throws {
        let bytes = Array(range.utf8)
        if !bytes.isEmpty && bytes.allSatisfy({ $0 == 45 }) {
            throw LanguageRangeError(.indexOutOfBounds, "Index 0 out of bounds for length 0")
        }
        let subtags = bytes.split(separator: 45, omittingEmptySubsequences: false)
        for (index, subtag) in subtags.enumerated() {
            guard (1...8).contains(subtag.count) else { throw LanguageRangeError("range=" + range) }
            if subtag.count == 1 && subtag.first == 42 { continue }
            guard subtag.allSatisfy({ (97...122).contains($0) || (index > 0 && (48...57).contains($0)) }) else {
                throw LanguageRangeError("range=" + range)
            }
        }
    }

    /// Authored insertion order. A parsed list inserts each at original+1, which
    /// reverses this sequence. Matching identities must preserve this distinction.
    package static func expansions(_ range: String, equivalents: LanguageRangeEquivalents = .ianaRegistry) -> [String] {
        var values: [String] = []
        if let own = equivalentForRegionAndVariant(range) { values.append(own) }
        for other in languageEquivalents(range, equivalents: equivalents) {
            values.append(other)
            if let nested = equivalentForRegionAndVariant(other) { values.append(nested) }
        }
        return values
    }

    package static func languageEquivalents(_ range: String, equivalents: LanguageRangeEquivalents = .ianaRegistry) -> [String] {
        var prefix = range
        while !prefix.isEmpty {
            if let others = LanguageRangeTables.equivalents(for: prefix, jdk: equivalents == .jdk) {
                let suffix = range.dropFirst(prefix.count)
                return others.map { $0 + suffix }
            }
            guard let dash = prefix.lastIndex(of: "-") else { break }
            prefix = String(prefix[..<dash])
        }
        return []
    }

    private static func firstOccurrence(_ needle: [UInt8], in bytes: [UInt8]) -> Int? {
        guard needle.count <= bytes.count else { return nil }
        for start in 0...(bytes.count - needle.count) where bytes[start..<(start + needle.count)].elementsEqual(needle) { return start }
        return nil
    }

    package static func equivalentForRegionAndVariant(_ range: String) -> String? {
        // Input is grammar-checked ASCII. A singleton extension is recognized
        // by two hyphens separated by one character, exactly as in the JDK.
        let bytes = Array(range.utf8)
        var priorDash: Int?
        var extensionIndex: Int?
        for position in bytes.indices.dropFirst() where bytes[position] == 45 {
            if let priorDash, position - priorDash == 2 { extensionIndex = priorDash; break }
            priorDash = position
        }
        for (from, to) in LanguageRangeTables.regionVariantEquivalents {
            let fromBytes = Array(from.utf8)
            guard let position = firstOccurrence(fromBytes, in: bytes) else { continue }
            if let extensionIndex, position > extensionIndex { continue }
            let end = position + fromBytes.count
            if end == bytes.count || bytes[end] == 45 {
                return String(decoding: bytes[..<position], as: UTF8.self) + to + String(decoding: bytes[end...], as: UTF8.self)
            }
        }
        return nil
    }
}
