package enum MatchingLocale {
    package static func validated(_ text: String, description: String) throws -> LocaleTag {
        guard JDKLocaleTag.parse(text).wellFormed else {
            throw LocaleMatcherError("\(description) '\(text)' is not a well-formed IETF BCP 47 locale")
        }
        let locale = LocaleTag.forLanguageTag(text)
        try JDKLocaleTag.requireWellFormed(locale, description: description)
        return locale
    }

    package static func requireRangeCount(_ count: Int) throws {
        if count > DefaultLocaleMatcher.maximumLanguageRanges {
            throw LocaleMatcherError("At most \(DefaultLocaleMatcher.maximumLanguageRanges) language ranges are supported, but received \(count)")
        }
    }

    package static func equal(_ first: String, _ second: String) -> Bool { first.lowercased() == second.lowercased() }
    package static func split(_ text: String) -> [String] {
        var parts = text.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        while parts.last == "" { parts.removeLast() }
        return parts
    }
    package static func canonical(_ tag: String) -> String { CldrLocaleData.canonicalLanguageTag(tag) }
    package static func equivalent(_ first: String, _ second: String) -> Bool { equal(canonical(first), canonical(second)) }
    package static func primary(_ tag: String) -> String {
        let canonicalTag = canonical(LocaleTag.forLanguageTag(tag).tag)
        if canonicalTag.lowercased().hasPrefix("x-") || canonicalTag.lowercased() == "x" { return "" }
        let language = split(canonicalTag).first ?? ""
        return equal(language, "und") ? "" : language
    }
    package static func normalizedLanguageCode(_ code: String) -> String {
        let language = primary(code)
        return (language.isEmpty ? code : language).lowercased()
    }
    package static func compatible(_ requested: String?, _ available: String?) -> Bool {
        guard let requested, let available else { return true }
        return equal(requested, available)
    }
    package static func structuralDepth(_ range: String) -> Int {
        range.split(separator: "-", omittingEmptySubsequences: false).filter { $0 != "*" }.count
    }
    package static func normalizedExtended(_ range: String) -> String {
        let parts = split(range)
        guard let first = parts.first else { return "" }
        return ([first] + parts.dropFirst().filter { $0 != "*" }).joined(separator: "-")
    }
    package static func structuralMatch(_ range: [String], _ tag: [String]) -> Bool {
        guard let firstRange = range.first, let firstTag = tag.first,
              firstRange == "*" || equal(firstRange, firstTag) else { return false }
        var rangeIndex = 1, tagIndex = 1
        while rangeIndex < range.count {
            let rangeSubtag = range[rangeIndex]
            if rangeSubtag == "*" { rangeIndex += 1; continue }
            if tagIndex >= tag.count { return false }
            let tagSubtag = tag[tagIndex]
            if equal(rangeSubtag, tagSubtag) { rangeIndex += 1; tagIndex += 1 }
            else if tagSubtag.utf8.count == 1 { return false }
            else { tagIndex += 1 }
        }
        return true
    }

    /// Java Double.compare order, including signed zeros and canonical NaNs.
    package static func compareWeight(_ first: Double, _ second: Double) -> Int {
        if first < second { return -1 }
        if first > second { return 1 }
        if first.isNaN { return second.isNaN ? 0 : 1 }
        if second.isNaN { return -1 }
        if first == 0 && second == 0 && first.sign != second.sign { return first.sign == .minus ? -1 : 1 }
        return 0
    }

    package static func javaTrim(_ text: String) -> String {
        let units = text.utf16
        let start = units.firstIndex { $0 > 32 } ?? units.endIndex
        let end = units.lastIndex { $0 > 32 }.map { units.index(after: $0) } ?? start
        return String(decoding: units[start..<end], as: UTF16.self)
    }
    package static func normalizedAcceptLanguage(_ text: String) -> String {
        text.split(separator: ",", omittingEmptySubsequences: false).compactMap { member -> String? in
            let units = member.utf16
            let start = units.firstIndex { $0 != 32 && $0 != 9 } ?? units.endIndex
            let end = units.lastIndex { $0 != 32 && $0 != 9 }.map { units.index(after: $0) } ?? start
            if start == end { return nil }
            return String(decoding: units[start..<end].map { $0 == 9 ? 32 : $0 }, as: UTF16.self)
        }.joined(separator: ",")
    }
}
