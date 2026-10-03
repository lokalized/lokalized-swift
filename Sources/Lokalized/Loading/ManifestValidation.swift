import Foundation

public extension LocalizedStringLoader {
    /// Parses bounded source bytes, retaining duplicate diagnostics and locations.
    /// Manifest bytes also incur the manifest's UTF-16 reader-character limit.
    static func parseStringsManifest(_ input: Data, source: String = "<manifest>",
                                     loadingOptions: LocalizedStringLoadingOptions = .defaults) throws -> StringsManifestV1 {
        guard input.count <= loadingOptions.maximumInputBytes else {
            throw manifestSourceError("localized strings resource exceeds the maximum size of \(loadingOptions.maximumInputBytes) bytes", source: source)
        }
        let text: String
        do { text = try JSONReader.decodeUTF8(input) }
        catch { throw manifestSourceError("localized strings resource is not valid UTF-8", source: source, cause: error) }
        return try parseStringsManifest(text, source: source, loadingOptions: loadingOptions)
    }

    /// Parses source text through the strict, ordered JSON reader. Unknown wire
    /// members are tolerated and omitted from the immutable validated result.
    static func parseStringsManifest(_ input: String, source: String = "<manifest>",
                                     loadingOptions: LocalizedStringLoadingOptions = .defaults) throws -> StringsManifestV1 {
        guard input.utf16.count <= loadingOptions.maximumReaderCharacters else {
            throw manifestSourceError("localized strings resource exceeds the maximum size of \(loadingOptions.maximumReaderCharacters) characters", source: source)
        }
        let text = input.unicodeScalars.first?.value == 0xFEFF ? String(input.unicodeScalars.dropFirst()) : input
        guard text.utf16.contains(where: { $0 != 32 && $0 != 9 && $0 != 10 && $0 != 13 }) else {
            throw manifestSourceError("a localized strings file may not be blank; use an empty JSON object ({}) for an empty file", source: source)
        }
        try ManifestRawParser.checkNesting(text, source: source, maximum: loadingOptions.maximumJsonNestingDepth)
        let parsed: JSONValue
        do {
            parsed = try JSONReader.parse(text, limits: .init(maximumCharacters: max(1, text.utf16.count), maximumDepth: 128,
                                                            maximumNodes: Int.max), allowLeadingBOM: false)
        } catch let readerCause as JSONReadError {
            let cause = ManifestRawParser.syntaxCause(readerCause, text: text)
            throw StringsParseError(message: "\(source):\(cause.location.line):\(cause.location.column): unable to parse localized strings file",
                source: source, line: cause.location.line, column: cause.location.column, cause: cause)
        }
        try ManifestRawParser.checkDuplicates(parsed, source: source)
        return try validateStringsManifest(ManifestRawParser.project(parsed), loadingOptions: loadingOptions)
    }

    /// Semantic object ingress: duplicate supplied members use last-value-wins
    /// object semantics. This door does not invent source diagnostics or budgets.
    static func validateStringsManifest(_ input: StringsManifestValue,
                                        loadingOptions: LocalizedStringLoadingOptions = .defaults) throws -> StringsManifestV1 {
        try ManifestValidator.validate(input, options: loadingOptions)
    }

    /// Revalidates every structural, data-compatibility and identity requirement.
    static func validateStringsManifest(_ input: StringsManifestV1,
                                        loadingOptions: LocalizedStringLoadingOptions = .defaults) throws -> StringsManifestV1 {
        try validateStringsManifest(input.decodedValue, loadingOptions: loadingOptions)
    }
}

private func manifestSourceError(_ message: String, source: String, cause: (any Error)? = nil) -> StringsParseError {
    .init(message: "\(source): \(message)", source: source, cause: cause)
}

private enum ManifestRawParser {
    static func syntaxCause(_ cause: JSONReadError, text: String) -> JSONReadError {
        // The shared reader consumes the unsupported escape before refusing it.
        // The manifest reference reports that code unit while it is current.
        let offset = max(0, cause.location.offset - (cause.reason == "Invalid string escape" ? 1 : 0))
        // CR and LF advance the line; a CRLF pair advances it only once.
        var line = 1, lineOffset = 0, previousWasCR = false
        for (index, unit) in text.utf16.prefix(offset).enumerated() {
            if unit == 13 { line += 1; lineOffset = index + 1 }
            else if unit == 10 { if !previousWasCR { line += 1 }; lineOffset = index + 1 }
            previousWasCR = unit == 13
        }
        return .init(reason: cause.reason, location: .init(offset: offset, line: line, column: offset - lineOffset + 1))
    }
    static func checkNesting(_ input: String, source: String, maximum: Int) throws {
        var depth = 0, quoted = false, escaped = false
        for unit in input.utf16 {
            if quoted {
                if escaped { escaped = false }
                else if unit == 92 { escaped = true }
                else if unit == 34 { quoted = false }
            } else if unit == 34 { quoted = true }
            else if unit == 123 || unit == 91 {
                depth += 1
                if depth > maximum { throw manifestSourceError("JSON nesting depth exceeds the maximum of \(maximum)", source: source) }
            } else if unit == 125 || unit == 93 { depth -= 1 }
        }
    }
    static func checkDuplicates(_ value: JSONValue, source: String) throws {
        if case .object(let members) = value {
            var seen: Set<ExactString> = []
            for member in members where !seen.insert(member.name).inserted {
                throw manifestSourceError("duplicate manifest member '\(member.name)' encountered", source: source)
            }
        }
        try firstNestedDuplicate(value, path: "$", isRoot: true, source: source)
    }
    private static func firstNestedDuplicate(_ value: JSONValue, path: String, isRoot: Bool, source: String) throws {
        switch value {
        case .object(let members):
            var seen: Set<ExactString> = []
            for member in members {
                if !isRoot && !seen.insert(member.name).inserted {
                    throw StringsParseError(message: "\(source): duplicate JSON object member '\(boundedValue(member.name.string))' encountered at \(path)",
                        source: source)
                }
                try firstNestedDuplicate(member.value, path: boundedPath(path, ".", member.name.string, ""), isRoot: false, source: source)
            }
        case .array(let values):
            for (index, value) in values.enumerated() {
                try firstNestedDuplicate(value, path: boundedPath(path, "[", String(index), "]"), isRoot: false, source: source)
            }
        default: break
        }
    }
    private static func boundedValue(_ value: String) -> String {
        let units = Array(value.utf16.prefix(257))
        return units.count <= 256 ? value : String(decoding: units.prefix(255), as: UTF16.self) + "…"
    }
    private static func boundedPath(_ parts: String...) -> String {
        var result = "", remaining = 4_096
        for part in parts where remaining > 0 {
            let prefix = Array(part.utf16.prefix(remaining + 1))
            if prefix.count > remaining {
                result += String(decoding: prefix.prefix(remaining - 1), as: UTF16.self) + "…"
                remaining = 0
            } else {
                result += part; remaining -= prefix.count
            }
        }
        return result
    }
    static func project(_ value: JSONValue) -> StringsManifestValue {
        switch value {
        case .object(let members): return .object(members.map { .init(name: $0.name, value: project($0.value)) })
        case .array(let values): return .array(values.map(project))
        case .string(let value): return .string(value)
        // JSON schema numbers follow JavaScript Number projection deliberately.
        case .number(let value): return .number(Double(value) ?? .nan)
        case .bool(let value): return .bool(value)
        case .null: return .null
        }
    }
}

/// A decoded object's property semantics: last value wins, first position stays;
/// array-index property names precede other names in numeric order.
private struct ManifestObject {
    let members: [StringsManifestMember]
    private let values: [ExactString: StringsManifestValue]
    init?(_ value: StringsManifestValue?) {
        guard case .object(let incoming) = value else { return nil }
        var members: [StringsManifestMember] = [], indexes: [ExactString: Int] = [:]
        for member in incoming {
            if let index = indexes[member.name] { members[index] = member }
            else { indexes[member.name] = members.count; members.append(member) }
        }
        var indexed: [(UInt32, StringsManifestMember)] = [], ordinary: [StringsManifestMember] = []
        for member in members {
            if let index = Self.arrayIndex(member.name.string) { indexed.append((index, member)) }
            else { ordinary.append(member) }
        }
        indexed.sort { $0.0 < $1.0 }
        self.members = indexed.map(\.1) + ordinary
        values = Dictionary(self.members.map { ($0.name, $0.value) }, uniquingKeysWith: { _, last in last })
    }
    subscript(_ name: ExactString) -> StringsManifestValue? { values[name] }
    private static func arrayIndex(_ name: String) -> UInt32? {
        let bytes = Array(name.utf8)
        guard !bytes.isEmpty, bytes.count <= 10, bytes.allSatisfy({ (48...57).contains($0) }),
              bytes.count == 1 || bytes.first != 48, let value = UInt32(name), value < UInt32.max else { return nil }
        return value
    }
}

private enum ManifestValidator {
    static func refusal(_ message: String) -> ConfigurationError { .init(kind: .invalidArgument, message: message) }
    private static func urlRefusal(_ message: String, cause: any Error) -> ConfigurationError {
        // Unsupported host processing is an unfinished native capability, not
        // evidence that the shared manifest's URL is malformed.
        if let failure = cause as? ManifestURL.Failure, case .unsupportedFeature = failure.kind {
            return .init(kind: .invalidArgument, message: message, cause: failure)
        }
        return refusal(message)
    }
    static func string(_ value: StringsManifestValue?) -> String? { if case .string(let text) = value { return text }; return nil }
    static func nonempty(_ value: StringsManifestValue?) -> String? { string(value).flatMap { $0.isEmpty ? nil : $0 } }
    static func digest(_ value: StringsManifestValue?) -> String? {
        guard let text = string(value), CatalogIdentityCanonicalizer.isDigest(text) else { return nil }
        return text
    }
    static func version(_ value: StringsManifestValue?) -> String? {
        guard let text = string(value), !text.isEmpty else { return nil }
        var needsDigit = true
        for unit in text.utf8 {
            if (48...57).contains(unit) { needsDigit = false }
            else if unit == 46 && !needsDigit { needsDigit = true }
            else { return nil }
        }
        return needsDigit ? nil : text
    }
    static func requireTag(_ value: StringsManifestValue?, where description: String) throws -> String {
        guard let text = nonempty(value) else { throw refusal("\(description) must be a non-empty locale tag") }
        do {
            guard CldrLocaleData.isKnownLanguageTag(text) else { throw refusal("\(description) is '\(text)', which is not a valid pinned-data-known locale tag") }
            _ = try LocaleTag(text)
            return try ManifestLocale.normalizeTag(text)
        } catch {
            throw refusal("\(description) is '\(text)', which is not a valid pinned-data-known locale tag")
        }
    }
    static func validate(_ value: StringsManifestValue, options: LocalizedStringLoadingOptions) throws -> StringsManifestV1 {
        guard let input = ManifestObject(value) else { throw refusal("A strings manifest must be an object") }
        guard case .number(let format) = input["formatVersion"], format == 1 else {
            throw refusal("A strings manifest must declare formatVersion 1; received \(ManifestDiagnostic.render(input["formatVersion"]))")
        }
        guard let catalogVersion = nonempty(input["catalogVersion"]) else { throw refusal("A strings manifest must carry a non-empty catalogVersion") }
        guard let catalogFingerprint = digest(input["catalogFingerprint"]) else { throw refusal("A manifest's catalogFingerprint must be a full lowercase hexadecimal SHA-256") }
        let identity = try runtimeIdentity(input)
        let fallback = try requireTag(input["fallbackLocale"], where: "A manifest's fallbackLocale")
        guard let baseURL = string(input["baseUrl"]) else { throw refusal("A manifest's baseUrl must be a string") }
        let resolvedBase: String
        do { resolvedBase = try ManifestURL.resolve(baseURL) }
        catch { throw urlRefusal("A manifest's baseUrl must be an absolute URL; received \(ManifestDiagnostic.render(.string(baseURL)))", cause: error) }
        let baseScheme = scheme(resolvedBase)
        guard allowedSchemes.contains(baseScheme) else { throw refusal("A manifest's baseUrl must be http:, https: or file:; received '\(baseScheme)'") }
        guard let rawFiles = ManifestObject(input["files"]) else { throw refusal("A manifest's files must be an object") }
        guard rawFiles.members.count <= options.maximumLocalizedStringsFiles else {
            throw refusal("A manifest declares \(rawFiles.members.count) files, which exceeds the maximum of \(options.maximumLocalizedStringsFiles)")
        }
        var files: [ExactString: StringsManifestFile] = [:], fileOrder: [String] = []
        for member in rawFiles.members {
            let tag = try requireTag(.string(member.name.string), where: "A manifest file key")
            let key = ExactString(tag)
            guard files[key] == nil else { throw refusal("A manifest declares two file keys that normalize to '\(tag)'") }
            guard let entry = ManifestObject(member.value) else { throw refusal("The manifest entry for '\(tag)' must be an object") }
            guard let url = nonempty(entry["url"]) else { throw refusal("The manifest entry for '\(tag)' must carry a non-empty url") }
            let resolved: String
            do { resolved = try ManifestURL.resolve(url, relativeTo: baseURL) }
            catch { throw urlRefusal("The url for '\(tag)' does not resolve against the manifest baseUrl", cause: error) }
            let resolvedScheme = scheme(resolved)
            guard allowedSchemes.contains(resolvedScheme) else { throw refusal("The resolved url for '\(tag)' has scheme '\(resolvedScheme)', which a manifest may not name") }
            guard let sha256 = digest(entry["sha256"]) else { throw refusal("The sha256 for '\(tag)' must be a full lowercase hexadecimal SHA-256") }
            var decodedBytes: Int?
            if let decoded = entry["decodedBytes"] {
                guard case .number(let number) = decoded, number.isFinite, number >= 0,
                      number.rounded(.towardZero) == number, number <= 9_007_199_254_740_991 else {
                    throw refusal("The decodedBytes for '\(tag)' must be a non-negative integer")
                }
                decodedBytes = Int(number)
            }
            files[key] = .init(url: url, sha256: sha256, decodedBytes: decodedBytes)
            fileOrder.append(tag)
        }
        guard let rawTies = ManifestObject(input["tiebreakerLocalesByLanguageCode"]) else {
            throw refusal("A manifest's tiebreakerLocalesByLanguageCode must be an object")
        }
        var ties: [ExactString: [String]] = [:], tieOrder: [String] = []
        for member in rawTies.members {
            let tag = try requireTag(.string(member.name.string), where: "A manifest tiebreaker key")
            guard case .array(let candidates) = member.value else { throw refusal("The tiebreakerLocalesByLanguageCode for '\(tag)' must be an array of locale tags") }
            let normalized = try candidates.enumerated().map { try requireTag($0.element, where: "The tiebreaker for '\(tag)' at index \($0.offset)") }
            if ties[ExactString(tag)] == nil { tieOrder.append(tag) }
            ties[ExactString(tag)] = normalized
        }
        try validateTiebreakers(files: fileOrder, ties: ties, tieOrder: tieOrder)
        let sortedFiles = fileOrder.sorted { ExactString($0) < ExactString($1) }
        let equivalent = sortedFiles.filter { CldrLocaleData.equivalentTags($0, fallback) }
        guard !equivalent.isEmpty else {
            throw refusal("A manifest's fallbackLocale is '\(fallback)' but no matching catalog was declared. Known locales: \(list(sortedFiles))")
        }
        let resolvedFallback: String
        if sortedFiles.contains(where: { ExactString($0) == ExactString(fallback) }) { resolvedFallback = fallback }
        else if equivalent.count == 1 { resolvedFallback = equivalent[0] }
        else {
            let language = MatchingLocale.normalizedLanguageCode(MatchingLocale.split(CldrLocaleData.canonicalLanguageTag(fallback)).first ?? "")
            guard let elected = ties[ExactString(language)]?.first(where: { candidate in equivalent.contains(where: { ExactString($0) == ExactString(candidate) }) }) else {
                throw refusal("A manifest's fallbackLocale '\(fallback)' is canonically equivalent to multiple declared locales \(list(equivalent)); declare it as one of them exactly")
            }
            resolvedFallback = elected
        }
        let manifest = StringsManifestV1(catalogVersion: catalogVersion, catalogFingerprint: catalogFingerprint,
            cldrVersion: identity.cldrVersion, dataFingerprint: identity.dataFingerprint,
            behavioralVectorsVersion: identity.behavioralVectorsVersion, localeDataMode: identity.localeDataMode,
            cardinalityMode: identity.cardinalityMode, ianaRegistryDate: identity.ianaRegistryDate,
            ianaDataFingerprint: identity.ianaDataFingerprint, fallbackLocale: resolvedFallback,
            baseUrl: baseURL, files: files, tiebreakerLocalesByLanguageCode: ties)
        let recomputed = try LocalizedStringLoader.computeCatalogIdentity(catalogIdentityInputFor(manifest)).catalogFingerprint
        guard ExactString(recomputed) == ExactString(catalogFingerprint) else {
            throw refusal("A manifest's declared catalogFingerprint does not match its contents: declared \(catalogFingerprint), computed \(recomputed)")
        }
        return manifest
    }
    private static let allowedSchemes: Set<String> = ["http:", "https:", "file:"]
    private static func scheme(_ url: String) -> String { String(url.prefix { $0 != ":" }) + ":" }
    private static func list(_ values: [String]) -> String { "[\(values.joined(separator: ", "))]" }
    private static func primary(_ tag: String) -> String {
        let parts = JDKLocaleTag.parse(tag)
        let language = parts.extlangs.first ?? parts.language
        if language.isEmpty || language == "und" { return "" }
        let canonical = CldrLocaleData.canonicalLanguageTag(LocaleTag.forLanguageTag(tag).tag)
        if canonical.lowercased().hasPrefix("x-") || canonical.lowercased() == "x" { return "" }
        let projected = MatchingLocale.split(canonical).first ?? ""
        return projected.lowercased() == "und" ? "" : projected
    }
    private static func validateTiebreakers(files: [String], ties: [ExactString: [String]], tieOrder: [String]) throws {
        var languages: [String] = [], declared: [ExactString: [String]] = [:]
        for tag in files {
            let language = primary(tag)
            if language.isEmpty { continue }
            let key = ExactString(language)
            if declared[key] == nil { languages.append(language) }
            declared[key, default: []].append(tag)
        }
        for language in languages {
            let tags = declared[ExactString(language)]!
            if tags.count > 1 && ties[ExactString(language)] == nil {
                throw refusal("The manifest declares \(tags.count) files for '\(language)' \(list(tags)) and no tiebreakerLocalesByLanguageCode for it, so no instance could resolve between them")
            }
        }
        for language in tieOrder {
            let key = ExactString(language), candidates = ties[key]!
            guard let tags = declared[key] else { throw refusal("The manifest declares tiebreakerLocalesByLanguageCode for '\(language)' but no file for that language") }
            var seen: Set<ExactString> = []
            for candidate in candidates where !seen.insert(ExactString(candidate)).inserted {
                throw refusal("The tiebreakerLocalesByLanguageCode for '\(language)' name '\(candidate)' twice; this list is a resolution order, so a repeat has no recoverable meaning")
            }
            let unrelated = candidates.filter { candidate in !tags.contains(where: { ExactString($0) == ExactString(candidate) }) }
            let missing = tags.filter { !seen.contains(ExactString($0)) }
            if !unrelated.isEmpty || !missing.isEmpty {
                throw refusal("The tiebreakerLocalesByLanguageCode for '\(language)' must be an exact permutation of the files the manifest declares for that language \(list(tags)); missing: \(list(missing)); unrelated: \(list(unrelated))")
            }
        }
    }
    private static func runtimeIdentity(_ input: ManifestObject) throws -> Identity {
        guard let cldr = version(input["cldrVersion"]) else { throw refusal("A manifest's cldrVersion must be a CLDR version; received \(ManifestDiagnostic.render(input["cldrVersion"]))") }
        guard let data = digest(input["dataFingerprint"]) else { throw refusal("A manifest's dataFingerprint must be a full lowercase hexadecimal SHA-256") }
        let build = BuildMetadata.current
        guard ExactString(cldr) == ExactString(build.cldrVersion), ExactString(data) == ExactString(build.dataFingerprint) else {
            throw refusal("This manifest was published against CLDR \(cldr) / \(data.prefix(12))…, and this build carries CLDR \(build.cldrVersion) / \(build.dataFingerprint.prefix(12))…. Plural rules and locale identity come from that data, so the catalogs would render differently even though the file plan matches.")
        }
        guard string(input["localeDataMode"]) == "pinned" else { throw refusal("A manifest's localeDataMode must be \"pinned\"; received \(ManifestDiagnostic.render(input["localeDataMode"]))") }
        guard string(input["cardinalityMode"]) == "exact" else { throw refusal("A manifest's cardinalityMode must be \"exact\"; received \(ManifestDiagnostic.render(input["cardinalityMode"]))") }
        guard let vectors = version(input["behavioralVectorsVersion"]) else { throw refusal("A manifest's behavioralVectorsVersion must be a version; received \(ManifestDiagnostic.render(input["behavioralVectorsVersion"]))") }
        guard let ianaDate = nonempty(input["ianaRegistryDate"]) else { throw refusal("A manifest's ianaRegistryDate must be a non-empty identity string; received \(ManifestDiagnostic.render(input["ianaRegistryDate"]))") }
        guard let ianaData = digest(input["ianaDataFingerprint"]) else { throw refusal("A manifest's ianaDataFingerprint must be a full lowercase hexadecimal SHA-256") }
        guard ExactString(vectors) == ExactString(build.behavioralVectorsVersion), ExactString(ianaDate) == ExactString(build.ianaRegistryDate), ExactString(ianaData) == ExactString(build.ianaDataFingerprint) else {
            throw refusal("This manifest was published against IANA \(ianaDate) / \(ianaData.prefix(12))… and vectors \(vectors), and this build carries \(build.ianaRegistryDate) / \(build.ianaDataFingerprint.prefix(12))… and vectors \(build.behavioralVectorsVersion). Range equivalence and whole-list matching come from that IANA data, so the two builds can negotiate a visitor to different catalogs even though every file digest matches.")
        }
        return .init(cldrVersion: cldr, dataFingerprint: data, behavioralVectorsVersion: vectors, localeDataMode: "pinned", cardinalityMode: "exact", ianaRegistryDate: ianaDate, ianaDataFingerprint: ianaData)
    }
    private struct Identity {
        let cldrVersion: String, dataFingerprint: String, behavioralVectorsVersion: String
        let localeDataMode: String, cardinalityMode: String, ianaRegistryDate: String, ianaDataFingerprint: String
    }
}

/// JSON.stringify-shaped received-value diagnostics. This is not the JCS engine.
private enum ManifestDiagnostic {
    static func render(_ value: StringsManifestValue?) -> String {
        guard let value else { return "undefined" }
        var tasks: [Task] = [.value(value)], output = ""
        while let task = tasks.popLast() {
            switch task {
            case .text(let text): output += text
            case .value(let value):
                switch value {
                case .string(let text): output += quote(text)
                case .number(let number): output += numberText(number)
                case .bool(let flag): output += flag ? "true" : "false"
                case .null: output += "null"
                case .array(let values):
                    output += "["; tasks.append(.text("]"))
                    for index in values.indices.reversed() {
                        tasks.append(.value(values[index]))
                        if index > 0 { tasks.append(.text(",")) }
                    }
                case .object:
                    let members = ManifestObject(value)!.members
                    output += "{"; tasks.append(.text("}"))
                    for index in members.indices.reversed() {
                        tasks.append(.value(members[index].value))
                        tasks.append(.text(":")); tasks.append(.text(quote(members[index].name.string)))
                        if index > 0 { tasks.append(.text(",")) }
                    }
                }
            }
        }
        return output
    }
    private enum Task { case text(String), value(StringsManifestValue) }
    static func quote(_ text: String) -> String {
        CatalogIdentityCanonicalizer.quote(text)
    }
    private static func numberText(_ value: Double) -> String {
        guard value.isFinite else { return "null" }
        if value == 0 { return "0" }
        let negative = value < 0
        let raw = String(value.magnitude).lowercased().split(separator: "e", omittingEmptySubsequences: false)
        let coefficient = String(raw[0]), parts = coefficient.split(separator: ".", omittingEmptySubsequences: false)
        var digits = parts.joined(), exponent = (raw.count > 1 ? Int(raw[1]) ?? 0 : 0) - (parts.count > 1 ? parts[1].count : 0)
        while digits.last == "0" { digits.removeLast(); exponent += 1 }
        while digits.first == "0" { digits.removeFirst() }
        let scientific = digits.count - 1 + exponent, sign = negative ? "-" : ""
        if scientific >= 21 || scientific < -6 {
            let first = digits.removeFirst()
            return sign + String(first) + (digits.isEmpty ? "" : "." + digits) + "e" + (scientific >= 0 ? "+" : "") + String(scientific)
        }
        if exponent >= 0 { return sign + digits + String(repeating: "0", count: exponent) }
        let point = digits.count + exponent
        if point <= 0 { return sign + "0." + String(repeating: "0", count: -point) + digits }
        let cut = digits.index(digits.startIndex, offsetBy: point)
        return sign + digits[..<cut] + "." + digits[cut...]
    }
}
