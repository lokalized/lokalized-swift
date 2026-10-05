// Behavior ported from Lokalized's Java/JS locale projection.
// Copyright 2017-2022 Product Mog LLC, 2022-2026 Revetware LLC.
// Licensed under Apache-2.0; see LICENSE.

package enum JDKLocaleTag {
    package struct Parts: Sendable {
        package var language = "", extlangs: [String] = [], script = "", region = ""
        package var variants: [String] = [], extensions: [[String]] = [], privateuse: [String] = []
        package var wellFormed = true, undetermined = false
    }
    private static let grandfathered: [String: String] = [
        "art-lojban": "jbo", "cel-gaulish": "xtg-x-cel-gaulish", "en-gb-oed": "en-GB-x-oed",
        "i-ami": "ami", "i-bnn": "bnn", "i-default": "en-x-i-default", "i-enochian": "und-x-i-enochian",
        "i-hak": "hak", "i-klingon": "tlh", "i-lux": "lb", "i-mingo": "see-x-i-mingo", "i-navajo": "nv",
        "i-pwn": "pwn", "i-tao": "tao", "i-tay": "tay", "i-tsu": "tsu", "no-bok": "nb", "no-nyn": "nn",
        "sgn-be-fr": "sfb", "sgn-be-nl": "vgt", "sgn-ch-de": "sgg", "zh-guoyu": "cmn", "zh-hakka": "hak",
        "zh-min": "nan-x-zh-min", "zh-min-nan": "nan", "zh-xiang": "hsn"
    ]
    package static func parse(_ text: String) -> Parts {
        let source = grandfathered[LocaleASCII.lower(text)] ?? text
        var parts = Parts()
        guard !source.isEmpty else { parts.wellFormed = false; return parts }
        let subtags = LocaleASCII.splitSubtags(source)
        var index = 0
        if LocaleASCII.language(subtags[0]) {
            parts.language = LocaleASCII.lower(subtags[0]); parts.undetermined = subtags[0] == "und"; index += 1
            while index < subtags.count && parts.extlangs.count < 3 && subtags[index].utf8.count == 3 && LocaleASCII.alpha(subtags[index]) {
                parts.extlangs.append(LocaleASCII.lower(subtags[index])); index += 1
            }
            if index < subtags.count && LocaleASCII.script(subtags[index]) { parts.script = LocaleASCII.title(subtags[index]); index += 1 }
            if index < subtags.count && LocaleASCII.region(subtags[index]) { parts.region = LocaleASCII.upper(subtags[index]); index += 1 }
            while index < subtags.count && LocaleASCII.variant(subtags[index]) { parts.variants.append(subtags[index]); index += 1 }
            while index < subtags.count && singleton(subtags[index]) {
                let key = LocaleASCII.lower(subtags[index]); index += 1
                var values: [String] = []
                while index < subtags.count && (2...8).contains(subtags[index].utf8.count) && LocaleASCII.alphanumeric(subtags[index]) {
                    values.append(LocaleASCII.lower(subtags[index])); index += 1
                }
                guard !values.isEmpty else { parts.wellFormed = false; return parts }
                parts.extensions.append([key] + values)
            }
        }
        if index < subtags.count && LocaleASCII.lower(subtags[index]) == "x" {
            index += 1
            while index < subtags.count && LocaleASCII.privateSubtag(subtags[index]) { parts.privateuse.append(subtags[index]); index += 1 }
            guard !parts.privateuse.isEmpty else { parts.wellFormed = false; return parts }
        }
        if index < subtags.count { parts.wellFormed = false }
        return parts
    }
    private static func singleton(_ text: String) -> Bool { text.utf8.count == 1 && LocaleASCII.alpha(text) && LocaleASCII.lower(text) != "x" }
    private static func privateVariantIndex(_ parts: [String]) -> Int? {
        guard let index = parts.firstIndex(where: { LocaleASCII.lower($0) == "lvariant" }), index + 1 < parts.count else { return nil }
        return index
    }
    private static func unicodeValue(_ values: [String]) -> String {
        var index = 0, attributes: Set<String> = []
        while index < values.count && (3...8).contains(values[index].utf8.count) { attributes.insert(values[index]); index += 1 }
        var keywords: [String: [String]] = [:], key: String?, type: [String] = []
        while index < values.count {
            let value = values[index]
            if let current = key {
                if value.utf8.count == 2 { keywords[current] = type; key = keywords[value] == nil ? value : nil; type = [] }
                else { type.append(value) }
            } else if value.utf8.count == 2 { key = keywords[value] == nil ? value : nil }
            if index == values.count - 1, let current = key { keywords[current] = type }
            index += 1
        }
        return (attributes.sorted() + keywords.keys.sorted().flatMap { [$0] + keywords[$0]! }).joined(separator: "-")
    }
    package static func make(_ parts: Parts) -> LocaleTag {
        var language = parts.extlangs.first ?? (parts.undetermined ? "" : parts.language)
        if language == "iw" { language = "he" }; if language == "ji" { language = "yi" }; if language == "in" { language = "id" }
        var variants = parts.variants
        var extensions: [String: String] = [:]
        for value in parts.extensions where extensions[value[0]] == nil {
            let payload = value[0] == "u" ? unicodeValue(Array(value.dropFirst())) : value.dropFirst().joined(separator: "-")
            if !payload.isEmpty { extensions[value[0]] = payload }
        }
        if !parts.privateuse.isEmpty {
            if let index = privateVariantIndex(parts.privateuse) {
                variants += parts.privateuse.dropFirst(index + 1)
                if index > 0 { extensions["x"] = LocaleASCII.lower(parts.privateuse.prefix(index).joined(separator: "-")) }
            } else { extensions["x"] = LocaleASCII.lower(parts.privateuse.joined(separator: "-")) }
        }
        let variant = variants.joined(separator: "_")
        if extensions.isEmpty && parts.script.isEmpty {
            if language == "ja" && parts.region == "JP" && variant == "JP" { extensions["u"] = "ca-japanese" }
            if language == "th" && parts.region == "TH" && variant == "TH" { extensions["u"] = "nu-thai" }
        }
        var tagLanguage = language
        var renderedVariants = variants
        if language == "no" && parts.region == "NO" && variant == "NY" { tagLanguage = "nn"; renderedVariants = [] }
        var valid: [String] = [], illFormed: [String] = []
        var index = 0
        while index < renderedVariants.count && LocaleASCII.variant(renderedVariants[index]) { valid.append(renderedVariants[index]); index += 1 }
        while index < renderedVariants.count && LocaleASCII.privateSubtag(renderedVariants[index]) { illFormed.append(renderedVariants[index]); index += 1 }
        var privateuse = extensions["x"]
        if !illFormed.isEmpty { privateuse = (privateuse.map { $0 + "-" } ?? "") + "lvariant-" + illFormed.joined(separator: "-") }
        let nonprivate = extensions.keys.filter { $0 != "x" }.sorted().map { $0 + "-" + extensions[$0]! }
        if tagLanguage.isEmpty && (!parts.script.isEmpty || !parts.region.isEmpty || !valid.isEmpty || !nonprivate.isEmpty || privateuse == nil) { tagLanguage = "und" }
        var components = [tagLanguage, parts.script, parts.region].filter { !$0.isEmpty } + valid + nonprivate
        if let privateuse, !privateuse.isEmpty { components.append("x-" + privateuse) }
        return .init(tag: components.joined(separator: "-"), language: language, script: parts.script, region: parts.region,
                     variants: variants, extensions: extensions)
    }
    @discardableResult package static func requireWellFormed(_ locale: LocaleTag, description: String) throws -> LocaleTag {
        let variant = locale.variants.joined(separator: "_")
        let exception = (locale.language == "ja" && locale.region == "JP" && variant == "JP")
            || (locale.language == "th" && locale.region == "TH" && variant == "TH")
            || (locale.language == "no" && locale.region == "NO" && variant == "NY")
        guard (locale.language.isEmpty || LocaleASCII.language(locale.language))
                && (locale.script.isEmpty || LocaleASCII.script(locale.script))
                && (locale.region.isEmpty || LocaleASCII.region(locale.region))
                && (exception || locale.variants.allSatisfy(LocaleASCII.variant)) else {
            throw LocaleTagError(.malformedLocale, "\(description) '\(locale.javaIdentifier)' is not a well-formed IETF BCP 47 locale")
        }
        return locale
    }
    package static func isCatalogLanguageTag(_ text: String) -> Bool {
        let groups = LocaleASCII.splitSubtags(text)
        guard !groups.isEmpty && groups.allSatisfy(LocaleASCII.alphanumeric) && parse(text).wellFormed else { return false }
        if LocaleASCII.lower(text).hasPrefix("x-") { return true }
        let explicit = LocaleASCII.lower(text) == "und" || LocaleASCII.lower(text).hasPrefix("und-")
        return (!make(parse(text)).language.isEmpty || explicit) && CldrLocaleData.isKnownLanguageTag(text)
    }
}
