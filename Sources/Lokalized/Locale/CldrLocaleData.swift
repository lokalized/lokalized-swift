// Behavior ported from Lokalized Java's CldrLocaleData.
// Copyright 2017-2022 Product Mog LLC, 2022-2026 Revetware LLC.
// Licensed under Apache-2.0; generated CLDR tables retain Unicode-3.0 notices.

/// CLDR's own lenient tag projection. This is not the JDK parser: aliases and
/// range matching deliberately accept forms such as underscore-separated tags.
package struct CldrTagParts: Sendable {
    package var language: String, script: String, region: String
    package var variants: [String], extensions: [String]
    package var privateUse: Bool
    package init(language: String = "", script: String = "", region: String = "", variants: [String] = [],
                 extensions: [String] = [], privateUse: Bool = false) {
        self.language = language; self.script = LanguageRangeLowercase.apply(script) == "zzzz" ? "" : script
        self.region = LanguageRangeLowercase.apply(region) == "zz" ? "" : region
        self.variants = variants; self.extensions = extensions; self.privateUse = privateUse
    }
    package init(_ text: String) {
        // Java String.trim removes only characters at or below U+0020.
        var units = Array(text.utf16)
        var first = 0, end = units.count
        while first < end && units[first] <= 32 { first += 1 }
        while end > first && units[end - 1] <= 32 { end -= 1 }
        units = units[first..<end].map { $0 == 95 ? 45 : $0 }
        let normalized = String(decoding: units, as: UTF16.self)
        if LanguageRangeLowercase.apply(normalized).hasPrefix("x-") {
            self.init(extensions: [LanguageRangeLowercase.apply(normalized)], privateUse: true); return
        }
        var subtags = normalized.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        if subtags.count > 1 { while subtags.last == "" { subtags.removeLast() } }
        var language = "", script = "", region = "", variants: [String] = [], extensions: [String] = [], index = 0
        if let first = subtags.first, !first.isEmpty { language = LanguageRangeLowercase.apply(first); index = 1 }
        if index < subtags.count && LocaleASCII.script(subtags[index]) { script = LocaleASCII.title(subtags[index]); index += 1 }
        if index < subtags.count && LocaleASCII.region(subtags[index]) { region = LocaleASCII.upper(subtags[index]); index += 1 }
        while index < subtags.count && subtags[index].utf16.count != 1 { variants.append(LanguageRangeLowercase.apply(subtags[index])); index += 1 }
        while index < subtags.count { extensions.append(LanguageRangeLowercase.apply(subtags[index])); index += 1 }
        self.init(language: language, script: script, region: region, variants: variants, extensions: extensions)
    }
    package var tag: String {
        if privateUse { return extensions.joined(separator: "-") }
        let values = [language, script, region].filter { !$0.isEmpty } + variants + extensions
        return values.isEmpty ? "und" : values.joined(separator: "-")
    }
    package func with(language: String? = nil, script: String? = nil, region: String? = nil, variants: [String]? = nil) -> Self {
        .init(language: language.map(LanguageRangeLowercase.apply) ?? self.language,
              script: script.map(LocaleASCII.title) ?? self.script, region: region.map(LocaleASCII.upper) ?? self.region,
              variants: variants ?? self.variants, extensions: extensions, privateUse: privateUse)
    }
}

package enum CldrLocaleData {
    private static let compoundAliasKeys = LocaleTables.languageAliases.keys.filter { $0.contains("-") }.sorted {
        $0.utf16.count == $1.utf16.count ? $0 < $1 : $0.utf16.count > $1.utf16.count
    }
    package static func canonicalLanguageTag(_ input: String) -> String {
        var canonical = CldrTagParts(input).tag
        var seen: Set<String> = []
        while seen.insert(LanguageRangeLowercase.apply(canonical)).inserted {
            let aliased = aliasOnce(canonical)
            if aliased == canonical { return canonical }
            canonical = CldrTagParts(aliased).tag
        }
        return canonical
    }
    private static func aliasOnce(_ tag: String) -> String {
        let key = LanguageRangeLowercase.apply(tag)
        if let direct = LocaleTables.languageAliases[key] { return direct }
        for compound in compoundAliasKeys where key.hasPrefix(compound + "-") {
            return LocaleTables.languageAliases[compound]! + String(tag.dropFirst(compound.count))
        }
        var parts = CldrTagParts(tag)
        if parts.privateUse { return parts.tag }
        if let alias = LocaleTables.languageAliases[LanguageRangeLowercase.apply(parts.language)] {
            let aliased = CldrTagParts(alias)
            parts = parts.with(language: aliased.language.isEmpty ? parts.language : aliased.language,
                               script: parts.script.isEmpty && !aliased.script.isEmpty ? aliased.script : nil,
                               region: parts.region.isEmpty && !aliased.region.isEmpty ? aliased.region : nil,
                               variants: parts.variants.isEmpty && !aliased.variants.isEmpty ? aliased.variants : nil)
        }
        if let alias = LocaleTables.scriptAliases[LanguageRangeLowercase.apply(parts.script)], !parts.script.isEmpty {
            parts = parts.with(script: CldrTagParts("und-" + alias).script)
        }
        if let aliases = LocaleTables.regionAliases[LanguageRangeLowercase.apply(parts.region)], !parts.region.isEmpty {
            parts = parts.with(region: preferredRegion(parts, aliases: aliases.split(separator: " ").map(String.init)))
        }
        if !parts.variants.isEmpty { parts = parts.with(variants: parts.variants.map { LocaleTables.variantAliases[LanguageRangeLowercase.apply($0)] ?? $0 }) }
        return parts.tag
    }
    private static func preferredRegion(_ parts: CldrTagParts, aliases: [String]) -> String {
        if aliases.count == 1 { return aliases[0] }
        for candidate in likelyCandidates(parts.with(region: "")) {
            guard let likely = LocaleTables.likelySubtags[LanguageRangeLowercase.apply(candidate)] else { continue }
            let region = CldrTagParts(likely).region
            if let matched = aliases.first(where: { LanguageRangeLowercase.apply($0) == LanguageRangeLowercase.apply(region) }) { return matched }
        }
        return aliases.first ?? ""
    }
    private static func appendUnique(_ tag: String, to values: inout [String], seen: inout Set<String>) {
        if seen.insert(tag).inserted { values.append(tag) }
    }
    private static func likelyCandidates(_ parts: CldrTagParts) -> [String] {
        let language = parts.language.isEmpty ? "und" : parts.language
        var result: [String] = [], seen: Set<String> = []
        appendUnique(parts.tag, to: &result, seen: &seen)
        if !parts.script.isEmpty && !parts.region.isEmpty { appendUnique(language + "-" + parts.script + "-" + parts.region, to: &result, seen: &seen) }
        if !parts.script.isEmpty { appendUnique(language + "-" + parts.script, to: &result, seen: &seen) }
        if !parts.region.isEmpty { appendUnique(language + "-" + parts.region, to: &result, seen: &seen) }
        appendUnique(language, to: &result, seen: &seen)
        if !parts.script.isEmpty { appendUnique("und-" + parts.script, to: &result, seen: &seen) }
        if !parts.region.isEmpty { appendUnique("und-" + parts.region, to: &result, seen: &seen) }
        appendUnique("und", to: &result, seen: &seen)
        return result
    }
    package static func likelySubtagFor(_ tag: String) -> String? {
        let requested = CldrTagParts(canonicalLanguageTag(tag))
        guard !requested.privateUse && !requested.language.isEmpty else { return nil }
        for candidate in likelyCandidates(requested) {
            guard let value = LocaleTables.likelySubtags[LanguageRangeLowercase.apply(candidate)] else { continue }
            let likely = CldrTagParts(canonicalLanguageTag(value))
            return CldrTagParts(language: requested.language.isEmpty || requested.language == "und" ? likely.language : requested.language,
                                script: requested.script.isEmpty ? likely.script : requested.script,
                                region: requested.region.isEmpty ? likely.region : requested.region, variants: requested.variants).tag
        }
        return nil
    }
    package static func languageScriptForLikelySubtag(_ tag: String) -> String? {
        guard let likely = likelySubtagFor(tag) else { return nil }
        let parts = CldrTagParts(likely)
        return parts.language.isEmpty || parts.script.isEmpty ? nil : parts.language + "-" + parts.script
    }
    package static func isRightToLeftScript(_ script: String) -> Bool { LocaleTables.rightToLeftScripts.contains(LanguageRangeLowercase.apply(script)) }
    package static func hasUndeterminedLanguage(_ tag: String) -> Bool { let parts = CldrTagParts(tag); return parts.language.isEmpty || LanguageRangeLowercase.apply(parts.language) == "und" }
    package static func isPrivateUseLanguageTag(_ tag: String) -> Bool { CldrTagParts(tag).privateUse }
    package static func equivalentTags(_ left: String, _ right: String) -> Bool { LanguageRangeLowercase.apply(canonicalLanguageTag(left)) == LanguageRangeLowercase.apply(canonicalLanguageTag(right)) }
    package static func isKnownLanguageTag(_ tag: String) -> Bool {
        let parts = CldrTagParts(tag)
        if parts.privateUse { return true }
        if LocaleTables.languageAliases[LanguageRangeLowercase.apply(parts.tag)] != nil || LocaleTables.languageAliases[LanguageRangeLowercase.apply(tag)] != nil { return true }
        let explicit = LanguageRangeLowercase.apply(tag) == "und" || LanguageRangeLowercase.apply(tag).hasPrefix("und-")
        if parts.language.isEmpty && !explicit { return false }
        if !parts.language.isEmpty && !explicit && !LocaleTables.validLanguages.contains(LanguageRangeLowercase.apply(parts.language))
            && LocaleTables.languageAliases[LanguageRangeLowercase.apply(parts.language)] == nil { return false }
        if !parts.script.isEmpty && !LocaleTables.validScripts.contains(LanguageRangeLowercase.apply(parts.script)) && LocaleTables.scriptAliases[LanguageRangeLowercase.apply(parts.script)] == nil { return false }
        if !parts.region.isEmpty && !LocaleTables.validRegions.contains(LanguageRangeLowercase.apply(parts.region)) && LocaleTables.regionAliases[LanguageRangeLowercase.apply(parts.region)] == nil { return false }
        return parts.variants.allSatisfy { LocaleTables.validVariants.contains(LanguageRangeLowercase.apply($0)) || LocaleTables.variantAliases[LanguageRangeLowercase.apply($0)] != nil }
    }
    private static func addParents(_ tag: String, values: inout [String], seen: inout Set<String>) -> Bool {
        var candidate = tag, visited: Set<String> = []
        while visited.insert(LanguageRangeLowercase.apply(candidate)).inserted {
            guard let parent = LocaleTables.parentLocales[LanguageRangeLowercase.apply(candidate)] else { return false }
            appendUnique(parent, to: &values, seen: &seen)
            if parent == "root" { return true }
            candidate = parent
        }
        return false
    }
    private static func addFallback(_ tag: String, bridges: Bool, values: inout [String], seen: inout Set<String>) {
        let requestedScript = languageScriptForLikelySubtag(tag)
        appendUnique(tag, to: &values, seen: &seen)
        var rootReached = addParents(tag, values: &values, seen: &seen)
        var candidate = tag
        while !rootReached, let separator = candidate.lastIndex(of: "-"), separator > candidate.startIndex {
            candidate = String(candidate[..<separator])
            if let requestedScript, let candidateScript = languageScriptForLikelySubtag(candidate),
               LanguageRangeLowercase.apply(requestedScript) != LanguageRangeLowercase.apply(candidateScript) { break }
            appendUnique(candidate, to: &values, seen: &seen)
            rootReached = addParents(candidate, values: &values, seen: &seen)
        }
        if bridges {
            let parts = CldrTagParts(tag)
            if parts.language == "no" { addFallback(parts.with(language: "nb").tag, bridges: false, values: &values, seen: &seen) }
            if parts.language == "nb" { addFallback(parts.with(language: "no").tag, bridges: false, values: &values, seen: &seen) }
        }
    }
    package static func fallbackLocalesFor(_ tag: String) -> [LocaleTag] {
        var values: [String] = [], seen: Set<String> = []
        let canonical = canonicalLanguageTag(tag)
        addFallback(tag, bridges: true, values: &values, seen: &seen)
        addFallback(canonical, bridges: true, values: &values, seen: &seen)
        _ = addParents(canonical, values: &values, seen: &seen)
        var locales: [LocaleTag] = [], localeSet: Set<LocaleTag> = []
        for value in values where value != "root" {
            let locale = LocaleTag.forLanguageTag(value)
            if localeSet.insert(locale).inserted { locales.append(locale) }
        }
        return locales
    }
    package static func fallbackLocaleTagsFor(_ tag: String) -> [String] { fallbackLocalesFor(tag).map(\.tag) }
    package static func pluralCandidateTags(for locale: LocaleTag) throws -> [String] {
        try JDKLocaleTag.requireWellFormed(locale, description: "Locale")
        let canonical = canonicalLanguageTag(locale.tag)
        let language = CldrTagParts(canonical).language
        let projected = LocaleTag.forLanguageTag(canonical)
        if language.isEmpty || LanguageRangeLowercase.apply(language) == "und" || isPrivateUseLanguageTag(canonical) {
            return hasUndeterminedLanguage(projected.tag) ? ["root"] : []
        }
        var values: [String] = [], seen: Set<String> = []
        if !projected.script.isEmpty && !projected.region.isEmpty { appendUnique(language + "-" + projected.script + "-" + projected.region, to: &values, seen: &seen) }
        if !projected.script.isEmpty { appendUnique(language + "-" + projected.script, to: &values, seen: &seen) }
        if !projected.region.isEmpty { appendUnique(language + "-" + projected.region, to: &values, seen: &seen) }
        appendUnique(language, to: &values, seen: &seen)
        return values
    }
}
